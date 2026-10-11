import CoreGraphics
import Foundation

/// What the page script reports: the viewport's geometry and every element
/// in view that shows an image. Decoded from the script's JSON.
public struct PageScan: Codable, Sendable {
    public struct Metrics: Codable, Sendable {
        public var innerWidth: Double
        public var innerHeight: Double
        public var devicePixelRatio: Double
        public var baseURL: String
    }

    public struct Element: Codable, Sendable {
        public enum Kind: String, Codable, Sendable { case img, background, svg, poster }
        public var kind: Kind
        /// Viewport rectangle in CSS pixels, origin top-left.
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var src: String?
        public var currentSrc: String?
        public var srcsets: [String]?
        public var background: String?
        public var svg: String?
    }

    public var metrics: Metrics
    public var elements: [Element]

    /// Resolved images, without anything smaller than `minimumSide` CSS pixels
    /// and without repeats of the same source over the same area.
    public func images(minimumSide: Double = 16) -> [PageImage] {
        let base = URL(string: metrics.baseURL)
        var seen = Set<String>()
        var images: [PageImage] = []
        for element in elements where element.width >= minimumSide && element.height >= minimumSide {
            let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
            for source in sources(of: element, base: base) {
                let key = "\(source.key)|\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
                guard seen.insert(key).inserted else { continue }
                images.append(PageImage(source: source, rect: rect, kind: element.kind))
            }
        }
        return images
    }

    private func sources(of element: Element, base: URL?) -> [PageImage.Source] {
        func resolve(_ string: String?) -> PageImage.Source? {
            guard let string, !string.isEmpty, let url = URL(string: string, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), ["http", "https", "data", "blob"].contains(scheme) else { return nil }
            return .url(url)
        }
        switch element.kind {
        case .img:
            return [resolve(ImageSourceParsing.bestImageSource(srcsets: element.srcsets ?? [], currentSrc: element.currentSrc, src: element.src))].compactMap { $0 }
        case .background:
            return ImageSourceParsing.backgroundURLs(element.background ?? "").compactMap(resolve)
        case .poster:
            return [resolve(element.src)].compactMap { $0 }
        case .svg:
            return element.svg.map { [.svg($0)] } ?? []
        }
    }
}

public struct PageImage: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case url(URL)
        /// Serialised inline `<svg>` markup.
        case svg(String)

        var key: String {
            switch self {
            case let .url(url): url.absoluteString
            case let .svg(markup): "svg:\(markup.hashValue)"
            }
        }
    }

    public var source: Source
    /// Viewport rectangle in CSS pixels, origin top-left.
    public var rect: CGRect
    public var kind: PageScan.Element.Kind
}

/// Places viewport CSS pixels on screen. Page zoom shows up in
/// `devicePixelRatio`, so one CSS pixel is `devicePixelRatio / backingScale`
/// points. Browser chrome is assumed to sit above the page and, when a
/// sidebar is open, to its left.
public struct ViewportMapping: Sendable {
    /// Viewport rectangle in global points, origin top-left of the main display.
    public let viewport: CGRect
    public let pointsPerCSSPixel: Double

    /// `windowFrame` is the browser window in global points, origin top-left (as CGWindowList reports it).
    public init(metrics: PageScan.Metrics, windowFrame: CGRect, backingScale: Double) {
        pointsPerCSSPixel = metrics.devicePixelRatio / max(backingScale, 1)
        let size = CGSize(width: metrics.innerWidth * pointsPerCSSPixel, height: metrics.innerHeight * pointsPerCSSPixel)
        viewport = CGRect(x: windowFrame.maxX - size.width, y: windowFrame.maxY - size.height, width: size.width, height: size.height)
    }

    public func screenRect(for cssRect: CGRect) -> CGRect {
        CGRect(x: viewport.minX + cssRect.minX * pointsPerCSSPixel,
               y: viewport.minY + cssRect.minY * pointsPerCSSPixel,
               width: cssRect.width * pointsPerCSSPixel,
               height: cssRect.height * pointsPerCSSPixel)
    }
}

public enum WebImageFilename {
    /// The URL's own filename, percent-decoded, with an extension from the MIME
    /// type when the path has none: `hero@2x.webp`, `image.png`.
    public static func name(for url: URL?, mimeType: String?) -> String {
        let fallbackExtension = mimeType.flatMap(fileExtension(forMIMEType:))
        var name = ""
        if let url, url.scheme?.lowercased() != "data" {
            name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            if name == "/" { name = "" }
        }
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if name.isEmpty { name = "image" }
        if (name as NSString).pathExtension.isEmpty, let fallbackExtension {
            name += ".\(fallbackExtension)"
        }
        return name
    }

    /// The name used when only a screenshot of the element could be had.
    public static func renderedCopyName(for url: URL?) -> String {
        let original = (name(for: url, mimeType: nil) as NSString).deletingPathExtension
        return "\(original) (rendered copy).png"
    }

    public static func fileExtension(forMIMEType mimeType: String) -> String? {
        let type = mimeType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return [
            "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg", "image/webp": "webp", "image/gif": "gif",
            "image/avif": "avif", "image/svg+xml": "svg", "image/heic": "heic", "image/bmp": "bmp", "image/tiff": "tiff",
            "image/x-icon": "ico", "image/vnd.microsoft.icon": "ico",
        ][type]
    }
}

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageCoding {
    /// PNG with DPI set to 72 × scale, so apps show a Retina capture at its on-screen size.
    static func png(_ image: CGImage, scale: CGFloat) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return Data() }
        let dpi = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The first frame of anything ImageIO reads (PNG, JPEG, WebP, AVIF, GIF, HEIC).
    /// SVG goes through NSImage and is rasterised at `rasterScale` pixels per point.
    static func decode(_ data: Data, rasterScale: CGFloat) -> CGImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        guard let vector = NSImage(data: data), vector.size.width >= 1, vector.size.height >= 1 else { return nil }
        let width = Int((vector.size.width * rasterScale).rounded())
        let height = Int((vector.size.height * rasterScale).rounded())
        guard let context = bitmapContext(width: width, height: height, colorSpace: nil) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        vector.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    static func resized(_ image: CGImage, by factor: CGFloat) -> CGImage {
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let context = bitmapContext(width: width, height: height, colorSpace: image.colorSpace) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func bitmapContext(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

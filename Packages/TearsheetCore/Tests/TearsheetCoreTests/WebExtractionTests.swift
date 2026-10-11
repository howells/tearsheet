import CoreGraphics
import Foundation
import Testing
@testable import TearsheetCore

struct BackgroundParsingTests {
    @Test func readsQuotedAndBareURLs() {
        #expect(ImageSourceParsing.backgroundURLs(#"url("https://a.test/x.png")"#) == ["https://a.test/x.png"])
        #expect(ImageSourceParsing.backgroundURLs("url(https://a.test/x.png)") == ["https://a.test/x.png"])
        #expect(ImageSourceParsing.backgroundURLs("url('y.jpg')") == ["y.jpg"])
    }

    @Test func keepsEveryImageLayerAndSkipsGradients() {
        let value = #"linear-gradient(rgba(0, 0, 0, 0.5), transparent), url("https://a.test/top.png"), url("https://a.test/bottom.jpg")"#
        #expect(ImageSourceParsing.backgroundURLs(value) == ["https://a.test/top.png", "https://a.test/bottom.jpg"])
    }

    @Test func ignoresNone() {
        #expect(ImageSourceParsing.backgroundURLs("none").isEmpty)
        #expect(ImageSourceParsing.backgroundURLs("").isEmpty)
    }

    @Test func picksDensestImageSetOption() {
        let value = #"image-set(url("https://a.test/1x.png") 1x, url("https://a.test/2x.png") 2x)"#
        #expect(ImageSourceParsing.backgroundURLs(value) == ["https://a.test/2x.png"])
        let webkit = #"-webkit-image-set(url("a.png") 1x, url("b.png") 3dppx, url("c.png") 192dpi)"#
        #expect(ImageSourceParsing.backgroundURLs(webkit) == ["b.png"])
        let strings = #"image-set("a.avif" type("image/avif") 2x, "a.jpg" 1x)"#
        #expect(ImageSourceParsing.backgroundURLs(strings) == ["a.avif"])
    }

    @Test func keepsCommasInsideDataURLs() {
        let value = #"url("data:image/png;base64,AAAA"), url("b.png")"#
        #expect(ImageSourceParsing.backgroundURLs(value) == ["data:image/png;base64,AAAA", "b.png"])
    }
}

struct SrcsetParsingTests {
    @Test func picksWidestByWidthDescriptor() {
        #expect(ImageSourceParsing.largestSource(inSrcset: "s.jpg 320w, l.jpg 1600w, m.jpg 800w") == "l.jpg")
    }

    @Test func picksDensestByDensity() {
        #expect(ImageSourceParsing.largestSource(inSrcset: "a.jpg, b.jpg 2x, c.jpg 1.5x") == "b.jpg")
    }

    @Test func handlesCommasInURLs() {
        let srcset = "https://cdn.test/w_400,q_80/a.jpg 400w, https://cdn.test/w_1200,q_80/a.jpg 1200w"
        #expect(ImageSourceParsing.largestSource(inSrcset: srcset) == "https://cdn.test/w_1200,q_80/a.jpg")
    }

    @Test func prefersPictureSourcesOverSmallerCurrentSource() {
        let best = ImageSourceParsing.bestImageSource(srcsets: ["hero-800.webp 800w, hero-2400.webp 2400w", "hero.jpg 1x"], currentSrc: "hero-800.webp", src: "hero.jpg")
        #expect(best == "hero-2400.webp")
    }

    @Test func fallsBackToCurrentSourceThenSource() {
        #expect(ImageSourceParsing.bestImageSource(srcsets: [], currentSrc: "a.png", src: "b.png") == "a.png")
        #expect(ImageSourceParsing.bestImageSource(srcsets: [], currentSrc: "", src: "b.png") == "b.png")
        #expect(ImageSourceParsing.bestImageSource(srcsets: ["x.png 1x"], currentSrc: "a.png", src: nil) == "a.png")
    }
}

struct PageScanTests {
    func element(_ kind: PageScan.Element.Kind, width: Double = 200, height: Double = 100, src: String? = nil,
                 background: String? = nil, svg: String? = nil) -> PageScan.Element {
        PageScan.Element(kind: kind, x: 10, y: 20, width: width, height: height, src: src, currentSrc: src, srcsets: nil, background: background, svg: svg)
    }

    func scan(_ elements: [PageScan.Element]) -> PageScan {
        PageScan(metrics: .init(innerWidth: 1200, innerHeight: 800, devicePixelRatio: 2, baseURL: "https://site.test/journal/post"), elements: elements)
    }

    @Test func decodesTheScriptsJSON() throws {
        let json = #"{"metrics":{"innerWidth":1200,"innerHeight":800,"devicePixelRatio":2,"baseURL":"https://site.test/"},"elements":[{"kind":"img","x":0,"y":0,"width":50,"height":50,"src":"a.png","currentSrc":"a.png","srcsets":[]}]}"#
        let scan = try JSONDecoder().decode(PageScan.self, from: Data(json.utf8))
        #expect(scan.images().first?.source == .url(URL(string: "https://site.test/a.png")!))
    }

    @Test func resolvesRelativeURLsAgainstThePage() {
        let images = scan([element(.img, src: "../img/heron.jpg")]).images()
        #expect(images.map(\.source) == [.url(URL(string: "https://site.test/img/heron.jpg")!)])
    }

    @Test func skipsTinyImagesAndUnfetchableSchemes() {
        let images = scan([
            element(.img, width: 12, height: 12, src: "icon.png"),
            element(.img, src: "javascript:void(0)"),
            element(.background, background: #"url("data:image/png;base64,AAAA")"#),
        ]).images()
        #expect(images.count == 1)
        #expect(images.first?.kind == .background)
    }

    @Test func dropsRepeatsOfTheSameImageOverTheSameArea() {
        let images = scan([element(.img, src: "a.png"), element(.img, src: "a.png"), element(.poster, src: "poster.jpg")]).images()
        #expect(images.count == 2)
    }

    @Test func keepsInlineSVGMarkup() {
        let images = scan([element(.svg, svg: "<svg xmlns=\"http://www.w3.org/2000/svg\"/>")]).images()
        #expect(images.first?.source == .svg("<svg xmlns=\"http://www.w3.org/2000/svg\"/>"))
    }
}

struct ViewportMappingTests {
    let metrics = PageScan.Metrics(innerWidth: 1200, innerHeight: 700, devicePixelRatio: 2, baseURL: "")

    @Test func placesTheViewportBelowTheToolbar() {
        let mapping = ViewportMapping(metrics: metrics, windowFrame: CGRect(x: 100, y: 50, width: 1200, height: 780), backingScale: 2)
        #expect(mapping.viewport == CGRect(x: 100, y: 130, width: 1200, height: 700))
        #expect(mapping.screenRect(for: CGRect(x: 10, y: 20, width: 300, height: 200)) == CGRect(x: 110, y: 150, width: 300, height: 200))
    }

    @Test func accountsForPageZoom() {
        // 150% zoom on a 2x display: devicePixelRatio 3, and the viewport is 2/3 as many CSS pixels wide.
        let zoomed = PageScan.Metrics(innerWidth: 800, innerHeight: 400, devicePixelRatio: 3, baseURL: "")
        let mapping = ViewportMapping(metrics: zoomed, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 680), backingScale: 2)
        #expect(mapping.pointsPerCSSPixel == 1.5)
        #expect(mapping.screenRect(for: CGRect(x: 100, y: 0, width: 100, height: 100)) == CGRect(x: 150, y: 80, width: 150, height: 150))
    }

    @Test func putsSidebarWidthOnTheLeft() {
        let mapping = ViewportMapping(metrics: metrics, windowFrame: CGRect(x: 0, y: 0, width: 1500, height: 780), backingScale: 2)
        #expect(mapping.viewport.minX == 300)
    }
}

struct WebImageFilenameTests {
    @Test func keepsTheURLsFilename() {
        #expect(WebImageFilename.name(for: URL(string: "https://cdn.test/a/hero@2x.webp?v=3"), mimeType: "image/webp") == "hero@2x.webp")
        #expect(WebImageFilename.name(for: URL(string: "https://cdn.test/Salt%20marsh.jpg"), mimeType: nil) == "Salt marsh.jpg")
    }

    @Test func addsAnExtensionFromTheMIMEType() {
        #expect(WebImageFilename.name(for: URL(string: "https://cdn.test/images/12345"), mimeType: "image/jpeg") == "12345.jpg")
        #expect(WebImageFilename.name(for: URL(string: "data:image/png;base64,AAAA"), mimeType: "image/png") == "image.png")
        #expect(WebImageFilename.name(for: URL(string: "https://cdn.test/"), mimeType: "image/svg+xml; charset=utf-8") == "image.svg")
    }

    @Test func labelsRenderedCopies() {
        #expect(WebImageFilename.renderedCopyName(for: URL(string: "https://cdn.test/hero.webp")) == "hero (rendered copy).png")
    }
}

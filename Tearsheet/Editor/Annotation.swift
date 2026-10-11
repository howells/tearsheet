import AppKit

enum AnnotationTool: CaseIterable {
    case arrow, rectangle, text, counter, pixelate, highlighter, crop

    var key: String {
        switch self {
        case .arrow: "a"
        case .rectangle: "r"
        case .text: "t"
        case .counter: "n"
        case .pixelate: "p"
        case .highlighter: "h"
        case .crop: "c"
        }
    }

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .counter: "1.circle"
        case .pixelate: "checkerboard.rectangle"
        case .highlighter: "highlighter"
        case .crop: "crop"
        }
    }

    var label: String {
        switch self {
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .text: "Text"
        case .counter: "Counter"
        case .pixelate: "Pixelate"
        case .highlighter: "Highlighter"
        case .crop: "Crop"
        }
    }
}

enum AnnotationColor: Int, CaseIterable, Sendable {
    case red, amber, green, blue, graphite, paper

    var nsColor: NSColor {
        switch self {
        case .red: NSColor(srgbRed: 1.0, green: 0.231, blue: 0.184, alpha: 1)
        case .amber: NSColor(srgbRed: 1.0, green: 0.690, blue: 0.125, alpha: 1)
        case .green: NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        case .blue: NSColor(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)
        case .graphite: NSColor(srgbRed: 0.227, green: 0.227, blue: 0.247, alpha: 1)
        case .paper: Self.paperColor
        }
    }

    static let paperColor = NSColor(srgbRed: 0.957, green: 0.949, blue: 0.933, alpha: 1)
    static let inkColor = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)

    /// Light inks (amber, paper) take a dark halo and dark lettering; the rest take paper.
    private var isLight: Bool { self == .amber || self == .paper }

    /// The thin outline around every stroke that keeps it legible on any screenshot.
    var halo: NSColor { isLight ? Self.inkColor.withAlphaComponent(0.75) : Self.paperColor }

    /// Lettering drawn on top of this colour: counter numerals and boxed text.
    var contrasting: NSColor { isLight ? Self.inkColor : Self.paperColor }
}

/// One pen at three sizes. Values are points at 1x; multiply by the capture's scale for pixels.
enum StrokeSize: Int, CaseIterable, Sendable {
    case small, medium, large

    var stroke: CGFloat { [2, 3, 4.5][rawValue] }
    /// Halo width on each side of the stroke.
    var halo: CGFloat { [1, 1.5, 2][rawValue] }
    var arrowArm: CGFloat { [10, 15, 22][rawValue] }
    var cornerRadius: CGFloat { [4, 6, 8][rawValue] }
    var counterDiameter: CGFloat { [18, 26, 36][rawValue] }
    var numeralPoints: CGFloat { [11, 15, 21][rawValue] }
    var textPoints: CGFloat { [13, 17, 24][rawValue] }
    var pixelBlock: CGFloat { [6, 10, 16][rawValue] }
    /// The highlighter is a broad marker, not the pen.
    var marker: CGFloat { [14, 22, 34][rawValue] }
}

enum TextStyle: Equatable, Sendable {
    case outline, background
}

/// Coordinates are pixels of the original capture, origin bottom-left.
struct Annotation: Identifiable, Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        /// `origin` is the top-left corner of the text box.
        case text(origin: CGPoint, string: String, style: TextStyle)
        case counter(center: CGPoint)
        case pixelate(CGRect)
        case highlighter([CGPoint])
    }

    var id = UUID()
    var shape: Shape
    var color: AnnotationColor
    var size: StrokeSize

    func translated(by delta: CGVector) -> Annotation {
        func move(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        var copy = self
        switch shape {
        case let .arrow(from, to): copy.shape = .arrow(from: move(from), to: move(to))
        case let .rectangle(rect): copy.shape = .rectangle(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .text(origin, string, style): copy.shape = .text(origin: move(origin), string: string, style: style)
        case let .counter(center): copy.shape = .counter(center: move(center))
        case let .pixelate(rect): copy.shape = .pixelate(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .highlighter(points): copy.shape = .highlighter(points.map(move))
        }
        return copy
    }

    var isCounter: Bool {
        if case .counter = shape { true } else { false }
    }
}

struct AnnotationDocument: Sendable {
    var annotations: [Annotation] = []
    /// Pixel rectangle to keep, origin bottom-left; nil keeps the whole capture.
    var crop: CGRect?

    /// Counters number themselves in the order they were placed.
    func counterNumber(for id: UUID) -> Int {
        var number = 0
        for annotation in annotations where annotation.isCounter {
            number += 1
            if annotation.id == id { return number }
        }
        return number + 1
    }
}

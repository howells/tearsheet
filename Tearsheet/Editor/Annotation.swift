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
    case red, yellow, green, blue, black, white

    var nsColor: NSColor {
        switch self {
        case .red: NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1)
        case .yellow: NSColor(srgbRed: 1.0, green: 0.8, blue: 0.0, alpha: 1)
        case .green: NSColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)
        case .blue: NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1)
        case .black: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        case .white: .white
        }
    }

    /// Ink for numbers and text drawn on top of this colour.
    var contrasting: NSColor { self == .yellow || self == .white ? .black : .white }
}

enum StrokeSize: Int, CaseIterable, Sendable {
    case small, medium, large

    /// Stroke width in points; multiplied by the capture's scale for pixels.
    var points: CGFloat { [3, 5, 8][rawValue] }
    var fontPoints: CGFloat { [16, 24, 36][rawValue] }
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

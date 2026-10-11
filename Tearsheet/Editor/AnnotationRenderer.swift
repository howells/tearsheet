import AppKit

/// Draws annotations. The editor canvas and the flattened export both go
/// through here, so what you see is what gets copied.
enum AnnotationRenderer {
    static func render(base: CGImage, document: AnnotationDocument, scale: CGFloat) -> CGImage {
        let full = composite(base: base, annotations: document.annotations, scale: scale)
        guard let crop = document.crop?.integral, !crop.isEmpty else { return full }
        let topLeft = CGRect(x: crop.minX, y: CGFloat(full.height) - crop.maxY, width: crop.width, height: crop.height)
        return full.cropping(to: topLeft) ?? full
    }

    static func composite(base: CGImage, annotations: [Annotation], scale: CGFloat) -> CGImage {
        guard let context = ImageCoding.bitmapContext(width: base.width, height: base.height, colorSpace: base.colorSpace) else { return base }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        var counter = 0
        for annotation in annotations {
            if annotation.isCounter { counter += 1 }
            draw(annotation, number: counter, in: context, scale: scale)
        }
        return context.makeImage() ?? base
    }

    static func draw(_ annotation: Annotation, number: Int, in context: CGContext, scale: CGFloat) {
        let width = annotation.size.points * scale
        let color = annotation.color.nsColor.cgColor
        context.saveGState()
        defer { context.restoreGState() }

        switch annotation.shape {
        case let .arrow(from, to):
            applyShadow(context, scale: scale)
            context.addPath(arrowPath(from: from, to: to, width: width))
            context.setFillColor(color)
            context.fillPath()

        case let .rectangle(rect):
            applyShadow(context, scale: scale)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: width, cornerHeight: width, transform: nil))
            context.setStrokeColor(color)
            context.setLineWidth(width)
            context.strokePath()

        case let .counter(center):
            let diameter = counterDiameter(annotation.size, scale: scale)
            let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            applyShadow(context, scale: scale)
            context.setFillColor(color)
            context.fillEllipse(in: circle)
            context.setShadow(offset: .zero, blur: 0)
            context.setStrokeColor(annotation.color.contrasting.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(max(1, diameter * 0.06))
            context.strokeEllipse(in: circle.insetBy(dx: diameter * 0.03, dy: diameter * 0.03))
            let font = NSFont.systemFont(ofSize: diameter * 0.55, weight: .bold)
            let label = NSAttributedString(string: "\(number)", attributes: [.font: font, .foregroundColor: annotation.color.contrasting])
            let size = label.size()
            withAppKit(context) { label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)) }

        case let .text(origin, string, style):
            drawText(string, origin: origin, style: style, annotation: annotation, scale: scale, in: context)

        case let .pixelate(rect):
            pixelate(rect, blockSize: 10 * scale, in: context)

        case let .highlighter(points):
            guard let first = points.first else { return }
            context.setBlendMode(.multiply)
            context.setStrokeColor(annotation.color.nsColor.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(width * 5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            if points.count == 1 { context.addLine(to: first) }
            context.strokePath()
        }
    }

    // MARK: Shapes

    /// A tapered arrow on a gentle curve, with the head lined up to the curve's end.
    static func arrowPath(from start: CGPoint, to tip: CGPoint, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let length = hypot(tip.x - start.x, tip.y - start.y)
        guard length > 1 else { return path }
        let unit = CGVector(dx: (tip.x - start.x) / length, dy: (tip.y - start.y) / length)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)
        let bend = length * 0.06
        let control = CGPoint(x: (start.x + tip.x) / 2 + normal.dx * bend, y: (start.y + tip.y) / 2 + normal.dy * bend)

        let headLength = min(length * 0.6, width * 5)
        let headHalfWidth = headLength * 0.5
        let end = CGVector(dx: tip.x - control.x, dy: tip.y - control.y)
        let endLength = max(hypot(end.dx, end.dy), 0.001)
        let direction = CGVector(dx: end.dx / endLength, dy: end.dy / endLength)
        let side = CGVector(dx: -direction.dy, dy: direction.dx)
        let headBase = CGPoint(x: tip.x - direction.dx * headLength, y: tip.y - direction.dy * headLength)

        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * tip.x,
                           y: u * u * start.y + 2 * u * t * control.y + t * t * tip.y)
        }
        func tangent(_ t: CGFloat) -> CGVector {
            let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (tip.x - control.x)
            let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (tip.y - control.y)
            let length = max(hypot(dx, dy), 0.001)
            return CGVector(dx: -dy / length, dy: dx / length)
        }

        let bodyEnd = max(0, 1 - headLength * 0.8 / length)
        let steps = 24
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for step in 0...steps {
            let t = bodyEnd * CGFloat(step) / CGFloat(steps)
            let p = point(t)
            let n = tangent(t)
            let halfWidth = (width * 0.3 + width * 0.8 * (t / max(bodyEnd, 0.001))) / 2
            left.append(CGPoint(x: p.x + n.dx * halfWidth, y: p.y + n.dy * halfWidth))
            right.append(CGPoint(x: p.x - n.dx * halfWidth, y: p.y - n.dy * halfWidth))
        }

        path.addLines(between: left)
        path.addLine(to: CGPoint(x: headBase.x + side.dx * headHalfWidth, y: headBase.y + side.dy * headHalfWidth))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: headBase.x - side.dx * headHalfWidth, y: headBase.y - side.dy * headHalfWidth))
        for point in right.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    static func counterDiameter(_ size: StrokeSize, scale: CGFloat) -> CGFloat {
        size.points * scale * 8
    }

    // MARK: Text

    static func textAttributes(for annotation: Annotation, scale: CGFloat, ink: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: annotation.size.fontPoints * scale, weight: .bold), .foregroundColor: ink]
    }

    static func textSize(_ string: String, annotation: Annotation, scale: CGFloat) -> CGSize {
        let text = NSAttributedString(string: string.isEmpty ? " " : string, attributes: textAttributes(for: annotation, scale: scale, ink: .black))
        let size = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    static func textPadding(_ annotation: Annotation, scale: CGFloat) -> CGFloat {
        annotation.size.fontPoints * scale * 0.3
    }

    private static func drawText(_ string: String, origin: CGPoint, style: TextStyle, annotation: Annotation, scale: CGFloat, in context: CGContext) {
        let size = textSize(string, annotation: annotation, scale: scale)
        let rect = CGRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
        switch style {
        case .background:
            let padding = textPadding(annotation, scale: scale)
            let box = rect.insetBy(dx: -padding, dy: -padding * 0.6)
            applyShadow(context, scale: scale)
            context.addPath(CGPath(roundedRect: box, cornerWidth: padding, cornerHeight: padding, transform: nil))
            context.setFillColor(annotation.color.nsColor.cgColor)
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0)
            let text = NSAttributedString(string: string, attributes: textAttributes(for: annotation, scale: scale, ink: annotation.color.contrasting))
            withAppKit(context) { text.draw(with: rect, options: [.usesLineFragmentOrigin]) }
        case .outline:
            // Stroke pass first, fill on top, so the outline never eats into the letters.
            let outline = NSAttributedString(string: string, attributes: textAttributes(for: annotation, scale: scale, ink: annotation.color.contrasting).merging([
                .strokeColor: annotation.color.contrasting,
                .strokeWidth: 22,
            ]) { $1 })
            let fill = NSAttributedString(string: string, attributes: textAttributes(for: annotation, scale: scale, ink: annotation.color.nsColor))
            context.setLineJoin(.round)
            withAppKit(context) {
                outline.draw(with: rect, options: [.usesLineFragmentOrigin])
                fill.draw(with: rect, options: [.usesLineFragmentOrigin])
            }
        }
    }

    // MARK: Pixelate

    /// Replaces the pixels under `rect` with block averages. Needs a bitmap
    /// context; anywhere else (the live canvas) it draws an outline instead.
    private static func pixelate(_ rect: CGRect, blockSize: CGFloat, in context: CGContext) {
        guard let snapshot = context.makeImage() else {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(blockSize / 5)
            context.setLineDash(phase: 0, lengths: [blockSize / 2, blockSize / 2])
            context.stroke(rect)
            return
        }
        let bounds = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        let area = rect.integral.intersection(bounds)
        guard !area.isEmpty,
              let region = snapshot.cropping(to: CGRect(x: area.minX, y: bounds.height - area.maxY, width: area.width, height: area.height)) else { return }
        let columns = max(1, Int((area.width / blockSize).rounded(.up)))
        let rows = max(1, Int((area.height / blockSize).rounded(.up)))
        guard let small = ImageCoding.bitmapContext(width: columns, height: rows, colorSpace: snapshot.colorSpace) else { return }
        small.interpolationQuality = .medium
        small.draw(region, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let blocks = small.makeImage() else { return }
        context.interpolationQuality = .none
        context.draw(blocks, in: area)
    }

    // MARK: Helpers

    private static func applyShadow(_ context: CGContext, scale: CGFloat) {
        context.setShadow(offset: CGSize(width: 0, height: -1 * scale), blur: 3 * scale, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    }

    private static func withAppKit(_ context: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Hit testing

extension Annotation {
    func bounds(scale: CGFloat) -> CGRect {
        let width = size.points * scale
        switch shape {
        case let .arrow(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(from.x - to.x), height: abs(from.y - to.y)).insetBy(dx: -width * 2, dy: -width * 2)
        case let .rectangle(rect):
            return rect.insetBy(dx: -width / 2, dy: -width / 2)
        case let .text(origin, string, _):
            let textSize = AnnotationRenderer.textSize(string, annotation: self, scale: scale)
            let padding = AnnotationRenderer.textPadding(self, scale: scale)
            return CGRect(x: origin.x, y: origin.y - textSize.height, width: textSize.width, height: textSize.height).insetBy(dx: -padding, dy: -padding * 0.6)
        case let .counter(center):
            let diameter = AnnotationRenderer.counterDiameter(size, scale: scale)
            return CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        case let .pixelate(rect):
            return rect
        case let .highlighter(points):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -width * 2.5, dy: -width * 2.5)
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat, scale: CGFloat) -> Bool {
        let width = size.points * scale
        switch shape {
        case let .arrow(from, to):
            return distance(from: point, toSegment: from, to) <= max(tolerance, width * 2)
        case let .rectangle(rect):
            let band = width / 2 + tolerance
            return rect.insetBy(dx: -band, dy: -band).contains(point) && !rect.insetBy(dx: band, dy: band).contains(point)
        case .text, .counter, .pixelate:
            return bounds(scale: scale).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .highlighter(points):
            let reach = width * 2.5 + tolerance
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= reach }
                || points.contains { hypot($0.x - point.x, $0.y - point.y) <= reach }
        }
    }
}

private func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
    let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
    return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
}

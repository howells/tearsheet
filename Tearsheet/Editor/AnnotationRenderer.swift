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
        let size = annotation.size
        let ink = annotation.color.nsColor.cgColor
        context.saveGState()
        defer { context.restoreGState() }

        switch annotation.shape {
        case let .arrow(from, to):
            pen(arrowPath(from: from, to: to, size: size, scale: scale), annotation: annotation, scale: scale, in: context)

        case let .rectangle(rect):
            let radius = min(size.cornerRadius * scale, rect.width / 2, rect.height / 2)
            pen(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), annotation: annotation, scale: scale, in: context)

        case let .counter(center):
            let diameter = counterDiameter(size, scale: scale)
            let disc = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            let halo = size.halo * scale
            applyShadow(context, scale: scale)
            context.setFillColor(annotation.color.halo.cgColor)
            context.fillEllipse(in: disc.insetBy(dx: -halo, dy: -halo))
            context.setShadow(offset: .zero, blur: 0)
            context.setFillColor(ink)
            context.fillEllipse(in: disc)
            let font = NSFont.monospacedDigitSystemFont(ofSize: size.numeralPoints * scale, weight: .semibold)
            let label = NSAttributedString(string: "\(number)", attributes: [.font: font, .foregroundColor: annotation.color.contrasting])
            // Centre on the cap height rather than the line box, so numerals sit optically centred.
            let baseline = center.y - font.capHeight / 2
            withAppKit(context) { label.draw(at: CGPoint(x: center.x - label.size().width / 2, y: baseline + font.descender)) }

        case let .text(origin, string, style):
            drawText(string, origin: origin, style: style, annotation: annotation, scale: scale, in: context)

        case let .pixelate(rect):
            pixelate(rect, blockSize: size.pixelBlock * scale, in: context)

        case let .highlighter(points):
            guard let first = points.first else { return }
            context.setBlendMode(.multiply)
            context.setStrokeColor(annotation.color.nsColor.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(size.marker * scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            if points.count == 1 { context.addLine(to: first) }
            context.strokePath()
        }
    }

    /// The single pen: a halo pass under an ink pass, both with round caps and joins.
    private static func pen(_ path: CGPath, annotation: Annotation, scale: CGFloat, in context: CGContext) {
        let stroke = annotation.size.stroke * scale
        context.setLineCap(.round)
        context.setLineJoin(.round)
        applyShadow(context, scale: scale)
        context.addPath(path)
        context.setStrokeColor(annotation.color.halo.cgColor)
        context.setLineWidth(stroke + 2 * annotation.size.halo * scale)
        context.strokePath()
        context.setShadow(offset: .zero, blur: 0)
        context.addPath(path)
        context.setStrokeColor(annotation.color.nsColor.cgColor)
        context.setLineWidth(stroke)
        context.strokePath()
    }

    // MARK: Shapes

    /// A straight shaft with an open chevron head, its arms 28 degrees off the shaft.
    static func arrowPath(from start: CGPoint, to tip: CGPoint, size: StrokeSize, scale: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let length = hypot(tip.x - start.x, tip.y - start.y)
        guard length > 1 else { return path }
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let arm = min(size.arrowArm * scale, length * 0.5)
        let spread = 28 * CGFloat.pi / 180
        func armEnd(_ offset: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - arm * cos(angle + offset), y: tip.y - arm * sin(angle + offset))
        }
        path.move(to: start)
        path.addLine(to: tip)
        path.move(to: armEnd(spread))
        path.addLine(to: tip)
        path.addLine(to: armEnd(-spread))
        return path
    }

    static func counterDiameter(_ size: StrokeSize, scale: CGFloat) -> CGFloat {
        size.counterDiameter * scale
    }

    // MARK: Text

    static func textFont(_ size: StrokeSize, scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size.textPoints * scale, weight: .semibold)
    }

    static func textAttributes(for annotation: Annotation, scale: CGFloat, ink: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: textFont(annotation.size, scale: scale), .foregroundColor: ink]
    }

    static func textSize(_ string: String, annotation: Annotation, scale: CGFloat) -> CGSize {
        let text = NSAttributedString(string: string.isEmpty ? " " : string, attributes: textAttributes(for: annotation, scale: scale, ink: .black))
        let size = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    static func textPadding(_ annotation: Annotation, scale: CGFloat) -> CGFloat {
        annotation.size.textPoints * scale * 0.45
    }

    private static func drawText(_ string: String, origin: CGPoint, style: TextStyle, annotation: Annotation, scale: CGFloat, in context: CGContext) {
        let size = textSize(string, annotation: annotation, scale: scale)
        let rect = CGRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
        switch style {
        case .background:
            let padding = textPadding(annotation, scale: scale)
            let box = rect.insetBy(dx: -padding, dy: -padding * 0.45)
            let radius = annotation.size.cornerRadius * scale
            let halo = annotation.size.halo * scale
            applyShadow(context, scale: scale)
            context.addPath(CGPath(roundedRect: box.insetBy(dx: -halo, dy: -halo), cornerWidth: radius + halo, cornerHeight: radius + halo, transform: nil))
            context.setFillColor(annotation.color.halo.cgColor)
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0)
            context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(annotation.color.nsColor.cgColor)
            context.fillPath()
            let text = NSAttributedString(string: string, attributes: textAttributes(for: annotation, scale: scale, ink: annotation.color.contrasting))
            withAppKit(context) { text.draw(with: rect, options: [.usesLineFragmentOrigin]) }
        case .outline:
            // Halo pass first, ink on top, so the outline never eats into the letters.
            // Stroke width is a percentage of the font size, centred on the glyph edge.
            let haloPercent = 3 * annotation.size.halo / annotation.size.textPoints * 100
            let outline = NSAttributedString(string: string, attributes: textAttributes(for: annotation, scale: scale, ink: annotation.color.halo).merging([
                .strokeColor: annotation.color.halo,
                .strokeWidth: haloPercent,
            ]) { $1 })
            let fill = NSAttributedString(string: string, attributes: textAttributes(for: annotation, scale: scale, ink: annotation.color.nsColor))
            context.setLineJoin(.round)
            applyShadow(context, scale: scale)
            withAppKit(context) { outline.draw(with: rect, options: [.usesLineFragmentOrigin]) }
            context.setShadow(offset: .zero, blur: 0)
            withAppKit(context) { fill.draw(with: rect, options: [.usesLineFragmentOrigin]) }
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

    /// A faint lift under the halo; the halo itself does the work of legibility.
    private static func applyShadow(_ context: CGContext, scale: CGFloat) {
        context.setShadow(offset: CGSize(width: 0, height: -0.5 * scale), blur: 2 * scale, color: NSColor.black.withAlphaComponent(0.25).cgColor)
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
        let width = (size.stroke + 2 * size.halo) * scale
        switch shape {
        case let .arrow(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(from.x - to.x), height: abs(from.y - to.y)).insetBy(dx: -size.arrowArm * scale, dy: -size.arrowArm * scale)
        case let .rectangle(rect):
            return rect.insetBy(dx: -width / 2, dy: -width / 2)
        case let .text(origin, string, _):
            let textSize = AnnotationRenderer.textSize(string, annotation: self, scale: scale)
            let padding = AnnotationRenderer.textPadding(self, scale: scale)
            return CGRect(x: origin.x, y: origin.y - textSize.height, width: textSize.width, height: textSize.height).insetBy(dx: -padding, dy: -padding * 0.45)
        case let .counter(center):
            let diameter = AnnotationRenderer.counterDiameter(size, scale: scale)
            return CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        case let .pixelate(rect):
            return rect
        case let .highlighter(points):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
            let reach = size.marker * scale / 2
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -reach, dy: -reach)
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat, scale: CGFloat) -> Bool {
        let width = (size.stroke + 2 * size.halo) * scale
        switch shape {
        case let .arrow(from, to):
            return distance(from: point, toSegment: from, to) <= max(tolerance, width * 2)
        case let .rectangle(rect):
            let band = width / 2 + tolerance
            return rect.insetBy(dx: -band, dy: -band).contains(point) && !rect.insetBy(dx: band, dy: band).contains(point)
        case .text, .counter, .pixelate:
            return bounds(scale: scale).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .highlighter(points):
            let reach = size.marker * scale / 2 + tolerance
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

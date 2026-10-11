import AppKit
import TearsheetCore

/// One display's overlay: the frozen image as layer contents, with the dimming,
/// selection, size readout and loupe drawn by a decoration view on top.
final class OverlayView: NSView {
    let snapshot: DisplaySnapshot
    private unowned let controller: OverlayController
    private let decorations = OverlayDecorationView()

    private(set) var selection: CGRect?
    private(set) var mouseLocation: CGPoint?
    private var anchor = CGPoint.zero
    private var lastDragPoint = CGPoint.zero

    init(snapshot: DisplaySnapshot, controller: OverlayController) {
        self.snapshot = snapshot
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
        wantsLayer = true
        layer?.contents = snapshot.image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        decorations.frame = bounds
        decorations.autoresizingMask = [.width, .height]
        decorations.overlay = self
        addSubview(decorations)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func clearSelection() {
        selection = nil
        decorations.needsDisplay = true
    }

    var pixelSelection: CGRect? {
        selection.map { SelectionGeometry.pixelRect(for: $0, viewHeight: bounds.height, scale: snapshot.scale) }
    }

    // MARK: Mouse

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        track(event)
    }

    override func mouseEntered(with event: NSEvent) { track(event) }

    override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        decorations.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        anchor = point
        lastDragPoint = point
        selection = CGRect(origin: point, size: .zero)
        controller.selectionBegan(in: self)
        track(event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if controller.isSpaceHeld, let current = selection {
            let moved = SelectionGeometry.move(current, by: CGVector(dx: point.x - lastDragPoint.x, dy: point.y - lastDragPoint.y), within: bounds)
            anchor.x += moved.minX - current.minX
            anchor.y += moved.minY - current.minY
            selection = moved
        } else {
            selection = SelectionGeometry.rect(from: anchor, to: point, within: bounds)
        }
        lastDragPoint = point
        track(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, let pixels = pixelSelection, pixels.width >= 4, pixels.height >= 4 else {
            clearSelection()
            return
        }
        controller.finish(OverlaySelection(snapshot: snapshot, rect: selection))
    }

    override func rightMouseDown(with event: NSEvent) { controller.finish(nil) }

    private func track(_ event: NSEvent) {
        mouseLocation = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        decorations.needsDisplay = true
    }
}

private final class OverlayDecorationView: NSView {
    weak var overlay: OverlayView?

    private let loupeSize: CGFloat = 132
    private let loupePixels = 17

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay, let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.addRect(bounds)
        if let selection = overlay.selection, !selection.isEmpty { context.addRect(selection) }
        context.fillPath(using: .evenOdd)

        if let selection = overlay.selection, let pixels = overlay.pixelSelection, !selection.isEmpty {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
            drawSizeLabel("\(Int(pixels.width)) × \(Int(pixels.height))", near: selection)
        }

        if let mouse = overlay.mouseLocation {
            drawLoupe(at: mouse, snapshot: overlay.snapshot, in: context)
        }
    }

    private func drawSizeLabel(_ text: String, near selection: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var pill = CGRect(x: selection.maxX - size.width - 12, y: selection.minY - size.height - 12, width: size.width + 12, height: size.height + 6)
        if pill.minY < bounds.minY + 4 { pill.origin.y = selection.minY + 6 }
        pill.origin.x = max(bounds.minX + 4, min(pill.minX, bounds.maxX - pill.width - 4))
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 3), withAttributes: attributes)
    }

    /// A magnified, unsmoothed view of the pixels around the cursor, for exact edges.
    private func drawLoupe(at mouse: CGPoint, snapshot: DisplaySnapshot, in context: CGContext) {
        var frame = CGRect(x: mouse.x + 20, y: mouse.y + 20, width: loupeSize, height: loupeSize)
        if frame.maxX > bounds.maxX { frame.origin.x = mouse.x - 20 - loupeSize }
        if frame.maxY > bounds.maxY { frame.origin.y = mouse.y - 20 - loupeSize }

        let image = snapshot.image
        let half = loupePixels / 2
        let centreX = min(Int(mouse.x * snapshot.scale), image.width - 1)
        let centreY = min(Int((bounds.height - mouse.y) * snapshot.scale), image.height - 1)
        let grid = CGRect(x: centreX - half, y: centreY - half, width: loupePixels, height: loupePixels)
        let visible = grid.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let cell = loupeSize / CGFloat(loupePixels)

        context.saveGState()
        let circle = CGPath(ellipseIn: frame, transform: nil)
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(circle)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0)

        context.addPath(circle)
        context.clip()
        if !visible.isNull, let crop = image.cropping(to: visible) {
            context.interpolationQuality = .none
            let destination = CGRect(
                x: frame.minX + (visible.minX - grid.minX) * cell,
                y: frame.maxY - (visible.maxY - grid.minY) * cell,
                width: visible.width * cell,
                height: visible.height * cell
            )
            context.draw(crop, in: destination)
        }
        let centre = CGRect(x: frame.minX + CGFloat(half) * cell, y: frame.maxY - CGFloat(half + 1) * cell, width: cell, height: cell)
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.cgColor)
        context.stroke(centre.insetBy(dx: -1, dy: -1))
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(centre)
        context.restoreGState()

        context.addPath(circle)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokePath()
    }
}

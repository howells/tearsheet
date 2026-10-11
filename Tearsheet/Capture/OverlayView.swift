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

    func refresh() { decorations.needsDisplay = true }

    func modeChanged() {
        selection = nil
        updateCursor()
        decorations.needsDisplay = true
    }

    var isExtracting: Bool { controller.mode == .extract }
    var imageState: OverlayController.ImageState { controller.imageState }

    /// The page's images on this display, in view coordinates.
    var localImages: [(image: ScreenImage, rect: CGRect)] {
        let origin = snapshot.screen.frame.origin
        return controller.images.compactMap { image in
            let rect = image.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            return rect.intersects(bounds) ? (image, rect) : nil
        }
    }

    /// What a click or drag would take: images inside the drag box, or the
    /// images under the pointer, smallest first so the one you aimed at leads.
    var targetedImages: [(image: ScreenImage, rect: CGRect)] {
        if let selection, selection.width >= 4 || selection.height >= 4 {
            return localImages.filter { $0.rect.intersects(selection) }
        }
        guard let mouseLocation else { return [] }
        return localImages.filter { $0.rect.contains(mouseLocation) }
            .sorted { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    private func updateCursor() {
        (isExtracting ? NSCursor.pointingHand : Self.crosshair).set()
    }

    /// A hairline ink cross on a white halo, from the mockup, readable on any screen.
    static let crosshair: NSCursor = {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: 12, y: 1)); cross.line(to: CGPoint(x: 12, y: 23))
            cross.move(to: CGPoint(x: 1, y: 12)); cross.line(to: CGPoint(x: 23, y: 12))
            cross.lineWidth = 3
            NSColor.white.setStroke()
            cross.stroke()
            cross.lineWidth = 1
            Darkroom.ink.setStroke()
            cross.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 12, y: 12))
    }()

    var pixelSelection: CGRect? {
        selection.map { SelectionGeometry.pixelRect(for: $0, viewHeight: bounds.height, scale: snapshot.scale) }
    }

    // MARK: Mouse

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    override func mouseMoved(with event: NSEvent) {
        updateCursor()
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
        if isExtracting {
            track(event)
            let taken = targetedImages.map(\.image)
            guard !taken.isEmpty else { return clearSelection() }
            controller.finish(.images(taken))
            return
        }
        guard let selection, let pixels = pixelSelection, pixels.width >= 4, pixels.height >= 4 else {
            clearSelection()
            return
        }
        controller.finish(.region(OverlaySelection(snapshot: snapshot, rect: selection)))
    }

    override func rightMouseDown(with event: NSEvent) { controller.finish(nil) }

    private func track(_ event: NSEvent) {
        mouseLocation = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        decorations.needsDisplay = true
    }
}

private final class OverlayDecorationView: NSView {
    weak var overlay: OverlayView?

    private let loupeSize: CGFloat = 136
    private let loupePixels = 17

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay, let context = NSGraphicsContext.current?.cgContext else { return }

        if overlay.isExtracting {
            drawExtraction(overlay, in: context)
            return
        }

        context.setFillColor(Darkroom.ink.withAlphaComponent(0.6).cgColor)
        context.addRect(bounds)
        if let selection = overlay.selection, !selection.isEmpty { context.addRect(selection) }
        context.fillPath(using: .evenOdd)

        if let selection = overlay.selection, let pixels = overlay.pixelSelection, !selection.isEmpty {
            // 1.5-point paper edge with a faint ink ring outside it, so it holds on white pages too.
            context.setStrokeColor(Darkroom.ink.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: -2, dy: -2))
            context.setStrokeColor(Darkroom.paper.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selection.insetBy(dx: -0.75, dy: -0.75))
            drawSizeLabel("\(Int(pixels.width)) × \(Int(pixels.height))", near: selection)
        }

        if let mouse = overlay.mouseLocation {
            drawLoupe(at: mouse, snapshot: overlay.snapshot, in: context)
        }
    }

    // MARK: Extract mode

    private func drawExtraction(_ overlay: OverlayView, in context: CGContext) {
        context.setFillColor(Darkroom.ink.withAlphaComponent(0.6).cgColor)
        context.fill(bounds)

        let paper = Darkroom.paper
        let targeted = overlay.targetedImages
        let targetedRects = Set(targeted.map { "\($0.rect)" })
        for entry in overlay.localImages where !targetedRects.contains("\(entry.rect)") {
            context.setStrokeColor(paper.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(1)
            context.stroke(entry.rect.insetBy(dx: 0.5, dy: 0.5))
        }
        // A click takes every layer under the pointer; outline the one it leads with most strongly.
        for (index, entry) in targeted.enumerated() {
            context.setFillColor(paper.withAlphaComponent(index == 0 ? 0.14 : 0.06).cgColor)
            context.fill(entry.rect)
            context.setStrokeColor(paper.withAlphaComponent(index == 0 ? 1 : 0.6).cgColor)
            context.setLineWidth(index == 0 ? 2 : 1)
            context.stroke(entry.rect.insetBy(dx: 1, dy: 1))
        }
        if let selection = overlay.selection, selection.width >= 4 || selection.height >= 4 {
            context.setStrokeColor(paper.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
            context.setLineDash(phase: 0, lengths: [])
        }

        switch overlay.imageState {
        case .idle, .loading:
            drawStatus("Finding images…", detail: nil)
        case let .loaded(images) where images.isEmpty:
            drawStatus("No images in view", detail: nil)
        case let .loaded(images):
            let count = images.count
            drawStatus(targeted.isEmpty ? (count == 1 ? "1 image" : "\(count) images") : (targeted.count == 1 ? "1 image selected" : "\(targeted.count) images selected"), detail: nil)
        case let .failed(error):
            let failure = error as? LocalizedError
            drawStatus(failure?.errorDescription ?? error.localizedDescription, detail: failure?.recoverySuggestion)
        }
    }

    /// A pill at the top of the display for the extraction state and any fix the user needs to make.
    private func drawStatus(_ title: String, detail: String?) {
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: Darkroom.paper]
        let detailAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Darkroom.muted]
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let detailBounds = detail.map { ($0 as NSString).boundingRect(with: CGSize(width: 420, height: 200), options: [.usesLineFragmentOrigin], attributes: detailAttributes).size } ?? .zero
        let width = max(titleSize.width, ceil(detailBounds.width)) + 28
        let height = titleSize.height + (detail == nil ? 0 : ceil(detailBounds.height) + 4) + 16
        let pill = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - 64 - height, width: width, height: height)
        drawPill(pill)
        (title as NSString).draw(at: CGPoint(x: pill.minX + 14, y: pill.maxY - 8 - titleSize.height), withAttributes: titleAttributes)
        if let detail {
            (detail as NSString).draw(with: CGRect(x: pill.minX + 14, y: pill.minY + 8, width: 420, height: ceil(detailBounds.height)), options: [.usesLineFragmentOrigin], attributes: detailAttributes)
        }
    }

    /// The pixel size in a dark pill, right-aligned under the selection (above it near the bottom edge).
    private func drawSizeLabel(_ text: String, near selection: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Darkroom.valueFont(), .foregroundColor: Darkroom.paper]
        let size = (text as NSString).size(withAttributes: attributes)
        var pill = CGRect(x: selection.maxX - size.width - 20, y: selection.minY - 11 - 26, width: size.width + 20, height: 26)
        if pill.minY < bounds.minY + 8 { pill.origin.y = selection.minY + 11 }
        pill.origin.x = max(bounds.minX + 8, min(pill.minX, bounds.maxX - pill.width - 8))
        drawPill(pill)
        (text as NSString).draw(at: CGPoint(x: pill.minX + 10, y: pill.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawPill(_ rect: CGRect) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowBlurRadius = 18
        shadow.set()
        Darkroom.graphite.withAlphaComponent(0.88).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.1).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
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
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.45).cgColor)
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
        // A faint pixel grid, then the centre pixel boxed in ink and white.
        context.setStrokeColor(Darkroom.ink.withAlphaComponent(0.07).cgColor)
        context.setLineWidth(1)
        for index in 1..<loupePixels {
            let offset = CGFloat(index) * cell
            context.move(to: CGPoint(x: frame.minX + offset, y: frame.minY)); context.addLine(to: CGPoint(x: frame.minX + offset, y: frame.maxY))
            context.move(to: CGPoint(x: frame.minX, y: frame.minY + offset)); context.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + offset))
        }
        context.strokePath()
        let centre = CGRect(x: frame.minX + CGFloat(half) * cell, y: frame.maxY - CGFloat(half + 1) * cell, width: cell, height: cell)
        context.setStrokeColor(Darkroom.ink.cgColor)
        context.stroke(centre.insetBy(dx: -0.5, dy: -0.5))
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(centre.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()

        context.addPath(CGPath(ellipseIn: frame.insetBy(dx: -2.25, dy: -2.25), transform: nil))
        context.setStrokeColor(Darkroom.ink.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
        context.addPath(CGPath(ellipseIn: frame.insetBy(dx: -1, dy: -1), transform: nil))
        context.setStrokeColor(Darkroom.paper.cgColor)
        context.setLineWidth(2)
        context.strokePath()
    }
}

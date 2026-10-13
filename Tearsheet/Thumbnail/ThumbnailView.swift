import AppKit

final class ThumbnailView: NSView, NSDraggingSource {
    weak var panel: ThumbnailPanel?
    private let item: CaptureItem
    private let imageLayer = CALayer()
    private let controls = NSView()
    private let flashLabel = DarkroomPill("")
    private var mouseDownPoint: CGPoint?
    private var swipeOffset: CGFloat = 0

    init(item: CaptureItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = Darkroom.graphite.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.borderWidth = 0.5
        // Smooth edges when the card is tilted in the fan.
        layer?.allowsEdgeAntialiasing = true

        imageLayer.allowsEdgeAntialiasing = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.contents = item.image
        layer?.addSublayer(imageLayer)

        if item.web?.isRenderedCopy == true { buildRenderedCopyBadge() }
        buildControls()
        buildFlashLabel()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func refreshImage() { imageLayer.contents = item.image }

    // MARK: Controls

    private func buildControls() {
        controls.wantsLayer = true
        controls.layer?.backgroundColor = Darkroom.ink.withAlphaComponent(0.42).cgColor
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        addSubview(controls)

        let copy = DarkroomButton("Copy", style: .primary, pill: true, width: 76) { [weak self] in self?.panel?.copy() }
        let save = DarkroomButton("Save", style: .glass, pill: true, width: 76) { [weak self] in
            self?.panel?.save(atOneX: NSEvent.modifierFlags.contains(.option))
        }
        save.toolTip = "Hold ⌥ to save at 1×"
        let close = DarkroomIconButton(.close, label: "Close") { [weak self] in self?.panel?.dismiss() }
        let annotate = DarkroomIconButton(.pencil, label: "Annotate") { [weak self] in self?.panel?.annotate() }

        for view in [copy, save, close, annotate] as [NSView] { controls.addSubview(view) }
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor),
            copy.trailingAnchor.constraint(equalTo: controls.centerXAnchor, constant: -4),
            copy.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            save.leadingAnchor.constraint(equalTo: controls.centerXAnchor, constant: 4),
            save.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            close.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            close.topAnchor.constraint(equalTo: controls.topAnchor),
            annotate.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            annotate.topAnchor.constraint(equalTo: controls.topAnchor),
        ])
    }

    /// Marks an extracted image that is a screenshot of the page, not the original file.
    private func buildRenderedCopyBadge() {
        let badge = DarkroomPill("Rendered copy")
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    private func buildFlashLabel() {
        flashLabel.isHidden = true
        addSubview(flashLabel)
        NSLayoutConstraint.activate([
            flashLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            flashLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func flash(_ message: String) {
        flashLabel.text = message
        setControlsVisible(false, duration: 0.1)
        flashLabel.isHidden = false
        flashLabel.alphaValue = 1
        layoutSubtreeIfNeeded()
        Darkroom.Motion.popIn(flashLabel, from: 0.94, duration: 0.2)
        flashGeneration += 1
        let generation = flashGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, generation == flashGeneration else { return }
            Darkroom.Motion.animate(0.18, Darkroom.Motion.easeOut, { self.flashLabel.animator().alphaValue = 0 }, completion: {
                guard generation == self.flashGeneration else { return }
                self.flashLabel.isHidden = true
                self.setControlsVisible(self.panel?.isHovered ?? false, duration: 0.15)
            })
        }
    }

    private var flashGeneration = 0

    // MARK: Hover

    override func mouseEntered(with event: NSEvent) {
        panel?.isHovered = true
        if flashLabel.isHidden { setControlsVisible(true, duration: 0.15) }
    }

    override func mouseExited(with event: NSEvent) {
        panel?.isHovered = false
        setControlsVisible(false, duration: 0.12)
    }

    private var controlsGeneration = 0

    /// Fades the hover scrim and buttons. Hidden once faded out, so they stop taking clicks;
    /// a later call supersedes an earlier one still in flight.
    private func setControlsVisible(_ visible: Bool, duration: TimeInterval) {
        controlsGeneration += 1
        let generation = controlsGeneration
        if visible {
            if controls.isHidden {
                controls.alphaValue = 0
                controls.isHidden = false
            }
            Darkroom.Motion.animate(duration, .init(name: .default)) { controls.animator().alphaValue = 1 }
        } else if !controls.isHidden {
            Darkroom.Motion.animate(duration, .init(name: .default), { self.controls.animator().alphaValue = 0 }, completion: {
                if generation == self.controlsGeneration { self.controls.isHidden = true }
            })
        }
    }

    // MARK: Click and drag out

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            panel?.annotate()
            return
        }
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        let draggingItem = NSDraggingItem(pasteboardWriter: item.pasteboardItem())
        draggingItem.setDraggingFrame(bounds, contents: NSImage(cgImage: item.image, size: bounds.size))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        panel?.alphaValue = 0.4
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty, let panel {
            Darkroom.Motion.animate(0.2, Darkroom.Motion.easeOut) { panel.animator().alphaValue = 1 }
        } else {
            panel?.dismiss()
        }
    }

    // MARK: Swipe away

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, let panel else { return }
        switch event.phase {
        case .began:
            swipeOffset = 0
            isSwiping = true
        case .changed:
            guard isSwiping else { return }
            // Positive means the fingers moved right, whichever scrolling direction is set.
            swipeOffset += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            // Free toward the screen edge, a little give the other way.
            let outward = swipeOffset * panel.edgeDirection
            panel.swipe(to: max(outward, -12) * panel.edgeDirection)
            finishSwipeIfQuiet()
        case .ended, .cancelled:
            finishSwipe()
        default:
            break
        }
    }

    private var isSwiping = false
    private var swipeWatch: Timer?

    /// The card can slide out from under a pointer that stays put, and the gesture's
    /// last event then goes to whatever is beneath. A swipe that goes quiet after the card
    /// has left the pointer finishes anyway; one paused over the card is still the fingers'.
    private func finishSwipeIfQuiet() {
        swipeWatch?.invalidate()
        swipeWatch = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isUnderPointer { self.finishSwipeIfQuiet() } else { self.finishSwipe() }
            }
        }
    }

    private var isUnderPointer: Bool {
        guard let window else { return false }
        return window.convertToScreen(convert(bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    private func finishSwipe() {
        swipeWatch?.invalidate()
        swipeWatch = nil
        guard isSwiping, let panel else { return }
        isSwiping = false
        if swipeOffset * panel.edgeDirection > 60 {
            panel.dismiss(swiped: true)
        } else {
            panel.settleSwipe()
        }
        swipeOffset = 0
    }
}

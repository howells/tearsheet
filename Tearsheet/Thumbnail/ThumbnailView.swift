import AppKit

final class ThumbnailView: NSView, NSDraggingSource {
    weak var panel: ThumbnailPanel?
    private let item: CaptureItem
    private let imageLayer = CALayer()
    private let controls = NSView()
    private let flashLabel = NSTextField(labelWithString: "")
    private var mouseDownPoint: CGPoint?
    private var swipeOffset: CGFloat = 0

    init(item: CaptureItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 0.5

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.contents = item.image
        layer?.addSublayer(imageLayer)

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
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        addSubview(controls)

        let copy = ThumbnailButton.text("Copy") { [weak self] in self?.panel?.copy() }
        let save = ThumbnailButton.text("Save") { [weak self] in
            self?.panel?.save(atOneX: NSEvent.modifierFlags.contains(.option))
        }
        save.toolTip = "Hold ⌥ to save at 1×"
        let centre = NSStackView(views: [copy, save])
        centre.orientation = .horizontal
        centre.spacing = 6
        centre.translatesAutoresizingMaskIntoConstraints = false

        let close = ThumbnailButton.symbol("xmark", label: "Close") { [weak self] in self?.panel?.dismiss() }
        let annotate = ThumbnailButton.symbol("pencil.tip", label: "Annotate") { [weak self] in self?.panel?.annotate() }

        for view in [centre, close, annotate] { controls.addSubview(view) }
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor),
            centre.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            centre.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            copy.widthAnchor.constraint(equalToConstant: 64),
            save.widthAnchor.constraint(equalToConstant: 64),
            close.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 6),
            close.topAnchor.constraint(equalTo: controls.topAnchor, constant: 6),
            annotate.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -6),
            annotate.topAnchor.constraint(equalTo: controls.topAnchor, constant: 6),
        ])
    }

    private func buildFlashLabel() {
        flashLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        flashLabel.textColor = .white
        flashLabel.alignment = .center
        flashLabel.wantsLayer = true
        flashLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        flashLabel.layer?.cornerRadius = 6
        flashLabel.translatesAutoresizingMaskIntoConstraints = false
        flashLabel.isHidden = true
        addSubview(flashLabel)
        NSLayoutConstraint.activate([
            flashLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            flashLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            flashLabel.widthAnchor.constraint(equalToConstant: 90),
        ])
    }

    func flash(_ message: String) {
        flashLabel.stringValue = message
        flashLabel.isHidden = false
        controls.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            flashLabel.isHidden = true
            controls.isHidden = !(panel?.isHovered ?? false)
        }
    }

    // MARK: Hover

    override func mouseEntered(with event: NSEvent) {
        panel?.isHovered = true
        controls.isHidden = !flashLabel.isHidden
    }

    override func mouseExited(with event: NSEvent) {
        panel?.isHovered = false
        controls.isHidden = true
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
        if operation.isEmpty {
            panel?.alphaValue = 1
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
        case .changed:
            // Positive means the fingers moved right, whichever scrolling direction is set.
            swipeOffset += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            panel.setFrameOrigin(CGPoint(x: panel.homeOrigin.x + min(swipeOffset, 12), y: panel.homeOrigin.y))
        case .ended, .cancelled:
            if swipeOffset < -60 {
                panel.dismiss(slidingLeft: true)
            } else {
                NSAnimationContext.runAnimationGroup { _ in panel.animateOrigin(to: panel.homeOrigin) }
            }
            swipeOffset = 0
        default:
            break
        }
    }
}

/// A button that works on the first click in a panel that never becomes key.
private final class ThumbnailButton: NSButton {
    private var handler: (() -> Void)?

    static func text(_ title: String, handler: @escaping () -> Void) -> ThumbnailButton {
        let button = ThumbnailButton(title: title, target: nil, action: nil)
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.configure(handler)
        return button
    }

    static func symbol(_ name: String, label: String, handler: @escaping () -> Void) -> ThumbnailButton {
        let button = ThumbnailButton(image: NSImage(systemSymbolName: name, accessibilityDescription: label)!, target: nil, action: nil)
        button.bezelStyle = .glass
        button.controlSize = .small
        button.toolTip = label
        button.configure(handler)
        return button
    }

    private func configure(_ handler: @escaping () -> Void) {
        self.handler = handler
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func fire() { handler?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

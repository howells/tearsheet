import AppKit

/// One editor window per capture; reopening a capture brings its window back.
final class EditorRegistry {
    private var controllers: [UUID: EditorWindowController] = [:]

    func open(_ item: CaptureItem) {
        if let existing = controllers[item.id] {
            existing.present()
            return
        }
        let controller = EditorWindowController(item: item)
        controller.onClose = { [weak self] in self?.controllers[item.id] = nil }
        controllers[item.id] = controller
        controller.present()
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    var onClose: (() -> Void)?

    private let item: CaptureItem
    private let canvas: EditorCanvasView
    /// Set once the edits have been applied (or deliberately thrown away), so closing doesn't apply them again.
    private var isSettled = false

    private let toolPicker = NSSegmentedControl()
    private let colorPicker = NSSegmentedControl()
    private let sizePicker = NSSegmentedControl()
    private let stylePicker = NSSegmentedControl()

    init(item: CaptureItem) {
        self.item = item
        canvas = EditorCanvasView(base: item.original, scale: item.scale, document: item.document)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)

        window.title = item.filename
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.contentView = buildContent()
        let toolbar = NSToolbar(identifier: "editor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        canvas.onCommit = { [weak self] in self?.copyAndClose(nil) }
        canvas.onCancel = { [weak self] in self?.discardAndClose() }
        canvas.onStateChange = { [weak self] in self?.syncControls() }
        configurePickers()
        size(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        item.isBeingEdited = true
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }

    // MARK: Commands

    @objc func copyAndClose(_ sender: Any?) {
        guard apply() else { return }
        Clipboard.copy(item)
        close()
    }

    @objc func saveCapture(_ sender: Any?) {
        guard apply() else { return }
        do {
            try Saver.save(item, atOneX: NSEvent.modifierFlags.contains(.option))
            close()
        } catch {
            NSAlert(error: error).beginSheetModal(for: window!)
        }
    }

    private func discardAndClose() {
        isSettled = true
        close()
    }

    @discardableResult
    private func apply() -> Bool {
        canvas.finishText()
        do {
            try item.apply(canvas.document)
            isSettled = true
            return true
        } catch {
            NSAlert(error: error).beginSheetModal(for: window!)
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window keeps the edits on the capture; only Esc throws them away.
        if !isSettled { apply() }
        item.isBeingEdited = false
        onClose?()
    }

    // MARK: Layout

    private func buildContent() -> NSView {
        let container = NSView()
        canvas.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "⇧ constrains · ⌫ deletes · double-click text to edit · ⌥ Save for 1×")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let save = NSButton(title: "Save", target: self, action: #selector(saveCapture(_:)))
        save.toolTip = "Save (⌘S)"
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyAndClose(_:)))
        copy.toolTip = "Copy and close (⌘C or ↩)"
        copy.bezelColor = .controlAccentColor
        for button in [save, copy] {
            button.controlSize = .large
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        }

        let bar = NSStackView(views: [hint, NSView(), save, copy])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        bar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(canvas)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 56),
        ])
        return container
    }

    private func size(_ window: NSWindow) {
        guard let visible = (NSScreen.underMouse ?? NSScreen.main)?.visibleFrame else { return }
        let image = CGSize(width: CGFloat(item.original.width) / item.scale, height: CGFloat(item.original.height) / item.scale)
        let content = CGSize(
            width: min(max(image.width + 48, 720), visible.width * 0.9),
            height: min(max(image.height + 48 + 56, 460), visible.height * 0.85)
        )
        window.contentMinSize = CGSize(width: 600, height: 360)
        window.setContentSize(content)
        window.setFrameOrigin(CGPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
    }

    // MARK: Toolbar

    private func configurePickers() {
        let tools = AnnotationTool.allCases
        toolPicker.segmentCount = tools.count
        for (index, tool) in tools.enumerated() {
            toolPicker.setImage(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.label), forSegment: index)
            toolPicker.setToolTip("\(tool.label) (\(tool.key.uppercased()))", forSegment: index)
        }

        let colors = AnnotationColor.allCases
        colorPicker.segmentCount = colors.count
        for (index, color) in colors.enumerated() {
            colorPicker.setImage(Swatch.color(color.nsColor), forSegment: index)
            colorPicker.setToolTip("Colour \(index + 1)", forSegment: index)
        }

        sizePicker.segmentCount = StrokeSize.allCases.count
        for (index, diameter) in [5.0, 8.0, 12.0].enumerated() {
            sizePicker.setImage(Swatch.dot(diameter: diameter), forSegment: index)
        }
        sizePicker.setToolTip("Small", forSegment: 0)
        sizePicker.setToolTip("Medium", forSegment: 1)
        sizePicker.setToolTip("Large", forSegment: 2)

        stylePicker.segmentCount = 2
        stylePicker.setLabel("Outline", forSegment: 0)
        stylePicker.setLabel("Box", forSegment: 1)
        stylePicker.setToolTip("Text with an outline", forSegment: 0)
        stylePicker.setToolTip("Text on a filled box", forSegment: 1)

        for picker in [toolPicker, colorPicker, sizePicker, stylePicker] {
            picker.trackingMode = .selectOne
            picker.target = self
            picker.action = #selector(pickerChanged(_:))
            picker.segmentStyle = .separated
        }
        syncControls()
    }

    @objc private func pickerChanged(_ sender: NSSegmentedControl) {
        switch sender {
        case toolPicker: canvas.tool = AnnotationTool.allCases[sender.selectedSegment]
        case colorPicker: canvas.color = AnnotationColor(rawValue: sender.selectedSegment) ?? .red
        case sizePicker: canvas.size = StrokeSize(rawValue: sender.selectedSegment) ?? .medium
        case stylePicker: canvas.textStyle = sender.selectedSegment == 0 ? .outline : .background
        default: break
        }
        window?.makeFirstResponder(canvas)
    }

    private func syncControls() {
        toolPicker.selectedSegment = AnnotationTool.allCases.firstIndex(of: canvas.tool) ?? 0
        colorPicker.selectedSegment = canvas.color.rawValue
        sizePicker.selectedSegment = canvas.size.rawValue
        stylePicker.selectedSegment = canvas.textStyle == .outline ? 0 : 1
    }

    private static let items: [NSToolbarItem.Identifier: String] = [
        .init("tools"): "Tools", .init("colors"): "Colour", .init("sizes"): "Size", .init("style"): "Text Style",
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("tools"), .space, .init("colors"), .init("sizes"), .init("style"), .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let view: NSView? = switch identifier.rawValue {
        case "tools": toolPicker
        case "colors": colorPicker
        case "sizes": sizePicker
        case "style": stylePicker
        default: nil
        }
        guard let view else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = view
        item.label = Self.items[identifier] ?? ""
        return item
    }
}

private enum Swatch {
    static func color(_ color: NSColor) -> NSImage {
        image(size: 16) { rect in
            color.setFill()
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            circle.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
        }
    }

    static func dot(diameter: CGFloat) -> NSImage {
        let template = image(size: 16) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)).fill()
        }
        template.isTemplate = true
        return template
    }

    private static func image(size: CGFloat, draw: (CGRect) -> Void) -> NSImage {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size * scale), pixelsHigh: Int(size * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = CGSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(CGRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

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

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let item: CaptureItem
    private let canvas: EditorCanvasView
    private let toolbar = EditorToolbarView()
    /// Set once the edits have been applied (or deliberately thrown away), so closing doesn't apply them again.
    private var isSettled = false

    init(item: CaptureItem) {
        self.item = item
        canvas = EditorCanvasView(base: item.original, scale: item.scale, document: item.document)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)

        window.title = item.filename
        window.delegate = self
        window.isReleasedWhenClosed = false
        // Graphite chrome whatever the system appearance, so the capture stays the brightest thing on screen.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Darkroom.graphite
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar gives the title bar the mockup's height and centres
        // the window controls in it; the tools are drawn by EditorToolbarView beneath.
        window.toolbar = NSToolbar(identifier: "editor")
        window.toolbarStyle = .unified
        window.contentView = buildContent()

        canvas.onCommit = { [weak self] in self?.copyAndClose(nil) }
        canvas.onCancel = { [weak self] in self?.discardAndClose() }
        canvas.onStateChange = { [weak self] in self?.syncControls() }
        configureToolbar()
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
        let bar = EditorActionBar(
            pixelSize: CGSize(width: item.original.width, height: item.original.height),
            save: { [weak self] in self?.saveCapture(nil) },
            copy: { [weak self] in self?.copyAndClose(nil) }
        )
        for view in [toolbar, canvas, bar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 56),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 60),
        ])
        return container
    }

    private func size(_ window: NSWindow) {
        guard let visible = (NSScreen.underMouse ?? NSScreen.main)?.visibleFrame else { return }
        let image = CGSize(width: CGFloat(item.original.width) / item.scale, height: CGFloat(item.original.height) / item.scale)
        // The capture floats on the ink canvas with room around it, as in the mockup.
        let content = CGSize(
            width: min(max(image.width + 160, 760), visible.width * 0.9),
            height: min(max(image.height + 100 + 56 + 60, 480), visible.height * 0.88)
        )
        window.contentMinSize = CGSize(width: 760, height: 400)
        window.setContentSize(content)
        window.setFrameOrigin(CGPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
    }

    // MARK: Toolbar

    private func configureToolbar() {
        toolbar.onTool = { [weak self] in self?.canvas.tool = $0; self?.refocus() }
        toolbar.onColor = { [weak self] in self?.canvas.color = $0; self?.refocus() }
        toolbar.onSize = { [weak self] in self?.canvas.size = $0; self?.refocus() }
        toolbar.onTextStyle = { [weak self] in self?.canvas.textStyle = $0; self?.refocus() }
        syncControls()
    }

    private func refocus() {
        syncControls()
        window?.makeFirstResponder(canvas)
    }

    private func syncControls() {
        toolbar.tool = canvas.tool
        toolbar.color = canvas.color
        toolbar.size = canvas.size
        toolbar.textStyle = canvas.textStyle
    }
}

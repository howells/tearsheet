import AppKit

struct OverlaySelection {
    let snapshot: DisplaySnapshot
    /// Point-space rectangle relative to the display's bottom-left corner.
    let rect: CGRect
}

/// Shows a frozen, dimmed copy of every display and waits for one selection.
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<OverlaySelection?, Never>?

    /// Space held while dragging moves the selection instead of resizing it.
    private(set) var isSpaceHeld = false

    func select(on snapshots: [DisplaySnapshot]) async -> OverlaySelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(snapshots)
        }
    }

    private func present(_ snapshots: [DisplaySnapshot]) {
        for snapshot in snapshots {
            let view = OverlayView(snapshot: snapshot, controller: self)
            let window = OverlayWindow(screen: snapshot.screen, contentView: view)
            views.append(view)
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate()
        let mouseScreen = NSScreen.underMouse
        (windows.first { $0.screen == mouseScreen } ?? windows.first)?.makeKey()
        NSCursor.crosshair.set()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Escape
            finish(nil)
        case 49: // Space
            isSpaceHeld = event.type == .keyDown
        default:
            break
        }
    }

    func selectionBegan(in view: OverlayView) {
        for other in views where other !== view { other.clearSelection() }
    }

    func finish(_ selection: OverlaySelection?) {
        guard let continuation else { return }
        self.continuation = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for window in windows { window.orderOut(nil) }
        // finish() runs inside the overlay's own mouse handler; release the
        // windows on the next turn of the run loop rather than mid-event.
        let released = windows
        DispatchQueue.main.async { _ = released }
        windows.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        continuation.resume(returning: selection)
    }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen, contentView: NSView) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
}

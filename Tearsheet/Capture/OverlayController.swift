import AppKit
import TearsheetCore

struct OverlaySelection {
    let snapshot: DisplaySnapshot
    /// Point-space rectangle relative to the display's bottom-left corner.
    let rect: CGRect
}

/// An image on the page, placed on screen.
struct ScreenImage {
    let image: PageImage
    /// Global AppKit points, origin bottom-left of the main display.
    let frame: CGRect
    let pageURL: URL?
}

enum OverlayResult {
    case region(OverlaySelection)
    case images([ScreenImage])
}

/// Shows a frozen, dimmed copy of every display and waits for one selection:
/// a region, or (in extract mode) images on the front browser tab.
final class OverlayController {
    enum Mode { case capture, extract }

    enum ImageState {
        case idle
        case loading
        case loaded([ScreenImage])
        case failed(Error)
    }

    private(set) var mode: Mode
    private(set) var imageState = ImageState.idle
    /// Finds the front tab's images. Nil when the front app isn't a browser, so Tab does nothing.
    private let loadImages: (() async throws -> [ScreenImage])?

    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<OverlayResult?, Never>?

    /// Space held while dragging moves the selection instead of resizing it.
    private(set) var isSpaceHeld = false

    init(mode: Mode = .capture, loadImages: (() async throws -> [ScreenImage])? = nil) {
        self.loadImages = loadImages
        self.mode = loadImages == nil ? .capture : mode
    }

    var images: [ScreenImage] {
        if case let .loaded(images) = imageState { images } else { [] }
    }

    func select(on snapshots: [DisplaySnapshot]) async -> OverlayResult? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(snapshots)
            if mode == .extract { startLoadingImages() }
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
        // No NSApp.activate(): macOS may refuse activation from a hot key. The
        // overlay is a non-activating panel, which takes keyboard focus anyway.
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
        case 48 where event.type == .keyDown && !event.isARepeat: // Tab
            toggleMode()
        default:
            break
        }
    }

    private func toggleMode() {
        guard loadImages != nil else { return }
        mode = mode == .capture ? .extract : .capture
        if mode == .extract { startLoadingImages() }
        for view in views { view.modeChanged() }
    }

    private func startLoadingImages() {
        guard let loadImages else { return }
        switch imageState {
        case .idle, .failed: break
        case .loading, .loaded: return
        }
        imageState = .loading
        redraw()
        Task {
            do {
                imageState = .loaded(try await loadImages())
            } catch {
                imageState = .failed(error)
            }
            redraw()
        }
    }

    private func redraw() {
        for view in views { view.refresh() }
    }

    func selectionBegan(in view: OverlayView) {
        for other in views where other !== view { other.clearSelection() }
    }

    func finish(_ result: OverlayResult?) {
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
        continuation.resume(returning: result)
    }
}

final class OverlayWindow: NSPanel {
    init(screen: NSScreen, contentView: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
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

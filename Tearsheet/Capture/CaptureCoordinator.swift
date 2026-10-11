import AppKit
import TearsheetCore

/// Runs a capture end to end: snapshot, select, then copy, thumbnail and (optionally) editor.
final class CaptureCoordinator {
    private let thumbnails = ThumbnailStack()
    private let editors = EditorRegistry()
    private var isCapturing = false

    init() {
        thumbnails.onAnnotate = { [editors] item in editors.open(item) }
    }

    func captureRegion(openEditor: Bool) async {
        await select(mode: .capture, openEditor: openEditor)
    }

    /// Picks images off the front Safari or Chrome tab; any other front app gets a region capture.
    func extractImages() async {
        await select(mode: .extract, openEditor: false)
    }

    private func select(mode: OverlayController.Mode, openEditor: Bool) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        let previousApp = NSWorkspace.shared.frontmostApplication
        let tab = BrowserTab(app: previousApp) ?? BrowserTab.underPointer()
        // Ask for Automation consent before the overlay, which would hide the system prompt.
        if mode == .extract, let tab { await tab.requestAutomationConsent() }

        let snapshots: [DisplaySnapshot]
        do {
            snapshots = try await ScreenGrabber.snapshotAllDisplays(excludingWindowNumbers: thumbnails.windowNumbers)
        } catch {
            report(error)
            return
        }

        let overlay = OverlayController(mode: mode, loadImages: tab.map { tab in { try await Self.screenImages(in: tab) } })
        let result = await overlay.select(on: snapshots)
        if !openEditor, let previousApp, previousApp != NSRunningApplication.current { previousApp.activate() }

        switch result {
        case nil:
            return
        case let .region(selection):
            Preferences.lastRegion = LastRegion(displayID: selection.snapshot.displayID, rect: selection.rect)
            deliver(crop(selection.snapshot, to: selection.rect), scale: selection.snapshot.scale, openEditor: openEditor)
        case let .images(found):
            guard let tab else { return }
            await deliverImages(found, from: tab, snapshots: snapshots)
        }
    }

    func repeatLastRegion() async {
        guard let last = Preferences.lastRegion,
              let screen = NSScreen.screens.first(where: { $0.displayID == last.displayID }) else {
            await captureRegion(openEditor: false)
            return
        }
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            guard let snapshot = try await ScreenGrabber.snapshot(screens: [screen], excludingWindowNumbers: thumbnails.windowNumbers).first else { return }
            let rect = last.rect.intersection(CGRect(origin: .zero, size: screen.frame.size))
            guard !rect.isNull, rect.width >= 2, rect.height >= 2 else { return }
            deliver(crop(snapshot, to: rect), scale: snapshot.scale, openEditor: false)
        } catch {
            report(error)
        }
    }

    private func crop(_ snapshot: DisplaySnapshot, to rect: CGRect) -> CGImage? {
        let pixels = SelectionGeometry.pixelRect(for: rect, viewHeight: snapshot.screen.frame.height, scale: snapshot.scale)
        return snapshot.image.cropping(to: pixels)
    }

    private func deliver(_ image: CGImage?, scale: CGFloat, openEditor: Bool) {
        guard let image else { return }
        do {
            let item = try CaptureItem(image: image, scale: scale)
            Clipboard.copy(item)
            thumbnails.show(item)
            if openEditor { editors.open(item) }
        } catch {
            report(error)
        }
    }

    // MARK: Web images

    /// Scans the tab and places each image on screen.
    private static func screenImages(in tab: BrowserTab) async throws -> [ScreenImage] {
        try await tab.checkAutomationConsent()
        let scan = try await tab.scan()
        guard let window = tab.frontWindowFrame(), let primary = NSScreen.screens.first else {
            throw BrowserTab.Failure.noWindow(tab.browser)
        }
        // CGWindowList is top-left; AppKit is bottom-left of the primary display.
        func appKit(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
        }
        let centre = CGPoint(x: appKit(window).midX, y: appKit(window).midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? primary
        let mapping = ViewportMapping(metrics: scan.metrics, windowFrame: window, backingScale: screen.backingScaleFactor)
        let pageURL = URL(string: scan.metrics.baseURL)
        return scan.images().compactMap { image in
            let visible = mapping.screenRect(for: image.rect).intersection(mapping.viewport)
            guard !visible.isNull, visible.width >= 4, visible.height >= 4 else { return nil }
            return ScreenImage(image: image, frame: appKit(visible), pageURL: pageURL)
        }
    }

    private func deliverImages(_ found: [ScreenImage], from tab: BrowserTab, snapshots: [DisplaySnapshot]) async {
        var chosen = found
        if found.count > 1 {
            let picker = ImagePicker(candidates: found) { [self] in renderedCopy(of: $0, in: snapshots)?.image }
            guard let picked = await picker.choose() else { return }
            chosen = picked
        }

        var items: [CaptureItem] = []
        for candidate in chosen {
            let fetched = await WebImageFetcher(tab: tab, pageURL: candidate.pageURL).fetch(candidate.image)
            do {
                if let item = try makeItem(candidate, fetched: fetched, snapshots: snapshots) { items.append(item) }
            } catch {
                report(error)
            }
        }
        guard !items.isEmpty else { return }
        Clipboard.copy(items)
        for item in items { thumbnails.show(item) }
    }

    /// The original when it decodes; otherwise the frozen screen behind it, named as a rendered copy.
    private func makeItem(_ candidate: ScreenImage, fetched: FetchedImage?, snapshots: [DisplaySnapshot]) throws -> CaptureItem? {
        let rendered = renderedCopy(of: candidate, in: snapshots)
        let scale = rendered?.scale ?? NSScreen.main?.backingScaleFactor ?? 2
        // Bytes that don't decode (an error page, a login form) aren't the image; use the rendered copy.
        if let fetched, let image = ImageCoding.decode(fetched.data, rasterScale: scale) {
            return try CaptureItem(image: image, scale: scale, web: WebOrigin(data: fetched.data, filename: fetched.filename))
        }
        guard let rendered else { return nil }
        var url: URL?
        if case let .url(source) = candidate.image.source { url = source }
        return try CaptureItem(image: rendered.image, scale: rendered.scale, web: WebOrigin(data: nil, filename: WebImageFilename.renderedCopyName(for: url)))
    }

    private func renderedCopy(of candidate: ScreenImage, in snapshots: [DisplaySnapshot]) -> (image: CGImage, scale: CGFloat)? {
        let centre = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
        guard let snapshot = snapshots.first(where: { $0.screen.frame.contains(centre) }) else { return nil }
        let origin = snapshot.screen.frame.origin
        let local = candidate.frame.offsetBy(dx: -origin.x, dy: -origin.y).intersection(CGRect(origin: .zero, size: snapshot.screen.frame.size))
        guard !local.isNull, let image = crop(snapshot, to: local) else { return nil }
        return (image, snapshot.scale)
    }

    private func report(_ error: Error) {
        guard ScreenRecordingPermission.isGranted else {
            ScreenRecordingPermission.showMissingAlert()
            return
        }
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}

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
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        let previousApp = NSWorkspace.shared.frontmostApplication
        let snapshots: [DisplaySnapshot]
        do {
            snapshots = try await ScreenGrabber.snapshotAllDisplays(excludingWindowNumbers: thumbnails.windowNumbers)
        } catch {
            report(error)
            return
        }

        let selection = await OverlayController().select(on: snapshots)
        if !openEditor, let previousApp, previousApp != NSRunningApplication.current { previousApp.activate() }
        guard let selection else { return }

        Preferences.lastRegion = LastRegion(displayID: selection.snapshot.displayID, rect: selection.rect)
        deliver(crop(selection.snapshot, to: selection.rect), scale: selection.snapshot.scale, openEditor: openEditor)
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

    private func report(_ error: Error) {
        guard ScreenRecordingPermission.isGranted else {
            ScreenRecordingPermission.showMissingAlert()
            return
        }
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}

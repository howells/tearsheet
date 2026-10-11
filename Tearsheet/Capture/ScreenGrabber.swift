import AppKit
import ScreenCaptureKit

/// A frozen image of one display, taken before the overlay appears so the
/// overlay never shows up in its own capture.
struct DisplaySnapshot {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let image: CGImage

    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

enum ScreenGrabber {
    /// Snapshots every display, leaving out the given windows (Tearsheet's thumbnails).
    static func snapshotAllDisplays(excludingWindowNumbers excluded: Set<Int>) async throws -> [DisplaySnapshot] {
        try await snapshot(screens: NSScreen.screens, excludingWindowNumbers: excluded)
    }

    static func snapshot(screens: [NSScreen], excludingWindowNumbers excluded: Set<Int>) async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedWindows = content.windows.filter { excluded.contains(Int($0.windowID)) }
        var snapshots: [DisplaySnapshot] = []
        for screen in screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * scale).rounded())
            configuration.height = Int((filter.contentRect.height * scale).rounded())
            configuration.captureResolution = .best
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            snapshots.append(DisplaySnapshot(screen: screen, displayID: displayID, image: image))
        }
        return snapshots
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}

import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let coordinator: CaptureCoordinator
    private let openSettings: () -> Void
    /// Set while the first run is unfinished; offers to pick it up again.
    var openSetup: (() -> Void)?

    init(coordinator: CaptureCoordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        super.init()
        item.button?.image = Self.glyph
        menu.delegate = self
        item.menu = menu
    }

    /// The app icon reduced to one colour: a print with its corner turned up.
    static let glyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let sheet = NSBezierPath()
            sheet.move(to: NSPoint(x: 4.5, y: 2.5))
            sheet.line(to: NSPoint(x: 13.5, y: 2.5))
            sheet.line(to: NSPoint(x: 13.5, y: 11))
            sheet.line(to: NSPoint(x: 10, y: 14.5))
            sheet.line(to: NSPoint(x: 4.5, y: 14.5))
            sheet.close()
            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: 13.5, y: 11))
            fold.line(to: NSPoint(x: 10, y: 11))
            fold.line(to: NSPoint(x: 10, y: 14.5))
            for path in [sheet, fold] {
                path.lineWidth = 1.5
                path.lineJoinStyle = .round
                path.stroke()
            }
            NSBezierPath(rect: NSRect(x: 6.5, y: 5, width: 5, height: 3.5)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tearsheet"
        return image
    }()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(entry("Capture Region", key: "4", modifiers: [.command, .shift], action: #selector(captureRegion)))
        menu.addItem(entry("Capture and Annotate", key: "4", modifiers: [.command, .shift, .option], action: #selector(captureIntoEditor)))
        menu.addItem(entry("Repeat Last Region", key: "6", modifiers: [.command, .shift, .option], action: #selector(repeatLastRegion)))
        menu.addItem(entry("Extract Images", key: "i", modifiers: [.command, .shift, .option], action: #selector(extractImages)))
        if SystemScreenshotShortcut.isEnabled {
            menu.addItem(.separator())
            menu.addItem(entry("Use ⇧⌘4 for Tearsheet", action: #selector(takeShiftCommand4)))
        }
        if !ScreenRecordingPermission.isGranted {
            menu.addItem(entry("Grant Screen Recording Access…", action: #selector(openPermissionSettings)))
        }
        menu.addItem(.separator())
        if openSetup != nil { menu.addItem(entry("Set Up Tearsheet…", action: #selector(showSetup))) }
        menu.addItem(entry("Settings…", key: ",", action: #selector(showSettings)))
        menu.addItem(entry("Quit Tearsheet", key: "q", action: #selector(quit)))
    }

    private func entry(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func captureRegion() { Task { await coordinator.captureRegion(openEditor: false) } }
    @objc private func captureIntoEditor() { Task { await coordinator.captureRegion(openEditor: true) } }
    @objc private func repeatLastRegion() { Task { await coordinator.repeatLastRegion() } }
    @objc private func extractImages() { Task { await coordinator.extractImages() } }
    @objc private func takeShiftCommand4() { SystemScreenshotShortcut.turnOff() }
    @objc private func openPermissionSettings() { ScreenRecordingPermission.openSettings() }
    @objc private func showSettings() { openSettings() }
    @objc private func showSetup() { openSetup?() }
    @objc private func quit() { NSApp.terminate(nil) }
}

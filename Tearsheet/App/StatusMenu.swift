import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let coordinator: CaptureCoordinator
    private let openSettings: () -> Void

    init(coordinator: CaptureCoordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Tearsheet")
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(entry("Capture Region", key: "4", modifiers: [.command, .shift], action: #selector(captureRegion)))
        menu.addItem(entry("Capture and Annotate", key: "4", modifiers: [.command, .shift, .option], action: #selector(captureIntoEditor)))
        menu.addItem(entry("Repeat Last Region", key: "6", modifiers: [.command, .shift], action: #selector(repeatLastRegion)))
        if SystemScreenshotShortcut.isEnabled {
            menu.addItem(.separator())
            menu.addItem(entry("Turn Off macOS ⇧⌘4 to Use Tearsheet…", action: #selector(openKeyboardSettings)))
        }
        if !ScreenRecordingPermission.isGranted {
            menu.addItem(entry("Grant Screen Recording Access…", action: #selector(openPermissionSettings)))
        }
        menu.addItem(.separator())
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
    @objc private func openKeyboardSettings() { SystemScreenshotShortcut.openSettings() }
    @objc private func openPermissionSettings() { ScreenRecordingPermission.openSettings() }
    @objc private func showSettings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

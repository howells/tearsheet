import AppKit
import CoreGraphics
import ServiceManagement

enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func request() { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func showMissingAlert() {
        let alert = NSAlert()
        alert.messageText = "Tearsheet needs Screen Recording access"
        alert.informativeText = "Turn on Tearsheet in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Tearsheet."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { openSettings() }
    }
}

enum SystemScreenshotShortcut {
    /// Whether any macOS screenshot shortcut still claims ⇧⌘4. That is "Save picture
    /// of selected area" (symbolic hot key 30) by default, but any of the screenshot
    /// entries can be rebound to it. Read-only: Tearsheet never edits this domain.
    static var isEnabled: Bool {
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        let keys = value as? [String: Any] ?? [:]
        let shiftCommand4 = (keyCode: 21, modifiers: 0x12_0000)
        return ["28", "29", "30", "31", "184"].contains { id in
            guard let entry = keys[id] as? [String: Any] else { return id == "30" }
            guard (entry["enabled"] as? Bool) ?? true else { return false }
            guard let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int], parameters.count == 3 else { return id == "30" }
            return parameters[1] == shiftCommand4.keyCode && parameters[2] == shiftCommand4.modifiers
        }
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Only the installed copy registers itself; Xcode builds in DerivedData
    /// would otherwise claim the login item.
    static func configureOnFirstInstalledLaunch() {
        guard !Preferences.didConfigureLaunchAtLogin, Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        try? set(true)
        Preferences.didConfigureLaunchAtLogin = true
    }
}

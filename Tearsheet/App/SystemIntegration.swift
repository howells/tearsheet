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
    /// Whether macOS still owns ⇧⌘4 ("Save picture of selected area as a file",
    /// symbolic hot key 30). Read-only: Tearsheet never edits this domain.
    static var isEnabled: Bool {
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        guard let keys = value as? [String: Any], let entry = keys["30"] as? [String: Any] else { return true }
        return (entry["enabled"] as? Bool) ?? true
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

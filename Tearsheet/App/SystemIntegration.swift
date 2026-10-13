import AppKit
import CoreGraphics
import ServiceManagement

enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func request() { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// Starts a fresh copy once this one has quit, which is what macOS needs
    /// before a newly granted Screen Recording permission takes effect.
    static func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$2\"", "sh", String(getpid()), Bundle.main.bundlePath]
        try? reopen.run()
        NSApp.terminate(nil)
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
    /// entries can be rebound to it. A fresh Mac has no entry for 30 at all, which
    /// means the default: on, at ⇧⌘4.
    static var isEnabled: Bool {
        let keys = symbolicHotKeys
        return screenshotIDs.contains { claims($0, in: keys) }
    }

    /// Switches off whichever macOS screenshot shortcuts claim ⇧⌘4, the same edit
    /// unticking them in Keyboard settings makes, and applies it at once. The other
    /// screenshot shortcuts are left alone. Posts `didTurnOff` once it has applied.
    static func turnOff() {
        var keys = symbolicHotKeys
        for id in screenshotIDs where claims(id, in: keys) {
            var entry = keys[id] as? [String: Any] ?? [:]
            if entry["value"] == nil { entry["value"] = ["parameters": [52, 21, 0x12_0000], "type": "standard"] }
            entry["enabled"] = false
            keys[id] = entry
        }
        CFPreferencesSetAppValue("AppleSymbolicHotKeys" as CFString, keys as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        // Tells the window server to reread the shortcuts now, not at next login.
        let apply = Process()
        apply.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        apply.arguments = ["-u"]
        apply.terminationHandler = { _ in Task { @MainActor in announce() } }
        do { try apply.run() } catch { announce() }
    }

    static let didTurnOff = Notification.Name("TearsheetSystemShortcutDidTurnOff")

    private static func announce() { NotificationCenter.default.post(name: didTurnOff, object: nil) }

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let screenshotIDs = ["28", "29", "30", "31", "184"]

    private static var symbolicHotKeys: [String: Any] {
        CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
    }

    private static func claims(_ id: String, in keys: [String: Any]) -> Bool {
        let shiftCommand4 = (keyCode: 21, modifiers: 0x12_0000)
        guard let entry = keys[id] as? [String: Any] else { return id == "30" }
        guard (entry["enabled"] as? Bool) ?? true else { return false }
        guard let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int], parameters.count == 3 else { return id == "30" }
        return parameters[1] == shiftCommand4.keyCode && parameters[2] == shiftCommand4.modifiers
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

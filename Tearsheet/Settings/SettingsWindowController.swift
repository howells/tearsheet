import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Tearsheet Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @State private var folder = Preferences.saveFolder
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var hasPermission = ScreenRecordingPermission.isGranted
    @State private var systemShortcutOn = SystemScreenshotShortcut.isEnabled

    var body: some View {
        Form {
            Section("Saving") {
                LabeledContent("Folder") {
                    HStack {
                        Text(folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchError {
                    Text(launchError).foregroundStyle(.red).font(.callout)
                }
            }

            Section("Shortcuts") {
                LabeledContent("Capture region", value: "⇧⌘4")
                LabeledContent("Capture and annotate", value: "⌥⇧⌘4")
                LabeledContent("Repeat last region", value: "⇧⌘6")
                if systemShortcutOn {
                    LabeledContent {
                        Button("Open Keyboard Settings") { SystemScreenshotShortcut.openSettings() }
                    } label: {
                        Text("macOS still owns ⇧⌘4")
                        Text("Turn off Screenshots → “Save picture of selected area as a file”.")
                    }
                }
            }

            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    if hasPermission {
                        Text("Granted").foregroundStyle(.secondary)
                    } else {
                        Button("Open System Settings") { ScreenRecordingPermission.openSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = ScreenRecordingPermission.isGranted
            systemShortcutOn = SystemScreenshotShortcut.isEnabled
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Preferences.saveFolder = url
        folder = url
    }
}

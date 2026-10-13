import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = DarkroomWindow.make(title: "Settings", content: SettingsView())
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @State private var folder = Preferences.saveFolder
    @State private var corner = Preferences.thumbnailCorner
    @State private var launchError: String?
    @State private var hasPermission = ScreenRecordingPermission.isGranted
    @State private var systemShortcutOn = SystemScreenshotShortcut.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            WindowHeading(title: "Settings")

            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 0) {
                    Row(height: 52, trailingPadding: 6) {
                        Text("Save to")
                    } trailing: {
                        HStack(spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: "folder").font(.system(size: 12))
                                Text(folder.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            }
                            .foregroundStyle(Color.muted)
                            TintedButton("Choose…", action: chooseFolder)
                        }
                    }
                    Hairline()
                    Row(height: 52, trailingPadding: 6) {
                        Text("Thumbnails")
                    } trailing: {
                        CornerMenu(corner: $corner)
                            .onChange(of: corner) { _, corner in Preferences.thumbnailCorner = corner }
                    }
                    Hairline()
                    Row(height: 52) {
                        Text("Open at login")
                    } trailing: {
                        LaunchAtLoginToggle(error: $launchError)
                    }
                }
                .groupBox()
                .overlay(alignment: .bottomLeading) { LaunchAtLoginError(message: launchError) }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shortcuts")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, 4)
                    ShortcutList().groupBox()
                }

                VStack(spacing: 0) {
                    Row(height: 52, trailingPadding: hasPermission ? 16 : 6) {
                        Text("Screen recording")
                    } trailing: {
                        if hasPermission {
                            Status("Allowed", symbol: "checkmark")
                        } else {
                            HStack(spacing: 10) {
                                Status("Not allowed", symbol: nil)
                                TintedButton("Open System Settings…") { ScreenRecordingPermission.openSettings() }
                            }
                        }
                    }
                    if systemShortcutOn {
                        Hairline()
                        Row(height: 52, trailingPadding: 6) {
                            Text("macOS screenshot shortcut")
                        } trailing: {
                            HStack(spacing: 10) {
                                Status("Uses ⇧⌘4", symbol: nil)
                                TintedButton("Use for Tearsheet") { SystemScreenshotShortcut.turnOff() }
                            }
                        }
                    }
                }
                .groupBox()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.paper)
        .frame(width: 540)
        .background(Color.graphite)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = ScreenRecordingPermission.isGranted
            systemShortcutOn = SystemScreenshotShortcut.isEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: SystemScreenshotShortcut.didTurnOff)) { _ in
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

import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = [.preferredContentSize]
            // The heading shares the title bar with the window controls, so no safe-area inset.
            hosting.safeAreaRegions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            // An empty unified toolbar centres the window controls in the 52-point header.
            window.toolbar = NSToolbar(identifier: "settings")
            window.toolbarStyle = .unified
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Darkroom.graphite
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private extension Color {
    static let paper = Color(nsColor: Darkroom.paper)
    static let muted = Color(nsColor: Darkroom.muted)
    static let graphite = Color(nsColor: Darkroom.graphite)
    static let raised = Color(nsColor: Darkroom.graphiteRaised)
}

private struct SettingsView: View {
    @State private var folder = Preferences.saveFolder
    @State private var corner = Preferences.thumbnailCorner
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var hasPermission = ScreenRecordingPermission.isGranted
    @State private var systemShortcutOn = SystemScreenshotShortcut.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 52)

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
                        PaperToggle(isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in
                                do {
                                    try LaunchAtLogin.set(enabled)
                                    launchError = nil
                                } catch {
                                    launchError = error.localizedDescription
                                }
                                launchAtLogin = LaunchAtLogin.isEnabled
                            }
                    }
                }
                .groupBox()
                .overlay(alignment: .bottomLeading) {
                    if let launchError {
                        Text(launchError).font(.system(size: 12)).foregroundStyle(Color(nsColor: AnnotationColor.red.nsColor)).offset(x: 16, y: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shortcuts")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ShortcutRow(title: "Capture region", keys: ["⇧", "⌘", "4"])
                        Hairline()
                        ShortcutRow(title: "Capture and annotate", keys: ["⌥", "⇧", "⌘", "4"])
                        Hairline()
                        ShortcutRow(title: "Repeat last region", keys: ["⌥", "⇧", "⌘", "6"])
                        Hairline()
                        ShortcutRow(title: "Extract images", keys: ["⌥", "⇧", "⌘", "I"])
                    }
                    .groupBox()
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
                                TintedButton("Open Settings…") { ScreenRecordingPermission.openSettings() }
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

// MARK: Pieces

private struct Row<Leading: View, Trailing: View>: View {
    var height: CGFloat
    var trailingPadding: CGFloat = 16
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, trailingPadding)
        .frame(height: height)
    }
}

private struct ShortcutRow: View {
    var title: String
    var keys: [String]

    var body: some View {
        Row(height: 48, trailingPadding: 12) {
            Text(title)
        } trailing: {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 26, minHeight: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                                .overlay(alignment: .bottom) {
                                    // The keycap's lower lip.
                                    RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)).frame(height: 1).padding(.horizontal, 2)
                                }
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(keys.joined())
        }
    }
}

private struct Status: View {
    var text: String
    var symbol: String?

    init(_ text: String, symbol: String?) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(text)
        }
        .foregroundStyle(Color.muted)
    }
}

private struct TintedButton: View {
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) { TintedLabel { Text(title) } }
            .buttonStyle(.plain)
    }
}

/// The face shared by tinted buttons and menus: a quiet 28-point plate in a 44-point target.
private struct TintedLabel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.paper)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

/// Picks the corner the thumbnails gather in.
private struct CornerMenu: View {
    @Binding var corner: ScreenCorner

    var body: some View {
        Menu {
            Picker("Thumbnails", selection: $corner) {
                ForEach(ScreenCorner.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            TintedLabel {
                HStack(spacing: 6) {
                    Text(corner.title)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// On: a paper track with a graphite knob, as in the mockup. Off: a quiet track.
private struct PaperToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? Color.paper : Color.white.opacity(0.18))
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? Color.graphite : Color.paper).frame(width: 18, height: 18).padding(2)
                }
                .animation(.snappy(duration: 0.18), value: isOn)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle("Open at login", isOn: $isOn) }
    }
}

/// One point of white at 6%, between rows. A system `Divider` draws its own line under any tint.
private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color(nsColor: Darkroom.hairline)).frame(height: 1)
    }
}

private extension View {
    /// A raised panel with no outline; the fill alone separates it from the window.
    func groupBox() -> some View {
        background(RoundedRectangle(cornerRadius: 10).fill(Color.raised))
    }
}

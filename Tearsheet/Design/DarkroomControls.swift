import AppKit
import SwiftUI

// The SwiftUI pieces of Tearsheet's windows, shared by Settings and the first run.

enum DarkroomWindow {
    /// A graphite window whose SwiftUI content draws its own 52-point heading
    /// across a transparent title bar, sized to fit the content.
    static func make(title: String, content: some View) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        // The heading shares the title bar with the window controls, so no safe-area inset.
        hosting.safeAreaRegions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar centres the window controls in the 52-point header.
        window.toolbar = NSToolbar(identifier: title)
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Darkroom.graphite
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Size to the content before centring, or it centres as if it had none.
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        return window
    }
}

/// The window heading, in the title bar beside the window controls.
struct WindowHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
    }
}

/// `DarkroomButton` in SwiftUI, for a window's leading or secondary action.
struct DarkroomButtonView: NSViewRepresentable {
    var title: String
    var style: DarkroomButton.Style
    /// Return presses it.
    var isDefault = false
    var action: () -> Void

    func makeNSView(context: Context) -> DarkroomButton {
        DarkroomButton(title, style: style, handler: action)
    }

    func updateNSView(_ button: DarkroomButton, context: Context) {
        button.title = title
        button.handler = action
        button.isDefault = isDefault
        // Follows `.disabled(_:)`, as SwiftUI's own buttons do.
        button.isEnabled = context.environment.isEnabled
    }
}

/// `DarkroomPill` in SwiftUI.
struct DarkroomPillView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> DarkroomPill { DarkroomPill(text, font: Darkroom.valueFont()) }
    func updateNSView(_ pill: DarkroomPill, context: Context) { pill.text = text }
}

extension Color {
    static let paper = Color(nsColor: Darkroom.paper)
    static let muted = Color(nsColor: Darkroom.muted)
    static let graphite = Color(nsColor: Darkroom.graphite)
    static let raised = Color(nsColor: Darkroom.graphiteRaised)
}

struct Row<Leading: View, Trailing: View>: View {
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

struct ShortcutRow: View {
    var title: String
    var keys: [String]

    var body: some View {
        Row(height: 48, trailingPadding: 12) {
            Text(title)
        } trailing: {
            Keycaps(keys: keys)
        }
    }
}

/// Tearsheet's four shortcuts.
struct ShortcutList: View {
    var body: some View {
        VStack(spacing: 0) {
            ShortcutRow(title: "Capture region", keys: ["⇧", "⌘", "4"])
            Hairline()
            ShortcutRow(title: "Capture and annotate", keys: ["⌥", "⇧", "⌘", "4"])
            Hairline()
            ShortcutRow(title: "Repeat last region", keys: ["⌥", "⇧", "⌘", "6"])
            Hairline()
            ShortcutRow(title: "Extract images", keys: ["⌥", "⇧", "⌘", "I"])
        }
    }
}

/// Open at login, switched at once. A refusal from macOS comes back as `error`.
struct LaunchAtLoginToggle: View {
    @Binding var error: String?
    @State private var isOn = LaunchAtLogin.isEnabled

    var body: some View {
        PaperToggle(label: "Open at login", isOn: $isOn)
            .onChange(of: isOn) { _, enabled in
                do {
                    try LaunchAtLogin.set(enabled)
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
                isOn = LaunchAtLogin.isEnabled
            }
    }
}

/// Why Open at login didn't change, hung below the group that holds the toggle.
struct LaunchAtLoginError: View {
    var message: String?

    var body: some View {
        if let message {
            Text(message).font(.system(size: 12)).foregroundStyle(Color(nsColor: AnnotationColor.red.nsColor)).offset(x: 16, y: 18)
        }
    }
}

/// A shortcut drawn as keys, read aloud as one.
struct Keycaps: View {
    var keys: [String]

    var body: some View {
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
        .accessibilityLabel(spoken)
    }

    /// "Shift Command 4", as the keys are said.
    private var spoken: String {
        let names = ["⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command"]
        return keys.map { names[$0] ?? $0 }.joined(separator: " ")
    }
}

struct Status: View {
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

struct TintedButton: View {
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
struct TintedLabel<Content: View>: View {
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
struct CornerMenu: View {
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
struct PaperToggle: View {
    var label: String
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
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

/// One point of white at 6%, between rows. A system `Divider` draws its own line under any tint.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color(nsColor: Darkroom.hairline)).frame(height: 1)
    }
}

extension View {
    /// A raised panel with no outline; the fill alone separates it from the window.
    func groupBox() -> some View {
        background(RoundedRectangle(cornerRadius: 10).fill(Color.raised))
    }
}

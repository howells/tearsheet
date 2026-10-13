import SwiftUI
import TearsheetCore

struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchError: String?

    var body: some View {
        VStack(spacing: 0) {
            WindowHeading(title: "Set up Tearsheet")

            VStack(alignment: .leading, spacing: 16) {
                Stage(model: model)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .groupBox()

                // A fixed height, so the window keeps its size from step to step.
                ZStack(alignment: .topLeading) {
                    controls
                        .id(model.step)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.paper)
        .frame(width: 540)
        .background(Color.graphite)
    }

    /// The next step's controls slide in from the right as the last one leaves to the left.
    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 16)),
            removal: .opacity.combined(with: .offset(x: -16))
        )
    }

    // MARK: Steps

    @ViewBuilder private var controls: some View {
        switch model.step {
        case .screenRecording: screenRecording
        case .shortcut: shortcut
        case .firstCapture: firstCapture
        case .ready: ready
        }
    }

    private var screenRecording: some View {
        VStack(alignment: .leading, spacing: 10) {
            Row(height: 52, trailingPadding: model.recordingStatus == .notAllowed || model.recordingStatus == .needsReopen ? 6 : 16) {
                Text("Screen recording")
            } trailing: {
                Group {
                    switch model.recordingStatus {
                    case .notAllowed:
                        HStack(spacing: 10) {
                            Status("Not allowed", symbol: nil)
                            TintedButton(model.hasAsked ? "Open System Settings…" : "Allow…", action: model.allow)
                        }
                    case .checking:
                        Status("Checking…", symbol: nil)
                    case .allowed:
                        Status("Allowed", symbol: "checkmark")
                    case .needsReopen:
                        HStack(spacing: 10) {
                            Status("Reopen to finish", symbol: nil)
                            TintedButton("Reopen", action: model.reopen)
                        }
                    }
                }
                .transition(.opacity)
            }
            .animation(Darkroom.Motion.entrance(0.2), value: model.recordingStatus)
            .groupBox()

            Note("Nothing leaves your Mac.")
        }
    }

    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Row(height: 52) {
                Keycaps(keys: ["⇧", "⌘", "4"])
            } trailing: {
                Group {
                    if model.macOSClaimsShortcut {
                        Status("Used by macOS", symbol: nil)
                    } else {
                        Status("Tearsheet", symbol: "checkmark")
                    }
                }
                .transition(.opacity)
            }
            .groupBox()

            Note("Switches off the macOS ⇧⌘4 in Keyboard settings, where you can switch it back on.")
        }
    }

    private var firstCapture: some View {
        VStack(spacing: 0) {
            Row(height: 52, trailingPadding: 6) {
                Text("Thumbnails")
            } trailing: {
                CornerMenu(corner: $model.corner)
            }
            Hairline()
            Row(height: 52, trailingPadding: model.captured == nil ? 6 : 16) {
                Text("Capture region")
            } trailing: {
                Group {
                    if let captured = model.captured {
                        Status("Copied · \(captured.image.width) × \(captured.image.height)", symbol: "checkmark")
                            .monospacedDigit()
                    } else {
                        HStack(spacing: 10) {
                            if !model.macOSClaimsShortcut { Keycaps(keys: ["⇧", "⌘", "4"]) }
                            TintedButton("Capture", action: model.captureNow)
                        }
                    }
                }
                .transition(.opacity)
            }
            .animation(Darkroom.Motion.entrance(0.2), value: model.captured == nil)
        }
        .groupBox()
    }

    private var ready: some View {
        Row(height: 52) {
            Text("Open at login")
        } trailing: {
            LaunchAtLoginToggle(error: $launchError)
        }
        .groupBox()
        .overlay(alignment: .bottomLeading) { LaunchAtLoginError(message: launchError) }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(model.step.number) of \(OnboardingStep.allCases.count)")
                .foregroundStyle(Color.muted)
                .monospacedDigit()
                .padding(.leading, 4)
            Spacer()
            switch model.step {
            case .screenRecording:
                DarkroomButtonView(title: "Continue", style: .primary, isDefault: true, action: model.advance)
                    .fixedSize()
                    .disabled(model.recordingStatus != .allowed)
            case .shortcut:
                DarkroomButtonView(title: "Keep macOS screenshots", style: .secondary, action: model.keepMacOSShortcut)
                    .fixedSize()
                DarkroomButtonView(title: "Use ⇧⌘4 for Tearsheet", style: .primary, isDefault: true, action: model.useShortcut)
                    .fixedSize()
                    .disabled(!model.macOSClaimsShortcut)
            case .firstCapture:
                // Quiet until there's a capture, so the capture is the thing to do first.
                DarkroomButtonView(title: "Continue", style: model.captured == nil ? .secondary : .primary, isDefault: model.captured != nil, action: model.advance)
                    .fixedSize()
                    .id(model.captured == nil)
            case .ready:
                DarkroomButtonView(title: "Done", style: .primary, isDefault: true, action: model.done)
                    .fixedSize()
            }
        }
        .frame(height: 44)
    }
}

/// A line of consent or constraint under a group: what an action does beyond the obvious.
private struct Note: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).foregroundStyle(Color.muted).padding(.horizontal, 4)
    }
}

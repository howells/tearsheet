import SwiftUI

/// The desktop from the film, in miniature. Until Tearsheet can capture the screen it
/// lies grey and faint, like an undeveloped print; once it can, it develops, and the
/// steps play out on it.
struct Stage: View {
    let model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = model.stage.size
        ZStack(alignment: .topLeading) {
            Color(nsColor: Darkroom.ink)

            // Develops like a print: the scene gains presence first, then colour and
            // contrast more slowly.
            Scene(stage: model.stage)
                .frame(width: StageScene.width, height: model.stage.height)
                .scaleEffect(model.stage.scale, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .saturation(model.developed ? 1 : 0)
                .contrast(model.developed ? 1 : 0.55)
                .brightness(model.developed ? 0 : -0.15)
                .animation(Darkroom.Motion.entrance(reduceMotion ? 0.3 : 1.8), value: model.developed)
                .opacity(model.developed ? 1 : 0.35)
                .animation(Darkroom.Motion.entrance(reduceMotion ? 0.3 : 0.6), value: model.developed)
                .accessibilityHidden(true)

            if let demo = model.demo {
                SelectionView(from: demo.from, to: demo.to, progress: demo.progress, size: size, pixelsPerPoint: model.pixelsPerStagePoint, showsSelection: demo.showsSelection)
                    .opacity(demo.dim)
                    .accessibilityHidden(true)
            }

            ForEach([model.demoCard, model.captureCard].compactMap(\.self)) { card in
                CardView(card: card, radius: max(2, 10 * model.stage.scale))
                    .accessibilityHidden(true)
            }

            if model.step == .ready {
                menu(in: size)
            }
        }
        .frame(width: size.width, height: size.height)
        // The panel's 10-point corners less its 6-point inset.
        .clipShape(RoundedRectangle(cornerRadius: 4))
        // The scene is decoration; only the shortcut menu on the last step is read out.
        .accessibilityElement(children: .contain)
    }

    /// Tearsheet's menu, dropped from its icon in the menu bar, holding the shortcuts.
    private func menu(in size: CGSize) -> some View {
        let width: CGFloat = 300
        let icon = model.stage.onStage(StageScene.glyph)
        let x = min(max(8, icon.minX - 8), size.width - width - 8)
        let y = model.stage.onStage(CGRect(x: 0, y: 0, width: 1, height: StageScene.menuBar)).maxY + 2
        // Opens out of the icon, wherever the menu had to sit to stay on the stage.
        let anchor = UnitPoint(x: (icon.midX - x) / width, y: 0)
        return ZStack(alignment: .topLeading) {
            // As macOS marks a menu-bar item whose menu is open.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: icon.width + 3, height: icon.height + 1)
                .offset(x: icon.minX - 1.5, y: icon.minY - 0.5)
                .opacity(model.menuShown ? 1 : 0)
                .accessibilityHidden(true)
            ShortcutList()
                .frame(width: width)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.graphite))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .scaleEffect(model.menuShown || reduceMotion ? 1 : 0.96, anchor: anchor)
                .opacity(model.menuShown ? 1 : 0)
                .offset(x: x, y: y)
        }
    }
}

/// The film's desktop in scene points: the ocean, a menu bar, and the coat open in a window.
private struct Scene: View {
    let stage: StageScene

    var body: some View {
        let window = stage.window
        ZStack(alignment: .topLeading) {
            Image(nsImage: StageScene.wallpaper)
                .resizable()
                .scaledToFill()
                .frame(width: StageScene.width, height: stage.height)
                .clipped()

            MenuBar()

            VStack(spacing: 0) {
                ZStack {
                    HStack(spacing: 8) {
                        ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { light in
                            Circle().fill(light).frame(width: 12, height: 12)
                        }
                        Spacer()
                    }
                    .padding(.leading, 14)
                    Text("terracotta-coat.jpg")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.paper.opacity(0.75))
                }
                .frame(height: StageScene.titleBar)
                .background(Color.graphite)
                Image(nsImage: StageScene.photo)
                    .resizable()
                    .frame(width: window.width, height: window.height - StageScene.titleBar)
            }
            .frame(width: window.width, height: window.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
            .offset(x: window.minX, y: window.minY)
        }
        .frame(width: StageScene.width, height: stage.height, alignment: .topLeading)
    }
}

/// The film's menu bar: Finder's menus on the left; Tearsheet's icon and the time on the right.
private struct MenuBar: View {
    private static let time: String = {
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return format.string(from: .now)
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black.opacity(0.35))
            HStack(spacing: 20) {
                Text("Finder").fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Text("View")
            }
            .padding(.leading, 20)
            .frame(height: StageScene.menuBar)
            Image(nsImage: StatusMenu.glyph)
                .renderingMode(.template)
                .foregroundStyle(Color.paper)
                .frame(width: StageScene.glyph.width, height: StageScene.glyph.height)
                .offset(x: StageScene.glyph.minX, y: StageScene.glyph.minY)
            Text(Self.time)
                .frame(width: StageScene.width - 20, height: StageScene.menuBar, alignment: .trailing)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.paper)
        .frame(width: StageScene.width, height: StageScene.menuBar)
    }
}

/// The capture overlay in miniature: the screen dimmed except for a selection
/// growing from one corner to the other, with the crosshair and size readout.
private struct SelectionView: View, Animatable {
    var from: CGPoint
    var to: CGPoint
    var progress: CGFloat
    var size: CGSize
    var pixelsPerPoint: CGFloat
    var showsSelection: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let corner = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
        let selection = CGRect(x: from.x, y: from.y, width: corner.x - from.x, height: corner.y - from.y)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                if showsSelection { path.addRect(selection) }
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

            if showsSelection {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                    .frame(width: max(1, selection.width), height: max(1, selection.height))
                    .offset(x: selection.minX, y: selection.minY)
                Crosshair().offset(x: corner.x - 7, y: corner.y - 7)
                if progress > 0.02 {
                    DarkroomPillView(text: "\(Int(selection.width * pixelsPerPoint)) × \(Int(selection.height * pixelsPerPoint))")
                        .fixedSize()
                        .position(x: selection.midX, y: selection.maxY + 20)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct Crosshair: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 7, y: 0)); path.addLine(to: CGPoint(x: 7, y: 14))
            path.move(to: CGPoint(x: 0, y: 7)); path.addLine(to: CGPoint(x: 14, y: 7))
        }
        .stroke(Color.white, lineWidth: 1)
        .frame(width: 14, height: 14)
    }
}

/// A capture on the stage at the scale of the real thumbnail.
private struct CardView: View {
    let card: StageCard
    let radius: CGFloat

    var body: some View {
        Image(nsImage: card.image)
            .resizable()
            .scaledToFill()
            .frame(width: card.frame.width, height: card.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            .shadow(color: .black.opacity(card.lifted ? 0.45 : 0), radius: 5, y: 2)
            .opacity(card.opacity)
            .position(x: card.frame.midX, y: card.frame.midY)
    }
}

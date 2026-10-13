import SwiftUI

/// A miniature of the screen the window opened on. Before Tearsheet may see the
/// screen it shows the desktop picture, grey and faint; once it can, a real
/// capture develops in its place, and the steps play out on it.
struct Stage: View {
    let model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = model.stage.size
        ZStack(alignment: .topLeading) {
            Color(nsColor: Darkroom.ink)

            if let wallpaper = model.wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .saturation(0)
                    .opacity(0.3)
            }

            if let snapshot = model.snapshot {
                // Develops like a print: the image comes up grey and flat, then gains
                // colour and contrast more slowly than it gains presence.
                Image(nsImage: NSImage(cgImage: snapshot, size: size))
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .saturation(model.developed ? 1 : 0)
                    .contrast(model.developed ? 1 : 0.55)
                    .brightness(model.developed ? 0 : -0.15)
                    .animation(Darkroom.Motion.entrance(reduceMotion ? 0.3 : 1.8), value: model.developed)
                    .opacity(model.developed ? 1 : 0)
                    .animation(Darkroom.Motion.entrance(reduceMotion ? 0.3 : 0.6), value: model.developed)
            }

            if let demo = model.demo {
                SelectionView(from: demo.from, to: demo.to, progress: demo.progress, size: size, pixelsPerPoint: model.pixelsPerStagePoint, showsSelection: demo.showsSelection)
                    .opacity(demo.dim)
            }

            ForEach([model.demoCard, model.captureCard].compactMap(\.self)) { card in
                CardView(card: card, radius: max(2, 10 * model.stage.scale))
            }

            if model.step == .ready {
                menu(in: size)
            }
        }
        .frame(width: size.width, height: size.height)
        // The panel's 10-point corners less its 6-point inset.
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }

    /// Tearsheet's menu, dropped from its icon in the menu bar, holding the shortcuts.
    private func menu(in size: CGSize) -> some View {
        let width: CGFloat = 300
        let icon = model.iconOnStage
        let x = min(max(8, (icon?.minX ?? size.width) - 8), size.width - width - 8)
        let y = (icon?.maxY ?? 6) + 4
        // Opens out of the icon, wherever the menu had to sit to stay on the stage.
        let anchor = UnitPoint(x: icon.map { ($0.midX - x) / width } ?? 1, y: 0)
        return ZStack(alignment: .topLeading) {
            if let icon {
                // As macOS marks a menu-bar item whose menu is open.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: icon.width + 4, height: icon.height)
                    .offset(x: icon.minX - 2, y: icon.minY)
                    .opacity(model.menuShown ? 1 : 0)
            }
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

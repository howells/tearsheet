import AppKit

/// Floating thumbnails in the bottom-left corner of the screen under the
/// cursor; the newest sits at the bottom and older ones move up.
final class ThumbnailStack {
    var onAnnotate: ((CaptureItem) -> Void)?

    private var panels: [ThumbnailPanel] = []
    private var screen: NSScreen?
    private let limit = 5
    private let margin: CGFloat = 20
    private let spacing: CGFloat = 12

    var windowNumbers: Set<Int> { Set(panels.map(\.windowNumber)) }

    func show(_ item: CaptureItem) {
        screen = NSScreen.underMouse
        let panel = ThumbnailPanel(item: item, stack: self)
        panels.insert(panel, at: 0)
        while panels.count > limit, let oldest = panels.last { dismiss(oldest) }
        layout(appearing: panel)
        panel.orderFrontRegardless()
    }

    /// Thumbnails arrive from the left edge and leave the same way.
    private let travel: CGFloat = 24

    func dismiss(_ panel: ThumbnailPanel, slidingLeft: Bool = false) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        panel.stopTimer()
        // A swipe throws the card off screen; otherwise it backs out the way it came in.
        let distance = Darkroom.Motion.reduced ? 0 : slidingLeft ? panel.frame.maxX - (screen?.visibleFrame.minX ?? 0) : travel
        Darkroom.Motion.animate(slidingLeft ? 0.25 : 0.2, Darkroom.Motion.easeOut, {
            panel.animator().alphaValue = 0
            if distance > 0 { panel.animateOrigin(to: CGPoint(x: panel.frame.minX - distance, y: panel.frame.minY)) }
        }, completion: { panel.orderOut(nil) })
        layout(appearing: nil)
    }

    func layout(appearing: ThumbnailPanel?) {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let reduced = Darkroom.Motion.reduced
        var y = visible.minY + margin
        for panel in panels {
            let origin = CGPoint(x: visible.minX + margin, y: y)
            panel.homeOrigin = origin
            if panel === appearing {
                panel.setFrameOrigin(CGPoint(x: origin.x - (reduced ? 0 : travel), y: origin.y))
                panel.alphaValue = 0
                Darkroom.Motion.animate(0.3, Darkroom.Motion.easeOut) {
                    panel.animateOrigin(to: origin)
                    panel.animator().alphaValue = 1
                }
            } else if panel.frame.origin != origin {
                if reduced {
                    panel.setFrameOrigin(origin)
                } else {
                    // Older cards make room by moving between two places on screen.
                    Darkroom.Motion.animate(0.28, Darkroom.Motion.easeInOut) { panel.animateOrigin(to: origin) }
                }
            }
            y += panel.frame.height + spacing
        }
    }

    // MARK: Actions

    func copy(_ panel: ThumbnailPanel) {
        Clipboard.copy(panel.item)
        panel.flash("Copied")
    }

    func save(_ panel: ThumbnailPanel, atOneX: Bool) {
        do {
            try Saver.save(panel.item, atOneX: atOneX)
            panel.flash("Saved")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.dismiss(panel) }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    func annotate(_ panel: ThumbnailPanel) {
        onAnnotate?(panel.item)
    }
}

extension NSWindow {
    /// Window animators only animate `frame`; `setFrameOrigin` on the animator jumps or does nothing.
    func animateOrigin(to origin: CGPoint) {
        animator().setFrame(CGRect(origin: origin, size: frame.size), display: true)
    }
}

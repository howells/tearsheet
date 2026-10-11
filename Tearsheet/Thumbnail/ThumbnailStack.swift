import AppKit

/// Floating thumbnails in the bottom-left corner of the screen under the
/// cursor; the newest sits at the bottom and older ones move up.
final class ThumbnailStack {
    var onAnnotate: ((CaptureItem) -> Void)?

    private var panels: [ThumbnailPanel] = []
    private var screen: NSScreen?
    private let limit = 5
    private let margin: CGFloat = 16
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

    func dismiss(_ panel: ThumbnailPanel, slidingLeft: Bool = false) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        panel.stopTimer()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
            if slidingLeft { panel.animator().setFrameOrigin(CGPoint(x: panel.frame.minX - panel.frame.width, y: panel.frame.minY)) }
        }, completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
        layout(appearing: nil)
    }

    func layout(appearing: ThumbnailPanel?) {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        var y = visible.minY + margin
        for panel in panels {
            let origin = CGPoint(x: visible.minX + margin, y: y)
            panel.homeOrigin = origin
            if panel === appearing {
                panel.setFrameOrigin(CGPoint(x: origin.x - panel.frame.width / 2, y: origin.y))
                panel.alphaValue = 0
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(origin)
                panel.animator().alphaValue = 1
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

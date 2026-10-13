import AppKit

/// Floating thumbnails in a corner of the screen under the cursor, bottom left
/// unless Settings says otherwise. At rest they fan out from the corner, newest
/// in front; pointing at the pile stands them up in a column along the side.
final class ThumbnailStack {
    var onAnnotate: ((CaptureItem) -> Void)?

    private var panels: [ThumbnailPanel] = []
    private var screen: NSScreen?
    private let limit = 5
    /// Between the pile and the edges of the screen's visible frame.
    static let margin: CGFloat = 20
    private var margin: CGFloat { Self.margin }
    private let spacing: CGFloat = 12
    private let springs = PoseSprings()

    /// Standing in a column because the pointer is over the pile.
    private(set) var isStanding = false
    private var pointerWatch: Timer?
    private var pointerLeftAt: Date?

    var windowNumbers: Set<Int> { Set(panels.map(\.windowNumber)) }

    init() {
        NotificationCenter.default.addObserver(forName: Preferences.thumbnailCornerDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show(_ item: CaptureItem) {
        screen = NSScreen.underMouse
        let panel = ThumbnailPanel(item: item, stack: self)
        panels.insert(panel, at: 0)
        while panels.count > limit, let oldest = panels.last { dismiss(oldest) }
        layout(appearing: panel, spring: .settle)
        // Newest in front, each older card tucked behind the one before it.
        panel.orderFrontRegardless()
        for (newer, older) in zip(panels, panels.dropFirst()) { older.order(.below, relativeTo: newer.windowNumber) }
    }

    /// Thumbnails arrive from the nearer side of the screen and leave the same way.
    private let travel: CGFloat = 24

    func dismiss(_ panel: ThumbnailPanel, swiped: Bool = false) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        panel.stopTimer()
        // A swipe throws the card off screen; otherwise it backs out the way it came in.
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let offScreen = panel.edgeDirection < 0 ? panel.frame.maxX - visible.minX : visible.maxX - panel.frame.minX
        let distance = Darkroom.Motion.reduced ? 0 : swiped ? offScreen : travel
        panel.pose.x += panel.nudge
        panel.nudge = 0
        panel.target.x = panel.pose.x + panel.edgeDirection * distance
        move(panel)
        Darkroom.Motion.animate(swiped ? 0.25 : 0.2, Darkroom.Motion.easeOut, {
            panel.animator().alphaValue = 0
        }, completion: { [springs] in
            springs.stop(panel)
            panel.orderOut(nil)
        })
        if panels.count < 2 { sitDown(relayout: false) }
        layout()
    }

    func layout(appearing: ThumbnailPanel? = nil, spring: Darkroom.Motion.Spring = .standard) {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        for (panel, target) in zip(panels, poses(standing: isStanding, in: visible)) {
            panel.target = target
            if panel === appearing {
                // Lands level from the screen edge, in front of the pile.
                panel.pose = CardPose(x: target.x + panel.edgeDirection * (Darkroom.Motion.reduced ? 0 : travel), y: target.y, angle: 0)
                panel.apply()
                panel.alphaValue = 0
                Darkroom.Motion.animate(0.3, Darkroom.Motion.easeOut) { panel.animator().alphaValue = 1 }
            }
            move(panel, spring: spring)
        }
    }

    /// Springs a card to its target, or puts it straight there with Reduce Motion on.
    func move(_ panel: ThumbnailPanel, spring: Darkroom.Motion.Spring = .standard) {
        if Darkroom.Motion.reduced {
            panel.pose = panel.target
            panel.velocity = CardPose()
            panel.apply()
        } else {
            springs.move(panel, with: spring)
        }
    }

    // MARK: Fan and column

    /// The corner chosen in Settings, read afresh so a change moves the pile at once.
    var corner: ScreenCorner { Preferences.thumbnailCorner }

    /// At rest the pile is tucked into the corner: the newest card level in front,
    /// each older one behind it turned a little further away from the screen edge,
    /// so the pile opens like a fan pinned at the corner. Standing, the cards line
    /// up along the side of the screen, the newest in the corner.
    private func poses(standing: Bool, in visible: CGRect) -> [CardPose] {
        let corner = self.corner
        let inset = visible.insetBy(dx: margin, dy: margin)
        // The centre that puts a box of this size snug in the corner.
        func tucked(_ size: CGSize) -> CGPoint {
            CGPoint(
                x: corner.isLeft ? inset.minX + size.width / 2 : inset.maxX - size.width / 2,
                y: corner.isBottom ? inset.minY + size.height / 2 : inset.maxY - size.height / 2
            )
        }
        guard !standing, panels.count > 1 else {
            var offset: CGFloat = 0
            return panels.map { panel in
                let size = panel.cardSize
                defer { offset += size.height + spacing }
                let centre = tucked(size)
                return CardPose(x: centre.x, y: centre.y + (corner.isBottom ? offset : -offset))
            }
        }
        let step = min(12, 30 / CGFloat(panels.count - 1))
        // Anticlockwise lifts the far end of a card in the bottom-left corner;
        // the other corners mirror it.
        let turn: CGFloat = corner.isLeft == corner.isBottom ? 1 : -1
        return panels.enumerated().map { index, panel in
            let angle = turn * step * CGFloat(index)
            let centre = tucked(Self.extent(of: panel.cardSize, turnedBy: angle))
            return CardPose(x: centre.x, y: centre.y, angle: angle)
        }
    }

    /// The upright box a card fills once turned.
    private static func extent(of size: CGSize, turnedBy degrees: CGFloat) -> CGSize {
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians)), sine = abs(sin(radians))
        return CGSize(width: size.width * cosine + size.height * sine, height: size.width * sine + size.height * cosine)
    }

    private func footprint(_ poses: [CardPose]) -> CGRect {
        zip(panels, poses).reduce(CGRect.null) { area, pair in
            let size = Self.extent(of: pair.0.cardSize, turnedBy: pair.1.angle)
            return area.union(CGRect(x: pair.1.x - size.width / 2, y: pair.1.y - size.height / 2, width: size.width, height: size.height))
        }
    }

    func pointerEntered() {
        pointerLeftAt = nil
        guard !isStanding, panels.count > 1 else { return }
        isStanding = true
        for panel in panels { panel.stopTimer() }
        layout()
        pointerWatch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
    }

    /// The column folds back into the fan a moment after the pointer leaves both,
    /// so it never folds under a pointer still resting where the fan was.
    private func checkPointer() {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let area = footprint(poses(standing: true, in: visible)).union(footprint(poses(standing: false, in: visible))).insetBy(dx: -8, dy: -8)
        if area.contains(NSEvent.mouseLocation) {
            pointerLeftAt = nil
        } else if let left = pointerLeftAt {
            if Date().timeIntervalSince(left) >= 0.25 { sitDown(relayout: true) }
        } else {
            pointerLeftAt = Date()
        }
    }

    private func sitDown(relayout: Bool) {
        pointerWatch?.invalidate()
        pointerWatch = nil
        pointerLeftAt = nil
        guard isStanding else { return }
        isStanding = false
        for panel in panels where !panel.isHovered { panel.startTimer() }
        if relayout { layout() }
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

/// Moves cards toward their targets on a spring, a frame at a time, so each
/// window, its tilt and its shadow stay together, and a new target mid-flight
/// carries on from the current speed instead of starting over.
final class PoseSprings: NSObject {
    private var moving: [ThumbnailPanel] = []
    private var spring = Darkroom.Motion.Spring.standard
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?

    func move(_ panel: ThumbnailPanel, with spring: Darkroom.Motion.Spring) {
        self.spring = spring
        if !moving.contains(where: { $0 === panel }) { moving.append(panel) }
        guard link == nil, let screen = panel.screen ?? NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop(_ panel: ThumbnailPanel) {
        moving.removeAll { $0 === panel }
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        var remaining = min(1.0 / 30, now - (lastTime ?? link.timestamp))
        lastTime = now
        let k = spring.stiffness, c = spring.damping
        let parts: [WritableKeyPath<CardPose, CGFloat>] = [\.x, \.y, \.angle]
        // Small fixed steps keep the integration steady whatever the refresh rate.
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240)
            for panel in moving {
                for part in parts {
                    let force = -k * (panel.pose[keyPath: part] - panel.target[keyPath: part]) - c * panel.velocity[keyPath: part]
                    panel.velocity[keyPath: part] += force * h
                    panel.pose[keyPath: part] += panel.velocity[keyPath: part] * h
                }
            }
            remaining -= h
        }
        moving.removeAll { panel in
            let settled = parts.allSatisfy { abs(panel.pose[keyPath: $0] - panel.target[keyPath: $0]) < 0.05 && abs(panel.velocity[keyPath: $0]) < 1 }
            if settled {
                panel.pose = panel.target
                panel.velocity = CardPose()
            }
            panel.apply()
            return settled
        }
        if moving.isEmpty {
            link.invalidate()
            self.link = nil
            lastTime = nil
        }
    }
}

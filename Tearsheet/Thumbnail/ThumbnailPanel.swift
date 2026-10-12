import AppKit

/// Where a card sits: its centre on screen and its tilt in degrees, anticlockwise.
struct CardPose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var angle: CGFloat = 0
}

final class ThumbnailPanel: NSPanel {
    let item: CaptureItem
    private unowned let stack: ThumbnailStack
    private let thumbnail: ThumbnailView
    private var timer: Timer?
    private let lifetime: TimeInterval = 8

    /// Room around the card for it to tilt in, as it does in the fan. The window is
    /// clear there, so clicks fall through to whatever is underneath.
    static let padding: CGFloat = 20

    /// Where the card is, where the stack wants it, and how fast it is getting there.
    var pose = CardPose()
    var target = CardPose()
    var velocity = CardPose()
    /// A swipe in progress moves the card with the fingers, on top of its pose.
    var nudge: CGFloat = 0

    var isHovered = false {
        didSet {
            isHovered ? stopTimer() : startTimer()
            if isHovered { stack.pointerEntered() }
        }
    }

    init(item: CaptureItem, stack: ThumbnailStack) {
        self.item = item
        self.stack = stack
        thumbnail = ThumbnailView(item: item)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        // The window shadow follows the card's outline, tilted or not.
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        thumbnail.panel = self

        let host = NSView()
        host.wantsLayer = true
        host.addSubview(thumbnail)
        contentView = host

        item.onChange = { [weak self] in self?.itemChanged() }
        startTimer()
    }

    override var canBecomeKey: Bool { false }

    /// Always 240 points wide, as in the mockup; the height follows the capture
    /// between 96 and 180 points, and the image fills the card.
    static func size(for item: CaptureItem) -> CGSize {
        let aspect = CGFloat(item.image.height) / max(CGFloat(item.image.width), 1)
        return CGSize(width: 240, height: min(180, max(96, (240 * aspect).rounded())))
    }

    var cardSize: CGSize { ThumbnailPanel.size(for: item) }

    /// Puts the window and the card where `pose` says.
    func apply() {
        let size = cardSize
        let pad = ThumbnailPanel.padding
        setFrame(CGRect(x: pose.x + nudge - size.width / 2 - pad, y: pose.y - size.height / 2 - pad, width: size.width + 2 * pad, height: size.height + 2 * pad), display: false)
        if thumbnail.frame.size != size {
            // A tilted view's frame is its bounding box, so size it level.
            let angle = thumbnail.frameCenterRotation
            thumbnail.frameCenterRotation = 0
            thumbnail.frame = CGRect(x: pad, y: pad, width: size.width, height: size.height)
            thumbnail.frameCenterRotation = angle
        }
        if thumbnail.frameCenterRotation != pose.angle {
            thumbnail.frameCenterRotation = pose.angle
            invalidateShadow()
        }
    }

    private func itemChanged() {
        thumbnail.refreshImage()
        stack.layout()
    }

    // MARK: Lifetime

    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: lifetime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timerFired() {
        if isHovered || item.isBeingEdited || stack.isStanding { startTimer() } else { stack.dismiss(self) }
    }

    // MARK: Actions from the view

    func copy() { stack.copy(self) }
    func save(atOneX: Bool) { stack.save(self, atOneX: atOneX) }
    func annotate() { stack.annotate(self) }
    func dismiss(slidingLeft: Bool = false) { stack.dismiss(self, slidingLeft: slidingLeft) }
    func flash(_ message: String) { thumbnail.flash(message) }

    /// Follows the fingers during a swipe; `settleSwipe` springs back home.
    func swipe(to offset: CGFloat) {
        nudge = offset
        apply()
    }

    func settleSwipe() {
        pose.x += nudge
        nudge = 0
        stack.move(self)
    }
}

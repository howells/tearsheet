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

    /// Room for the shadow. The window is a square wide enough for the card at any
    /// tilt; it is clear around the card, so clicks fall through to whatever is underneath.
    static let padding: CGFloat = 20

    /// Where the card is, where the stack wants it, and how fast it is getting there.
    /// The card sits level in the window and turns about its centre.
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

    /// The window is the card plus a clear margin, which reaches into the menu bar
    /// in a top corner. AppKit would push the whole window below the menu bar and
    /// the card with it, so the frame is taken as given.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Always 240 points wide, as in the mockup; the height follows the capture
    /// between 96 and 180 points, and the image fills the card.
    static func size(for item: CaptureItem) -> CGSize {
        size(forPixelWidth: item.image.width, height: item.image.height)
    }

    static func size(forPixelWidth width: Int, height: Int) -> CGSize {
        let aspect = CGFloat(height) / max(CGFloat(width), 1)
        return CGSize(width: 240, height: min(180, max(96, (240 * aspect).rounded())))
    }

    var cardSize: CGSize { ThumbnailPanel.size(for: item) }

    /// Puts the window and the card where `pose` says.
    func apply() {
        let size = cardSize
        let side = (hypot(size.width, size.height) + 2 * ThumbnailPanel.padding).rounded(.up)
        setFrame(CGRect(x: pose.x + nudge - side / 2, y: pose.y - side / 2, width: side, height: side), display: false)
        if thumbnail.bounds.size != size {
            // A tilted view's frame is its bounding box, so size it level.
            let angle = thumbnail.frameCenterRotation
            thumbnail.frameCenterRotation = 0
            thumbnail.frame = CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
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
    func dismiss(swiped: Bool = false) { stack.dismiss(self, swiped: swiped) }
    /// −1 when the thumbnails sit on the left of the screen, 1 on the right.
    var edgeDirection: CGFloat { stack.corner.isLeft ? -1 : 1 }
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

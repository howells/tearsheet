import AppKit

final class ThumbnailPanel: NSPanel {
    let item: CaptureItem
    private unowned let stack: ThumbnailStack
    private let thumbnail: ThumbnailView
    private var timer: Timer?
    private let lifetime: TimeInterval = 8

    /// Where the stack wants this panel; swipes move away from it and spring back.
    var homeOrigin = CGPoint.zero
    var isHovered = false { didSet { isHovered ? stopTimer() : startTimer() } }

    init(item: CaptureItem, stack: ThumbnailStack) {
        self.item = item
        self.stack = stack
        thumbnail = ThumbnailView(item: item)
        super.init(contentRect: CGRect(origin: .zero, size: ThumbnailPanel.size(for: item)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        thumbnail.panel = self
        contentView = thumbnail

        item.onChange = { [weak self] in self?.itemChanged() }
        startTimer()
    }

    override var canBecomeKey: Bool { false }

    /// Fits the capture into 240 × 180 points, never smaller than 160 × 100 so the buttons fit.
    static func size(for item: CaptureItem) -> CGSize {
        let width = CGFloat(item.image.width) / item.scale
        let height = CGFloat(item.image.height) / item.scale
        let factor = min(240 / width, 180 / height, 1)
        return CGSize(width: max(160, (width * factor).rounded()), height: max(100, (height * factor).rounded()))
    }

    private func itemChanged() {
        thumbnail.refreshImage()
        setContentSize(ThumbnailPanel.size(for: item))
        stack.layout(appearing: nil)
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
        if isHovered || item.isBeingEdited { startTimer() } else { stack.dismiss(self) }
    }

    // MARK: Actions from the view

    func copy() { stack.copy(self) }
    func save(atOneX: Bool) { stack.save(self, atOneX: atOneX) }
    func annotate() { stack.annotate(self) }
    func dismiss(slidingLeft: Bool = false) { stack.dismiss(self, slidingLeft: slidingLeft) }
    func flash(_ message: String) { thumbnail.flash(message) }
}

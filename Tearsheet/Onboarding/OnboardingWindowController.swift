import AppKit
import SwiftUI
import TearsheetCore

/// The first run: one window, four steps, over a miniature of the screen it opens on.
/// Closing it part way keeps what's done; the next launch, or Set Up Tearsheet…
/// in the menu, picks up at the first step not yet settled.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    var onFinish: (() -> Void)?
    private let capture: () -> Void
    private let iconFrame: () -> CGRect?
    private var window: NSWindow?
    private var model: OnboardingModel?

    init(capture: @escaping () -> Void, iconFrame: @escaping () -> CGRect?) {
        self.capture = capture
        self.iconFrame = iconFrame
    }

    func show() {
        if window == nil {
            let record = Preferences.onboarding ?? OnboardingRecord()
            let step = Onboarding.resumeStep(record, facts: .current) ?? .ready
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let model = OnboardingModel(step: step, record: record, screen: screen, capture: capture, iconFrame: iconFrame) { [weak self] in
                self?.finish()
            }
            let window = DarkroomWindow.make(title: "Set up Tearsheet", content: OnboardingView(model: model))
            window.delegate = self
            model.window = window
            self.window = window
            self.model = model
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // macOS may decline to activate an app opened in the background; the first run shows regardless.
        window?.orderFrontRegardless()
        model?.start()
    }

    private func finish() {
        window?.close()
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        model = nil
        window = nil
    }
}

extension Onboarding.Facts {
    static var current: Self {
        .init(canRecordScreen: ScreenRecordingPermission.isGranted, macOSClaimsShortcut: SystemScreenshotShortcut.isEnabled)
    }
}

/// The screen the stage shows, in global points, and the stage's own size.
struct StageScreen {
    let displayID: CGDirectDisplayID?
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScale: CGFloat
    let size: CGSize

    init(_ screen: NSScreen) {
        displayID = screen.displayID
        frame = screen.frame
        visibleFrame = screen.visibleFrame
        backingScale = screen.backingScaleFactor
        // As wide as the panel allows, no taller than 320 points for a portrait display.
        var size = CGSize(width: 488, height: 488 * frame.height / frame.width)
        if size.height > 320 { size = CGSize(width: 320 * frame.width / frame.height, height: 320) }
        self.size = CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    /// Stage points per screen point.
    var scale: CGFloat { size.width / frame.width }

    /// A global, bottom-left-origin rectangle in the stage's top-left-origin space.
    func map(_ rect: CGRect) -> CGRect {
        CGRect(x: (rect.minX - frame.minX) * scale, y: (frame.maxY - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale)
    }

    /// Where a thumbnail of this many pixels sits, alone, in `corner`; as `ThumbnailStack` puts it.
    func thumbnailFrame(pixelWidth: Int, height: Int, corner: ScreenCorner) -> CGRect {
        let card = ThumbnailPanel.size(forPixelWidth: pixelWidth, height: height)
        let inset = visibleFrame.insetBy(dx: ThumbnailStack.margin, dy: ThumbnailStack.margin)
        let origin = CGPoint(x: corner.isLeft ? inset.minX : inset.maxX - card.width, y: corner.isBottom ? inset.minY : inset.maxY - card.height)
        return map(CGRect(origin: origin, size: card))
    }
}

/// A capture drawn on the stage: the demonstration's, or the real first one.
struct StageCard: Identifiable {
    let id = UUID()
    let image: NSImage
    let pixelWidth: Int
    let pixelHeight: Int
    var frame: CGRect
    var opacity: Double = 1
    var lifted = false
}

/// The selection drawn across the stage on the ⇧⌘4 step.
struct SelectionDemo {
    var from = CGPoint.zero
    var to = CGPoint.zero
    var progress: CGFloat = 0
    var dim: Double = 0
    var showsSelection = true
}

@MainActor @Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep
    private(set) var record: OnboardingRecord { didSet { Preferences.onboarding = record } }

    // Screen recording
    private(set) var granted = ScreenRecordingPermission.isGranted
    private(set) var captureWorked: Bool?
    private(set) var hasAsked = false
    var recordingStatus: ScreenRecordingStatus { ScreenRecordingStatus(granted: granted, captureWorked: captureWorked) }

    // Stage
    let stage: StageScreen
    let wallpaper: NSImage?
    private(set) var snapshot: CGImage?
    private(set) var developed = false
    private(set) var demo: SelectionDemo?
    private(set) var demoCard: StageCard?
    private(set) var captureCard: StageCard?
    private(set) var menuShown = false
    private(set) var iconOnStage: CGRect?

    // ⇧⌘4
    private(set) var macOSClaimsShortcut = SystemScreenshotShortcut.isEnabled

    // First capture
    var corner = Preferences.thumbnailCorner {
        didSet {
            Preferences.thumbnailCorner = corner
            withAnimation(reduced ? nil : Darkroom.Motion.Spring.standard.animation) { placeCards() }
        }
    }
    private(set) var captured: CaptureCoordinator.Capture?

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private let screen: NSScreen
    @ObservationIgnored private let captureRegion: () -> Void
    @ObservationIgnored private let iconFrame: () -> CGRect?
    @ObservationIgnored private let finish: () -> Void
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var isSnapshotting = false

    private var reduced: Bool { Darkroom.Motion.reduced }

    init(step: OnboardingStep, record: OnboardingRecord, screen: NSScreen, capture: @escaping () -> Void, iconFrame: @escaping () -> CGRect?, finish: @escaping () -> Void) {
        self.step = step
        self.record = record
        self.screen = screen
        stage = StageScreen(screen)
        wallpaper = Self.wallpaper(for: screen)
        captureRegion = capture
        self.iconFrame = iconFrame
        self.finish = finish
    }

    // MARK: Lifetime

    func start() {
        guard observers.isEmpty else { return }
        let centre = NotificationCenter.default
        observers = [
            centre.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            centre.addObserver(forName: SystemScreenshotShortcut.didTurnOff, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.shortcutTurnedOff() }
            },
            centre.addObserver(forName: CaptureCoordinator.didCapture, object: nil, queue: .main) { [weak self] note in
                guard let capture = note.object as? CaptureCoordinator.Capture else { return }
                MainActor.assumeIsolated { self?.landed(capture) }
            },
        ]
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        enter(step)
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        demoTask?.cancel()
    }

    /// Polls what macOS says now; the permission and the shortcut can change in System Settings.
    private func refresh() {
        granted = ScreenRecordingPermission.isGranted
        macOSClaimsShortcut = SystemScreenshotShortcut.isEnabled
        if granted, captureWorked != true { takeSnapshot() }
    }

    // MARK: Steps

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        finishDemo()
        if step == .firstCapture { record.passedFirstCapture = true }
        if next == .ready {
            LaunchAtLogin.configureOnFirstInstalledLaunch()
            iconOnStage = iconFrame().flatMap { frame in
                stage.frame.intersects(frame) ? stage.map(frame) : nil
            }
        }
        withAnimation(Darkroom.Motion.entrance(reduced ? 0.2 : 0.3)) { step = next }
        enter(next)
    }

    private func enter(_ step: OnboardingStep) {
        refresh()
        switch step {
        case .screenRecording:
            break
        case .shortcut, .firstCapture:
            playDemo()
        case .ready:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(Darkroom.Motion.entrance(0.2)) { menuShown = true }
            }
        }
    }

    func done() {
        record.isFinished = true
        finish()
    }

    // MARK: Screen recording

    func allow() {
        if hasAsked {
            ScreenRecordingPermission.openSettings()
        } else {
            hasAsked = true
            ScreenRecordingPermission.request()
        }
    }

    func reopen() { ScreenRecordingPermission.relaunch() }

    /// A real capture of the stage's screen, without this window. If macOS says the
    /// permission is granted but the capture fails, Tearsheet needs reopening.
    private func takeSnapshot() {
        guard !isSnapshotting, let window else { return }
        isSnapshotting = true
        Task { @MainActor in
            defer { isSnapshotting = false }
            do {
                guard let shot = try await ScreenGrabber.snapshot(screens: [screen], excludingWindowNumbers: [window.windowNumber]).first else { return }
                snapshot = shot.image
                captureWorked = true
                // The moment Tearsheet can see the screen, which after macOS reopens it is a later step.
                developed = true
                if step == .shortcut || step == .firstCapture {
                    // Once the print has mostly come up.
                    try? await Task.sleep(for: .milliseconds(reduced ? 300 : 1400))
                    if step == .shortcut || step == .firstCapture { playDemo() }
                }
            } catch {
                captureWorked = false
            }
        }
    }

    // MARK: ⇧⌘4

    func useShortcut() { SystemScreenshotShortcut.turnOff() }

    func keepMacOSShortcut() {
        record.keptMacOSShortcut = true
        advance()
    }

    private func shortcutTurnedOff() {
        withAnimation(Darkroom.Motion.entrance(0.2)) { macOSClaimsShortcut = SystemScreenshotShortcut.isEnabled }
        guard step == .shortcut, !macOSClaimsShortcut else { return }
        // Long enough to see the status change before the step does.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if step == .shortcut { advance() }
        }
    }

    // MARK: Demonstration

    /// Draws a selection across the stage, then lifts it into the thumbnail corner.
    /// Plays once; leaving the step, or a real capture, puts it straight at its end.
    private func playDemo() {
        guard demo == nil, demoCard == nil, captureCard == nil, let snapshot else { return }
        let size = stage.size
        let from = CGPoint(x: (size.width * 0.3).rounded(), y: (size.height * 0.26).rounded())
        let to = CGPoint(x: (size.width * 0.62).rounded(), y: (size.height * 0.6).rounded())
        let selection = CGRect(x: from.x, y: from.y, width: to.x - from.x, height: to.y - from.y)
        guard let card = card(cropping: snapshot, to: selection) else { return }

        if reduced {
            var landed = card
            landed.frame = stage.thumbnailFrame(pixelWidth: card.pixelWidth, height: card.pixelHeight, corner: corner)
            landed.opacity = 0
            demoCard = landed
            withAnimation(Darkroom.Motion.entrance(0.2)) { demoCard?.opacity = 1 }
            return
        }

        demo = SelectionDemo(from: from, to: to)
        demoTask = Task { @MainActor in
            withAnimation(Darkroom.Motion.entrance(0.2)) { demo?.dim = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(Darkroom.Motion.travel(0.9)) { demo?.progress = 1 }
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            // The selection becomes the card, then is thrown into the corner.
            demo?.showsSelection = false
            demoCard = card
            await Task.yield()
            withAnimation(Darkroom.Motion.Spring.settle.animation) {
                demoCard?.frame = stage.thumbnailFrame(pixelWidth: card.pixelWidth, height: card.pixelHeight, corner: corner)
                demoCard?.lifted = true
            }
            withAnimation(Darkroom.Motion.entrance(0.3)) { demo?.dim = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            demo = nil
        }
    }

    private func finishDemo() {
        guard demo != nil else { return }
        demoTask?.cancel()
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            demo = nil
            if demoCard == nil, captureCard == nil, let snapshot {
                let selection = CGRect(x: stage.size.width * 0.3, y: stage.size.height * 0.26, width: stage.size.width * 0.32, height: stage.size.height * 0.34)
                demoCard = card(cropping: snapshot, to: selection)
            }
            demoCard?.lifted = true
            placeCards()
        }
    }

    private func card(cropping image: CGImage, to selection: CGRect) -> StageCard? {
        let pixels = CGFloat(image.width) / stage.size.width
        let rect = CGRect(x: selection.minX * pixels, y: selection.minY * pixels, width: selection.width * pixels, height: selection.height * pixels).integral
        guard let crop = image.cropping(to: rect) else { return nil }
        return StageCard(image: NSImage(cgImage: crop, size: selection.size), pixelWidth: crop.width, pixelHeight: crop.height, frame: selection)
    }

    /// Pixels on the real display per stage point, for the size readout.
    var pixelsPerStagePoint: CGFloat { stage.backingScale / stage.scale }

    // MARK: First capture

    func captureNow() { captureRegion() }

    /// A real capture: the card flies from where it was selected into the corner.
    private func landed(_ capture: CaptureCoordinator.Capture) {
        finishDemo()
        captured = capture
        if step == .firstCapture || step == .shortcut { record.passedFirstCapture = true }
        let corner = stage.thumbnailFrame(pixelWidth: capture.image.width, height: capture.image.height, corner: self.corner)
        var start = corner
        if !reduced {
            if capture.displayID == stage.displayID {
                start = stage.map(capture.rect.offsetBy(dx: stage.frame.minX, dy: stage.frame.minY))
            } else {
                start = CGRect(x: stage.size.width / 2 - corner.width / 2, y: stage.size.height / 2 - corner.height / 2, width: corner.width, height: corner.height)
            }
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            captureCard = StageCard(
                image: NSImage(cgImage: capture.image, size: start.size),
                pixelWidth: capture.image.width, pixelHeight: capture.image.height,
                frame: start, opacity: reduced ? 0 : 1, lifted: true
            )
        }
        Task { @MainActor in
            await Task.yield()
            withAnimation(reduced ? nil : Darkroom.Motion.Spring.settle.animation) { captureCard?.frame = corner }
            withAnimation(Darkroom.Motion.entrance(0.2)) {
                captureCard?.opacity = 1
                demoCard?.opacity = 0
            }
        }
    }

    private func placeCards() {
        if let card = demoCard { demoCard?.frame = stage.thumbnailFrame(pixelWidth: card.pixelWidth, height: card.pixelHeight, corner: corner) }
        if let card = captureCard { captureCard?.frame = stage.thumbnailFrame(pixelWidth: card.pixelWidth, height: card.pixelHeight, corner: corner) }
    }

    // MARK: Wallpaper

    /// The desktop picture, small, for the stage before Tearsheet can see the screen.
    private static func wallpaper(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1200,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}

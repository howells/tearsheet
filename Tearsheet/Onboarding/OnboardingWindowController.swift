import AppKit
import SwiftUI
import TearsheetCore

/// The first run: one window, four steps, over a miniature desktop where each step plays out.
/// Closing it part way keeps what's done; the next launch, or Set Up Tearsheet…
/// in the menu, picks up at the first step not yet settled.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    var onFinish: (() -> Void)?
    private let capture: () -> Void
    private var window: NSWindow?
    private var model: OnboardingModel?

    init(capture: @escaping () -> Void) {
        self.capture = capture
    }

    func show() {
        if window == nil {
            let record = Preferences.onboarding ?? OnboardingRecord()
            let step = Onboarding.resumeStep(record, facts: .current) ?? .ready
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let model = OnboardingModel(step: step, record: record, screen: screen, capture: capture) { [weak self] in
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

/// The stage: the desktop from the film, an ocean with a photo open on it, laid out
/// as a 1440-point-wide display in roughly the shape of the screen the window opened on.
/// The scene is drawn in its own points and scaled; cards, the selection and the
/// menu are placed in stage points.
struct StageScene {
    /// Scene points.
    static let width: CGFloat = 1440
    static let menuBar: CGFloat = 24
    static let titleBar: CGFloat = 28
    static let photo = Bundle.main.image(forResource: "StageCoat")!
    static let wallpaper = Bundle.main.image(forResource: "StageOcean")!

    /// The real screen, for placing a real capture.
    let displayID: CGDirectDisplayID?
    let frame: CGRect
    let backingScale: CGFloat
    /// Stage points.
    let size: CGSize

    init(_ screen: NSScreen) {
        displayID = screen.displayID
        frame = screen.frame
        backingScale = screen.backingScaleFactor
        // The screen's shape, held between 16:9 and 16:10 so a portrait or ultrawide
        // display still leaves room for the shortcut menu on the last step.
        let aspect = min(max(frame.height / frame.width, 9.0 / 16), 10.0 / 16)
        size = CGSize(width: 488, height: (488 * aspect).rounded())
    }

    /// Stage points per scene point.
    var scale: CGFloat { size.width / Self.width }
    var height: CGFloat { size.height / scale }

    /// The photo's window, in scene points, where the film has it.
    var window: CGRect {
        let aspect = Self.photo.size.width / Self.photo.size.height
        let width = min(Self.width * 0.58, (height * 0.72 - Self.titleBar) * aspect)
        return CGRect(x: Self.width * 0.344, y: height * 0.155, width: width, height: width / aspect + Self.titleBar)
    }

    var photoFrame: CGRect {
        CGRect(x: window.minX, y: window.minY + Self.titleBar, width: window.width, height: window.height - Self.titleBar)
    }

    /// Tearsheet's icon in the menu bar, in scene points.
    static let glyph = CGRect(x: width - 186, y: 3, width: 18, height: 18)

    func onStage(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    /// Around the coat, in stage points, as the film draws it.
    var coatSelection: CGRect {
        let photo = photoFrame
        return onStage(CGRect(x: photo.minX + photo.width * 0.45, y: photo.minY + photo.height * 0.05, width: photo.width * 0.31, height: photo.height * 0.86)).integral
    }

    /// A rectangle on the real screen (bottom-left origin, relative to the display) at the same place on the stage.
    func map(displayRect rect: CGRect) -> CGRect {
        let x = rect.minX / frame.width, y = 1 - rect.maxY / frame.height
        return CGRect(x: x * size.width, y: y * size.height, width: rect.width / frame.width * size.width, height: rect.height / frame.height * size.height)
    }

    /// Where a thumbnail of this many pixels sits, alone, in `corner`; as `ThumbnailStack` puts it.
    func thumbnailFrame(pixelWidth: Int, height pixelHeight: Int, corner: ScreenCorner) -> CGRect {
        let card = ThumbnailPanel.size(forPixelWidth: pixelWidth, height: pixelHeight)
        let margin = ThumbnailStack.margin
        let area = CGRect(x: 0, y: Self.menuBar, width: Self.width, height: height - Self.menuBar).insetBy(dx: margin, dy: margin)
        let origin = CGPoint(x: corner.isLeft ? area.minX : area.maxX - card.width, y: corner.isBottom ? area.maxY - card.height : area.minY)
        return onStage(CGRect(origin: origin, size: card))
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
    private(set) var captureCheck = CaptureCheck(granted: ScreenRecordingPermission.isGranted)
    private(set) var hasAsked = false
    var recordingStatus: ScreenRecordingStatus { captureCheck.status }

    // Stage
    let stage: StageScene
    private(set) var developed = false
    private(set) var demo: SelectionDemo?
    private(set) var demoCard: StageCard?
    private(set) var captureCard: StageCard?
    private(set) var menuShown = false

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
    @ObservationIgnored private let finish: () -> Void
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var isSnapshotting = false
    /// Set once the window has closed, so work still in flight leaves the model alone.
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private var motionObserver: NSObjectProtocol?

    private var reduced: Bool { Darkroom.Motion.reduced }

    init(step: OnboardingStep, record: OnboardingRecord, screen: NSScreen, capture: @escaping () -> Void, finish: @escaping () -> Void) {
        self.step = step
        self.record = record
        self.screen = screen
        stage = StageScene(screen)
        captureRegion = capture
        self.finish = finish
        // A run that resumes at Ready gets the same login default as one that walks there,
        // before the toggle reads it.
        if step == .ready { LaunchAtLogin.configureOnFirstInstalledLaunch() }
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
        // Reduce Motion switched on mid-demonstration puts it straight at its end.
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if Darkroom.Motion.reduced { self?.finishDemo() } }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        enter(step)
    }

    func stop() {
        isStopped = true
        poll?.invalidate()
        poll = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        motionObserver = nil
        demoTask?.cancel()
    }

    /// Polls what macOS says now; the permission and the shortcut can change in System Settings.
    private func refresh() {
        guard !isStopped else { return }
        captureCheck.update(granted: ScreenRecordingPermission.isGranted)
        macOSClaimsShortcut = SystemScreenshotShortcut.isEnabled
        if captureCheck.shouldProbe { checkCapture() }
        returnToRecordingIfNeeded()
    }

    /// Nothing later works without capture, so a run that has lost it, or resumed past the
    /// step before it worked, goes back to the step that can put it right.
    private func returnToRecordingIfNeeded() {
        guard Onboarding.needsScreenRecordingStep(step, status: recordingStatus) else { return }
        finishDemo()
        withAnimation(Darkroom.Motion.entrance(reduced ? 0.2 : 0.3)) { step = .screenRecording }
    }

    // MARK: Steps

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        finishDemo()
        if step == .firstCapture { record.passedFirstCapture = true }
        if next == .ready { LaunchAtLogin.configureOnFirstInstalledLaunch() }
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
                guard !isStopped else { return }
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

    /// Captures the screen once, and shows nothing of it. If macOS says the permission is
    /// granted but a few attempts in a row capture nothing, Tearsheet needs reopening.
    private func checkCapture() {
        guard !isSnapshotting, let window else { return }
        isSnapshotting = true
        captureCheck.probeStarted()
        // The screen the window opened on may since have been unplugged.
        let screen = NSScreen.screens.contains(self.screen) ? self.screen : NSScreen.main ?? self.screen
        Task { @MainActor in
            defer { isSnapshotting = false }
            let shots = try? await ScreenGrabber.snapshot(screens: [screen], excludingWindowNumbers: [window.windowNumber])
            guard !isStopped else { return }
            // An empty result means nothing was captured, which is no proof.
            captureCheck.probe(succeeded: shots?.isEmpty == false)
            // Until the limit the next poll tries again; then the Reopen row stands.
            guard recordingStatus == .allowed else { return returnToRecordingIfNeeded() }
            // The stage develops the moment Tearsheet can capture, which after macOS
            // reopens it is a later step.
            developed = true
            if step == .shortcut || step == .firstCapture {
                // Once the print has mostly come up.
                try? await Task.sleep(for: .milliseconds(reduced ? 300 : 1400))
                if !isStopped, step == .shortcut || step == .firstCapture { playDemo() }
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
            if !isStopped, step == .shortcut { advance() }
        }
    }

    // MARK: Demonstration

    /// Draws a selection round the coat, then lifts it into the thumbnail corner, as the
    /// film does. Plays once; leaving the step, or a real capture, puts it straight at its end.
    private func playDemo() {
        guard developed, demo == nil, demoCard == nil, captureCard == nil, let card = coatCard() else { return }
        let selection = stage.coatSelection
        let from = selection.origin, to = CGPoint(x: selection.maxX, y: selection.maxY)

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
            if reduced { return finishDemo() }
            withAnimation(Darkroom.Motion.travel(0.9)) { demo?.progress = 1 }
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            if reduced { return finishDemo() }
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
            if demoCard == nil, captureCard == nil { demoCard = coatCard() }
            demoCard?.lifted = true
            placeCards()
        }
    }

    /// The coat, cut from the photo where the selection sits, as a card at the selection.
    private func coatCard() -> StageCard? {
        let selection = stage.coatSelection
        let photo = stage.onStage(stage.photoFrame)
        guard let image = StageScene.photo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixels = CGFloat(image.width) / photo.width
        let rect = CGRect(x: (selection.minX - photo.minX) * pixels, y: (selection.minY - photo.minY) * pixels, width: selection.width * pixels, height: selection.height * pixels).integral
        guard let crop = image.cropping(to: rect) else { return nil }
        return StageCard(image: NSImage(cgImage: crop, size: selection.size), pixelWidth: crop.width, pixelHeight: crop.height, frame: selection)
    }

    /// Pixels per stage point on a Retina display the size of the scene, for the size readout.
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
                start = stage.map(displayRect: capture.rect)
            } else {
                start = CGRect(x: stage.size.width / 2 - corner.width / 2, y: stage.size.height / 2 - corner.height / 2, width: corner.width, height: corner.height)
            }
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        let card = StageCard(
            image: NSImage(cgImage: capture.image, size: start.size),
            pixelWidth: capture.image.width, pixelHeight: capture.image.height,
            frame: start, opacity: reduced ? 0 : 1, lifted: true
        )
        withTransaction(instant) { captureCard = card }
        Task { @MainActor in
            await Task.yield()
            // A later capture, or a closed window, owns the stage now.
            guard !isStopped, captureCard?.id == card.id else { return }
            // Read the corner afresh: it may have changed while the card was placed.
            let destination = stage.thumbnailFrame(pixelWidth: card.pixelWidth, height: card.pixelHeight, corner: self.corner)
            withAnimation(reduced ? nil : Darkroom.Motion.Spring.settle.animation) { captureCard?.frame = destination }
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
}

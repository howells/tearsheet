import AppKit
import TearsheetCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeys = HotKeyCenter()
    private lazy var coordinator = CaptureCoordinator()
    private var statusMenu: StatusMenu?
    private let settings = SettingsWindowController()
    private lazy var onboarding = OnboardingWindowController(
        capture: { [coordinator] in Task { await coordinator.captureRegion(openEditor: false) } },
        iconFrame: { [weak self] in self?.statusMenu?.iconFrame }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        CaptureStore.removeStaleCaptures()

        statusMenu = StatusMenu(coordinator: coordinator) { [settings] in settings.show() }

        hotKeys.register(.captureRegion) { [coordinator] in Task { await coordinator.captureRegion(openEditor: false) } }
        hotKeys.register(.captureIntoEditor) { [coordinator] in Task { await coordinator.captureRegion(openEditor: true) } }
        hotKeys.register(.repeatLastRegion) { [coordinator] in Task { await coordinator.repeatLastRegion() } }
        hotKeys.register(.extractImages) { [coordinator] in Task { await coordinator.extractImages() } }
        NotificationCenter.default.addObserver(forName: SystemScreenshotShortcut.didTurnOff, object: nil, queue: .main) { [hotKeys] _ in
            MainActor.assumeIsolated { hotKeys.reinstall() }
        }

        // Tearsheet in use before the first run existed counts as set up.
        let record = Onboarding.record(stored: Preferences.onboarding, hasPriorUse: Preferences.didConfigureLaunchAtLogin || Preferences.lastRegion != nil)
        Preferences.onboarding = record
        if Onboarding.resumeStep(record, facts: .current) != nil {
            statusMenu?.openSetup = { [onboarding] in onboarding.show() }
            onboarding.onFinish = { [weak self] in self?.statusMenu?.openSetup = nil }
            onboarding.show()
        } else {
            LaunchAtLogin.configureOnFirstInstalledLaunch()
            if !ScreenRecordingPermission.isGranted { ScreenRecordingPermission.request() }
        }
    }
}

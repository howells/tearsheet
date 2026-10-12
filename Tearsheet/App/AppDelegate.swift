import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeys = HotKeyCenter()
    private lazy var coordinator = CaptureCoordinator()
    private var statusMenu: StatusMenu?
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        CaptureStore.removeStaleCaptures()
        LaunchAtLogin.configureOnFirstInstalledLaunch()

        statusMenu = StatusMenu(coordinator: coordinator) { [settings] in settings.show() }

        hotKeys.register(.captureRegion) { [coordinator] in Task { await coordinator.captureRegion(openEditor: false) } }
        hotKeys.register(.captureIntoEditor) { [coordinator] in Task { await coordinator.captureRegion(openEditor: true) } }
        hotKeys.register(.repeatLastRegion) { [coordinator] in Task { await coordinator.repeatLastRegion() } }
        hotKeys.register(.extractImages) { [coordinator] in Task { await coordinator.extractImages() } }
        NotificationCenter.default.addObserver(forName: SystemScreenshotShortcut.didTurnOff, object: nil, queue: .main) { [hotKeys] _ in
            MainActor.assumeIsolated { hotKeys.reinstall() }
        }

        if !ScreenRecordingPermission.isGranted { ScreenRecordingPermission.request() }
    }
}

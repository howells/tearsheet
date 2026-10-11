import AppKit
import TearsheetCore

/// The front tab of Safari or Chrome, reached through Apple Events.
///
/// Scripts go through `osascript -l JavaScript` with the page script as an
/// argument: nothing is spliced into AppleScript source, and the blocking call
/// runs off the main thread, which NSAppleScript does not allow.
struct BrowserTab: Sendable {
    nonisolated enum Browser: String, Sendable {
        case safari = "com.apple.Safari"
        case chrome = "com.google.Chrome"

        var name: String {
            switch self {
            case .safari: "Safari"
            case .chrome: "Chrome"
            }
        }

        /// Where the browser keeps its "Allow JavaScript from Apple Events" switch.
        var javaScriptSetting: String {
            switch self {
            case .safari: "In Safari, turn on Develop → Allow JavaScript from Apple Events. Show the Develop menu in Safari Settings → Advanced first if it’s hidden."
            case .chrome: "In Chrome, turn on View → Developer → Allow JavaScript from Apple Events."
            }
        }
    }

    nonisolated enum Failure: LocalizedError {
        case notAllowed(Browser)
        case consentNeeded(Browser)
        case javaScriptOff(Browser)
        case noWindow(Browser)
        case script(String)

        var errorDescription: String? {
            switch self {
            case let .notAllowed(browser): "Tearsheet isn’t allowed to control \(browser.name)"
            case let .consentNeeded(browser): "Tearsheet needs permission to read \(browser.name)"
            case let .javaScriptOff(browser): "\(browser.name) won’t run JavaScript from Tearsheet"
            case let .noWindow(browser): "No \(browser.name) window to read"
            case .script: "Couldn’t read the page"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .notAllowed: "Allow it in System Settings → Privacy & Security → Automation → Tearsheet."
            case .consentNeeded: "Press Esc, then ⌥⇧⌘I to allow it."
            case let .javaScriptOff(browser): browser.javaScriptSetting
            case .noWindow: nil
            case let .script(message): message
            }
        }
    }

    let browser: Browser
    let processIdentifier: pid_t

    init?(app: NSRunningApplication?) {
        guard let app, let id = app.bundleIdentifier, let browser = Browser(rawValue: id) else { return nil }
        self.browser = browser
        processIdentifier = app.processIdentifier
    }

    /// Safari or Chrome when its window is the topmost one under the pointer, even
    /// if another app (a chat, an editor) has keyboard focus.
    static func underPointer() -> BrowserTab? {
        guard let primary = NSScreen.screens.first else { return nil }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            return BrowserTab(app: NSRunningApplication(processIdentifier: pid))
        }
        return nil
    }

    /// The browser's front window in global points, origin top-left, as the window server has it.
    func frontWindowFrame() -> CGRect? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 100, frame.height > 100 else { continue }
            return frame
        }
        return nil
    }

    /// Asks macOS whether Tearsheet may send the browser Apple Events, showing the
    /// consent prompt the first time. Blocks until answered, so it runs off the main thread.
    func requestAutomationConsent() async {
        let bundleID = browser.rawValue
        _ = await Self.automationPermission(bundleID: bundleID, ask: true)
    }

    /// Fails early when consent was never given: on the Tab path the system prompt
    /// would open underneath the overlay, so the user is sent to ⌥⇧⌘I instead.
    func checkAutomationConsent() async throws {
        switch await Self.automationPermission(bundleID: browser.rawValue, ask: false) {
        case OSStatus(errAEEventWouldRequireUserConsent): throw Failure.consentNeeded(browser)
        case OSStatus(errAEEventNotPermitted): throw Failure.notAllowed(browser)
        default: break
        }
    }

    nonisolated private static func automationPermission(bundleID: String, ask: Bool) async -> OSStatus {
        await Task.detached {
            let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            return withExtendedLifetime(descriptor) {
                AEDeterminePermissionToAutomateTarget(descriptor.aeDesc!, typeWildCard, typeWildCard, ask)
            }
        }.value
    }

    func scan() async throws -> PageScan {
        let json = try await run(Self.pageScript)
        do {
            return try JSONDecoder().decode(PageScan.self, from: Data(json.utf8))
        } catch {
            throw Failure.script("The page returned something unexpected.")
        }
    }

    /// Runs `javaScript` in the front tab and returns its result as a string.
    func run(_ javaScript: String) async throws -> String {
        let browser = browser
        return try await Task.detached {
            try Self.osascript(browser: browser, javaScript: javaScript)
        }.value
    }

    private static let pageScript: String = {
        guard let url = Bundle.main.url(forResource: "PageScan", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return script
    }()

    /// JXA runner: argv[0] is the bundle identifier, argv[1] the page script.
    nonisolated private static let runner = """
    function run(argv) {
      const app = Application(argv[0]);
      if (app.windows.length === 0) throw new Error("TEARSHEET_NO_WINDOW");
      const window = app.windows[0];
      if (argv[0] === "com.apple.Safari") return app.doJavaScript(argv[1], { in: window.currentTab });
      return window.activeTab.execute({ javascript: argv[1] });
    }
    """

    nonisolated private static func osascript(browser: Browser, javaScript: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", runner, browser.rawValue, javaScript]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // Read before waiting, so a large result can't fill the pipe and stall the child.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
            if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authori") { throw Failure.notAllowed(browser) }
            if message.contains("TEARSHEET_NO_WINDOW") { throw Failure.noWindow(browser) }
            if message.localizedCaseInsensitiveContains("JavaScript from Apple Events")
                || message.localizedCaseInsensitiveContains("JavaScript through AppleScript") {
                throw Failure.javaScriptOff(browser)
            }
            throw Failure.script(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var result = String(decoding: data, as: UTF8.self)
        if result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}

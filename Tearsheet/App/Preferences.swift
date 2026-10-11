import Foundation
import TearsheetCore

enum Preferences {
    private static let defaults = UserDefaults.standard

    static var saveFolder: URL {
        get {
            defaults.string(forKey: "saveFolder").map { URL(filePath: $0, directoryHint: .isDirectory) }
                ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { defaults.set(newValue.path, forKey: "saveFolder") }
    }

    static var lastRegion: LastRegion? {
        get { defaults.data(forKey: "lastRegion").flatMap { try? JSONDecoder().decode(LastRegion.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "lastRegion") }
    }

    /// Launch at login is switched on once, on the first run from /Applications;
    /// after that the user's choice in Settings stands.
    static var didConfigureLaunchAtLogin: Bool {
        get { defaults.bool(forKey: "didConfigureLaunchAtLogin") }
        set { defaults.set(newValue, forKey: "didConfigureLaunchAtLogin") }
    }
}

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

    /// The screen corner the thumbnails gather in.
    static var thumbnailCorner: ScreenCorner {
        get { defaults.string(forKey: "thumbnailCorner").flatMap(ScreenCorner.init(rawValue:)) ?? .bottomLeft }
        set {
            defaults.set(newValue.rawValue, forKey: "thumbnailCorner")
            NotificationCenter.default.post(name: thumbnailCornerDidChange, object: nil)
        }
    }

    static let thumbnailCornerDidChange = Notification.Name("TearsheetThumbnailCornerDidChange")

    /// Launch at login is switched on once, on the first run from /Applications;
    /// after that the user's choice in Settings stands.
    static var didConfigureLaunchAtLogin: Bool {
        get { defaults.bool(forKey: "didConfigureLaunchAtLogin") }
        set { defaults.set(newValue, forKey: "didConfigureLaunchAtLogin") }
    }
}

enum ScreenCorner: String, CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight

    var title: String {
        switch self {
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        }
    }

    var isLeft: Bool { self == .bottomLeft || self == .topLeft }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
}

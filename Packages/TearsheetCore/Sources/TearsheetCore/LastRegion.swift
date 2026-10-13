import CoreGraphics

/// The most recent selection, kept so ⌥⇧⌘6 can capture it again.
public struct LastRegion: Codable, Equatable, Sendable {
    public var displayID: UInt32
    /// Point-space rectangle relative to the display's bottom-left corner.
    public var rect: CGRect

    public init(displayID: UInt32, rect: CGRect) {
        self.displayID = displayID
        self.rect = rect
    }
}

import AppKit
import TearsheetCore

enum Clipboard {
    static func copy(_ item: CaptureItem) {
        copy([item])
    }

    static func copy(_ items: [CaptureItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.pasteboardItem() })
    }
}

enum Saver {
    /// Writes the capture to the save folder. `atOneX` downsamples Retina captures to one pixel per point.
    /// An unannotated web image is written as its original file, format and name intact.
    @discardableResult
    static func save(_ item: CaptureItem, atOneX: Bool) throws -> URL {
        let folder = Preferences.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = CaptureFilename.uniqueURL(in: folder, name: item.filename) { FileManager.default.fileExists(atPath: $0.path) }
        if let original = item.originalFileData {
            try original.write(to: url)
            return url
        }
        let data = atOneX && item.scale > 1
            ? ImageCoding.png(ImageCoding.resized(item.image, by: 1 / item.scale), scale: 1)
            : item.pngData
        try data.write(to: url)
        return url
    }
}

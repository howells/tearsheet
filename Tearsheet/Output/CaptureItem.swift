import AppKit
import TearsheetCore

/// One capture from selection to dismissal. The thumbnail and the editor share
/// it; annotations stay editable on it until the thumbnail goes away.
final class CaptureItem {
    let id = UUID()
    let original: CGImage
    /// Pixels per point of the display the capture came from.
    let scale: CGFloat
    let createdAt = Date()

    private(set) var document = AnnotationDocument()
    private(set) var image: CGImage
    private(set) var pngData: Data
    /// A real file with the final name, for dragging and pasting into apps that want files.
    private(set) var fileURL: URL

    var onChange: (() -> Void)?
    /// Keeps the thumbnail on screen while an editor has the capture open.
    var isBeingEdited = false

    var filename: String { CaptureFilename.name(for: createdAt) }

    init(image: CGImage, scale: CGFloat) throws {
        original = image
        self.scale = scale
        self.image = image
        pngData = ImageCoding.png(image, scale: scale)
        fileURL = try CaptureStore.folder(for: id).appending(path: CaptureFilename.name(for: createdAt))
        try pngData.write(to: fileURL)
    }

    func apply(_ document: AnnotationDocument) throws {
        self.document = document
        image = AnnotationRenderer.render(base: original, document: document, scale: scale)
        pngData = ImageCoding.png(image, scale: scale)
        try pngData.write(to: fileURL)
        onChange?()
    }

    /// PNG bytes and the file URL on a single item, so apps choose whichever they understand.
    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setString(fileURL.absoluteString, forType: .fileURL)
        return item
    }
}

enum CaptureStore {
    private static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "com.howells.tearsheet/Captures", directoryHint: .isDirectory)
    }

    static func folder(for id: UUID) throws -> URL {
        let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Files are kept for a day so anything pasted as a file reference still resolves.
    static func removeStaleCaptures() {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for folder in folders {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fileManager.removeItem(at: folder) }
        }
    }
}

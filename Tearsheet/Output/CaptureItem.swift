import AppKit
import TearsheetCore

/// Where an image extracted from a web page came from.
struct WebOrigin {
    /// The original file's bytes; nil for a rendered copy.
    let data: Data?
    /// `hero@2x.webp`, or `hero (rendered copy).png`.
    let filename: String
    var isRenderedCopy: Bool { data == nil }
}

/// One capture from selection to dismissal. The thumbnail and the editor share
/// it; annotations stay editable on it until the thumbnail goes away.
final class CaptureItem {
    let id = UUID()
    let original: CGImage
    /// Pixels per point of the display the capture came from.
    let scale: CGFloat
    let createdAt = Date()
    let web: WebOrigin?

    private(set) var document = AnnotationDocument()
    private(set) var image: CGImage
    private(set) var pngData: Data
    /// A real file with the final name, for dragging and pasting into apps that want files.
    private(set) var fileURL: URL

    var onChange: (() -> Void)?
    /// Keeps the thumbnail on screen while an editor has the capture open.
    var isBeingEdited = false

    /// The name it saves under: the screenshot name, the web file's own name,
    /// or that name as a PNG once annotated.
    var filename: String {
        guard let web else { return CaptureFilename.name(for: createdAt) }
        guard isEdited, web.data != nil else { return web.filename }
        return (web.filename as NSString).deletingPathExtension + ".png"
    }

    var isEdited: Bool { !document.annotations.isEmpty || document.crop != nil }

    /// The web original's bytes while it is unannotated; Save writes these untouched.
    var originalFileData: Data? { isEdited ? nil : web?.data }

    init(image: CGImage, scale: CGFloat, web: WebOrigin? = nil) throws {
        original = image
        self.scale = scale
        self.web = web
        self.image = image
        pngData = ImageCoding.png(image, scale: scale)
        fileURL = try CaptureStore.folder(for: id).appending(path: web?.filename ?? CaptureFilename.name(for: createdAt))
        try (web?.data ?? pngData).write(to: fileURL)
    }

    func apply(_ document: AnnotationDocument) throws {
        self.document = document
        image = AnnotationRenderer.render(base: original, document: document, scale: scale)
        pngData = ImageCoding.png(image, scale: scale)
        let url = fileURL.deletingLastPathComponent().appending(path: filename)
        if url != fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = url
        try (originalFileData ?? pngData).write(to: fileURL)
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

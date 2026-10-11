import Foundation

public enum CaptureFilename {
    /// `Screenshot 2026-10-11 at 14.32.05.png`, matching macOS's own naming.
    public static func name(for date: Date, prefix: String = "Screenshot", fileExtension: String = "png", timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(fileExtension)"
    }

    /// The first of `name`, `name (2)`, `name (3)`… that does not exist in `folder`.
    public static func uniqueURL(in folder: URL, name: String, exists: (URL) -> Bool) -> URL {
        let candidate = folder.appending(path: name)
        guard exists(candidate) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while true {
            let numbered = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let url = folder.appending(path: numbered)
            if !exists(url) { return url }
            index += 1
        }
    }
}

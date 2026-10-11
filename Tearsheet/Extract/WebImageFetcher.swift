import AppKit
import TearsheetCore

/// An extracted image's original bytes, or nil when only a screenshot of it could be had.
struct FetchedImage: Sendable {
    let data: Data
    let mimeType: String?
    let filename: String
}

/// Gets the original file behind a page image, trying in order: the page's own
/// fetch (its cookies and origin), Tearsheet's download without cookies, and
/// finally giving up so the caller can fall back to a rendered copy.
struct WebImageFetcher: Sendable {
    let tab: BrowserTab
    let pageURL: URL?

    func fetch(_ image: PageImage) async -> FetchedImage? {
        switch image.source {
        case let .svg(markup):
            return FetchedImage(data: Data(markup.utf8), mimeType: "image/svg+xml", filename: "image.svg")
        case let .url(url):
            if url.scheme?.lowercased() == "data" { return Self.decodeDataURL(url) }
            if let fetched = try? await fetchInPage(url) { return fetched }
            if url.scheme?.lowercased() == "blob" { return nil }
            return try? await download(url)
        }
    }

    // MARK: In the page

    /// `do JavaScript` returns synchronously, so the page starts the fetch, parks
    /// the base64 result on `window`, and Tearsheet polls and reads it in chunks.
    private func fetchInPage(_ url: URL) async throws -> FetchedImage? {
        let id = "t" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let target = try Self.jsonString(url.absoluteString)
        let started = try await tab.run("""
        (() => {
          const store = window.__tearsheet || (window.__tearsheet = {});
          const slot = store.\(id) = { state: "pending" };
          fetch(\(target), { credentials: "include" })
            .then((response) => {
              if (!response.ok) throw new Error("HTTP " + response.status);
              slot.type = response.headers.get("content-type") || "";
              return response.blob();
            })
            .then((blob) => new Promise((resolve, reject) => {
              const reader = new FileReader();
              reader.onload = () => resolve(reader.result);
              reader.onerror = () => reject(reader.error);
              reader.readAsDataURL(blob);
            }))
            .then((dataURL) => {
              slot.data = dataURL.slice(dataURL.indexOf(",") + 1);
              slot.state = "done";
            })
            .catch((error) => { slot.state = "failed"; slot.error = String(error); });
          return "started";
        })()
        """)
        guard started == "started" else { return nil }
        defer { Task { _ = try? await tab.run("delete (window.__tearsheet || {}).\(id); 'ok'") } }

        struct Status: Decodable { let state: String; let type: String?; let length: Int? }
        var status: Status?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let json = try await tab.run("""
            (() => { const s = (window.__tearsheet || {}).\(id); return JSON.stringify(s ? { state: s.state, type: s.type, length: s.data ? s.data.length : 0 } : { state: "failed" }); })()
            """)
            status = try? JSONDecoder().decode(Status.self, from: Data(json.utf8))
            if status?.state != "pending" { break }
            try await Task.sleep(for: .milliseconds(150))
        }
        guard let status, status.state == "done", let length = status.length, length > 0 else { return nil }
        if let type = status.type, !type.isEmpty, !Self.isImageType(type) { return nil }

        var base64 = ""
        let chunk = 1_000_000
        var offset = 0
        while offset < length {
            base64 += try await tab.run("(window.__tearsheet || {}).\(id).data.substr(\(offset), \(chunk))")
            offset += chunk
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return FetchedImage(data: data, mimeType: status.type, filename: WebImageFilename.name(for: url, mimeType: status.type))
    }

    // MARK: Without cookies

    private func download(_ url: URL) async throws -> FetchedImage? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        // Hotlink protection often checks the referrer; send the page's, as the browser would.
        if let pageURL { request.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer") }
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
        let type = http.value(forHTTPHeaderField: "Content-Type")
        // A login page or error document served with 200 is not the image.
        if let type, !Self.isImageType(type) { return nil }
        return FetchedImage(data: data, mimeType: type, filename: WebImageFilename.name(for: url, mimeType: type))
    }

    // MARK: Helpers

    private static func decodeDataURL(_ url: URL) -> FetchedImage? {
        let string = url.absoluteString
        guard let comma = string.firstIndex(of: ",") else { return nil }
        let header = string[string.index(string.startIndex, offsetBy: 5)..<comma]
        let payload = String(string[string.index(after: comma)...])
        let mimeType = header.split(separator: ";").first.map(String.init)
        let data = header.hasSuffix(";base64")
            ? Data(base64Encoded: payload.removingPercentEncoding ?? payload)
            : payload.removingPercentEncoding.map { Data($0.utf8) }
        guard let data else { return nil }
        return FetchedImage(data: data, mimeType: mimeType, filename: WebImageFilename.name(for: url, mimeType: mimeType))
    }

    /// `image/*`, or a generic binary type some servers use for images.
    private static func isImageType(_ type: String) -> Bool {
        let lower = type.lowercased()
        return lower.hasPrefix("image/") || lower.hasPrefix("application/octet-stream") || lower.hasPrefix("binary/octet-stream")
    }

    private static func jsonString(_ value: String) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}

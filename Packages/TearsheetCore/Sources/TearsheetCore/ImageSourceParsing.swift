import Foundation

/// Reads image URLs out of the strings browsers hand back: computed
/// `background-image` values and `srcset` attributes.
public enum ImageSourceParsing {
    /// One URL per image layer of a computed `background-image`. Gradients and
    /// `none` are skipped; `image-set()` contributes its densest option.
    public static func backgroundURLs(_ value: String) -> [String] {
        splitTopLevel(value, on: ",").compactMap(layerURL)
    }

    /// The largest candidate in a `srcset`, by width descriptor, else by density.
    /// Bare URLs count as `1x`.
    public static func largestSource(inSrcset srcset: String) -> String? {
        let candidates = srcsetCandidates(srcset)
        if let widest = candidates.filter({ $0.width != nil }).max(by: { $0.width! < $1.width! }) {
            return widest.url
        }
        return candidates.max { $0.density < $1.density }?.url
    }

    /// The largest source an `<img>` could show: its own `srcset`, the matched
    /// `<source>` sets of a `<picture>`, then `currentSrc` and `src`.
    public static func bestImageSource(srcsets: [String], currentSrc: String?, src: String?) -> String? {
        let fromSets = srcsets.flatMap(srcsetCandidates)
        if let widest = fromSets.filter({ $0.width != nil }).max(by: { $0.width! < $1.width! }) {
            return widest.url
        }
        if let densest = fromSets.max(by: { $0.density < $1.density }), densest.density > 1 {
            return densest.url
        }
        return [currentSrc, src, fromSets.first?.url].compactMap { $0 }.first { !$0.isEmpty }
    }

    // MARK: Layers

    private static func layerURL(_ layer: String) -> String? {
        let layer = layer.trimmingCharacters(in: .whitespaces)
        let lower = layer.lowercased()
        if lower.hasPrefix("url(") {
            return unquote(String(layer.dropFirst(4).dropLast(layer.hasSuffix(")") ? 1 : 0)))
        }
        if lower.hasPrefix("image-set(") || lower.hasPrefix("-webkit-image-set(") {
            guard let open = layer.firstIndex(of: "("), layer.hasSuffix(")") else { return nil }
            let inner = String(layer[layer.index(after: open)..<layer.index(before: layer.endIndex)])
            return imageSetURL(inner)
        }
        return nil
    }

    /// `url("a.png") 1x, "b.png" 2x, url(c.avif) type("image/avif") 3dppx`
    private static func imageSetURL(_ inner: String) -> String? {
        var best: (url: String, density: Double)?
        for option in splitTopLevel(inner, on: ",") {
            let parts = splitTopLevel(option.trimmingCharacters(in: .whitespaces), on: " ").filter { !$0.isEmpty }
            guard let first = parts.first else { continue }
            let url: String? = first.lowercased().hasPrefix("url(")
                ? layerURL(first)
                : (first.hasPrefix("\"") || first.hasPrefix("'")) ? unquote(first) : nil
            guard let url, !url.isEmpty else { continue }
            let density = parts.dropFirst().compactMap(resolution).first ?? 1
            if best == nil || density > best!.density { best = (url, density) }
        }
        return best?.url
    }

    /// `2x`, `2dppx`, `192dpi`, `75.6dpcm` as dots per CSS pixel.
    private static func resolution(_ token: String) -> Double? {
        let lower = token.lowercased()
        for (unit, perDppx) in [("dppx", 1.0), ("dpcm", 96 / 2.54), ("dpi", 96.0), ("x", 1.0)] where lower.hasSuffix(unit) {
            return Double(lower.dropLast(unit.count)).map { $0 / perDppx }
        }
        return nil
    }

    // MARK: srcset

    private struct SrcsetCandidate {
        let url: String
        let width: Double?
        let density: Double
    }

    private static func srcsetCandidates(_ srcset: String) -> [SrcsetCandidate] {
        // URLs may contain commas (data: URLs, CDN transforms); a candidate ends at
        // a comma that follows whitespace-separated descriptors or the URL itself.
        var candidates: [SrcsetCandidate] = []
        var scanner = Substring(srcset)
        while true {
            scanner = scanner.drop { $0.isWhitespace || $0 == "," }
            guard !scanner.isEmpty else { break }
            let urlEnd = scanner.firstIndex(where: \.isWhitespace) ?? scanner.endIndex
            var url = String(scanner[..<urlEnd])
            scanner = scanner[urlEnd...]
            var descriptors = ""
            if url.hasSuffix(",") {
                url.removeLast()
            } else {
                let end = scanner.firstIndex(of: ",") ?? scanner.endIndex
                descriptors = String(scanner[..<end])
                scanner = scanner[end...]
            }
            var width: Double?
            var density = 1.0
            for token in descriptors.split(whereSeparator: \.isWhitespace) {
                if token.hasSuffix("w"), let value = Double(token.dropLast()) { width = value }
                if token.hasSuffix("x"), let value = Double(token.dropLast()) { density = value }
            }
            if !url.isEmpty { candidates.append(SrcsetCandidate(url: url, width: width, density: density)) }
        }
        return candidates
    }

    // MARK: Tokens

    /// Splits on `separator` outside parentheses and quotes.
    static func splitTopLevel(_ value: String, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in value {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if character == separator, depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "\"" || first == "'", trimmed.count >= 2, trimmed.last == first else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\(first)", with: String(first))
    }
}

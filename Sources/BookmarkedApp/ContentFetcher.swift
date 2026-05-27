import Foundation
import CryptoKit

struct FetchedContent {
    var title: String?
    var creator: String?
    var summary: String?
    var text: String
    var html: String?
}

enum ContentFetcher {
    static func fetch(url: URL) async throws -> FetchedContent {
        if url.isFileURL {
            return try fetchFile(url)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue("Bookmarked/0.1 (+macOS bookmark indexer)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""

        if mime.contains("text/html") || text.localizedCaseInsensitiveContains("<html") {
            let pageURL = response.url ?? url
            var content = HTMLContentExtractor.extract(from: text, url: pageURL)
            if let html = content.html {
                content.html = await ReaderImageCache.shared.localizingImages(in: html, pageURL: pageURL)
            }
            return content
        }

        if mime.contains("text/") || mime.contains("json") || mime.contains("xml") {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return FetchedContent(title: url.lastPathComponent, creator: url.host, summary: cleaned.prefixSummary, text: cleaned, html: nil)
        }

        return FetchedContent(title: url.lastPathComponent.isEmpty ? url.host : url.lastPathComponent, creator: url.host, summary: mime, text: url.absoluteString, html: nil)
    }

    private static func fetchFile(_ url: URL) throws -> FetchedContent {
        let kind = BookmarkClassifier.classify(url: url)
        if kind == .image || kind == .video || kind == .audio {
            return FetchedContent(title: url.lastPathComponent, creator: nil, summary: url.path, text: url.path, html: nil)
        }
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        return FetchedContent(title: url.lastPathComponent, creator: nil, summary: text.prefixSummary, text: text, html: nil)
    }
}

struct ReaderImageCache: Sendable {
    static let shared = ReaderImageCache()

    private let directory: URL
    private let fetchData: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    var readAccessDirectory: URL {
        directory.deletingLastPathComponent()
    }

    init(
        directory: URL = ReaderImageCache.defaultDirectory(),
        fetchData: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.directory = directory
        self.fetchData = fetchData
    }

    func localizingImages(in html: String, pageURL: URL) async -> String {
        let remoteURLs = Array(html.mediaResourceURLs(baseURL: pageURL).prefix(40))
        guard !remoteURLs.isEmpty else { return html }

        var localURLs: [URL: URL] = [:]
        await withTaskGroup(of: (URL, URL?).self) { group in
            for remoteURL in remoteURLs {
                group.addTask {
                    (remoteURL, await cacheImage(from: remoteURL))
                }
            }
            for await (remoteURL, localURL) in group {
                guard let localURL else { continue }
                localURLs[remoteURL] = localURL
            }
        }

        guard !localURLs.isEmpty else { return html }
        return html.replacingMediaResourceURLs(baseURL: pageURL, localURLs: localURLs)
    }

    func hasRemoteImages(in html: String, pageURL: URL) -> Bool {
        !html.mediaResourceURLs(baseURL: pageURL).isEmpty
    }

    private func cacheImage(from url: URL) async -> URL? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bookmarked/0.1 (+macOS bookmark image cache)", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/jpeg,image/gif,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await fetchData(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                return nil
            }

            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard contentType.contains("image/") || isLikelyImageURL(url) else { return nil }

            let fileURL = directory
                .appendingPathComponent(Self.cacheKey(for: url))
                .appendingPathExtension(Self.fileExtension(for: url, contentType: contentType))
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Bookmarked", isDirectory: true)
            .appendingPathComponent("ReaderImages", isDirectory: true)
    }

    private static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileExtension(for url: URL, contentType: String) -> String {
        switch contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/avif": return "avif"
        case "image/svg+xml": return "svg"
        default:
            let ext = url.pathExtension.lowercased()
            return ext.isEmpty ? "img" : ext
        }
    }

    private func isLikelyImageURL(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "avif", "svg"].contains(url.pathExtension.lowercased())
    }
}

enum HTMLContentExtractor {
    static func extract(from html: String, url: URL) -> FetchedContent {
        let contentHTML = primaryContentHTML(from: html)
        let readerHTML = contentHTML
            .removingMatches("<script[\\s\\S]*?</script>")
            .removingMatches("<style[\\s\\S]*?</style>")
            .removingMatches("<noscript[\\s\\S]*?</noscript>")
            .removingMatches("<!--([\\s\\S]*?)-->")
            .removingMatches("<nav[\\s\\S]*?</nav>")
            .removingMatches("<header[\\s\\S]*?</header>")
            .removingMatches("<footer[\\s\\S]*?</footer>")
            .removingMatches("<aside[\\s\\S]*?</aside>")
            .normalizedResourceURLs(baseURL: url)

        let withoutNoise = contentHTML
            .removingMatches("<script[\\s\\S]*?</script>")
            .removingMatches("<style[\\s\\S]*?</style>")
            .removingMatches("<noscript[\\s\\S]*?</noscript>")
            .removingMatches("<!--([\\s\\S]*?)-->")
            .removingMatches("<nav[\\s\\S]*?</nav>")
            .removingMatches("<header[\\s\\S]*?</header>")
            .removingMatches("<footer[\\s\\S]*?</footer>")
            .removingMatches("<aside[\\s\\S]*?</aside>")

        let title = metaValue("og:title", in: html)
            ?? metaValue("twitter:title", in: html)
            ?? firstCapture("<title[^>]*>([\\s\\S]*?)</title>", in: html)
        let description = metaValue("description", in: html)
            ?? metaValue("og:description", in: html)
            ?? metaValue("twitter:description", in: html)
        let creator = metaValue("author", in: html)
            ?? metaValue("article:author", in: html)
            ?? metaValue("og:site_name", in: html)
            ?? url.host

        let readable = withoutNoise
            .markdownStructuralText
            .removingMatches("<[^>]+>")
            .decodedHTMLEntities
            .normalizedWhitespace

        return FetchedContent(
            title: title?.decodedHTMLEntities.normalizedWhitespace,
            creator: creator?.decodedHTMLEntities.normalizedWhitespace,
            summary: description?.decodedHTMLEntities.normalizedWhitespace ?? readable.prefixSummary,
            text: readable,
            html: readerHTML
        )
    }

    private static func primaryContentHTML(from html: String) -> String {
        firstCapture("<article(?:\\s[^>]*)?>([\\s\\S]*?)</article>", in: html)
            ?? firstCapture("<main(?:\\s[^>]*)?>([\\s\\S]*?)</main>", in: html)
            ?? firstCapture("<body(?:\\s[^>]*)?>([\\s\\S]*?)</body>", in: html)
            ?? html
    }

    private static func metaValue(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "<meta[^>]+(?:name|property)=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:name|property)=[\"']\(escaped)[\"'][^>]*>"
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern, in: html) {
                return value
            }
        }
        return nil
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func removingMatches(_ pattern: String) -> String {
        replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
    }

    var markdownStructuralText: String {
        var value = self
        let replacements: [(String, String)] = [
            ("<h1[^>]*>", "\n\n# "),
            ("<h2[^>]*>", "\n\n## "),
            ("<h3[^>]*>", "\n\n### "),
            ("<h4[^>]*>", "\n\n#### "),
            ("<h5[^>]*>", "\n\n##### "),
            ("<h6[^>]*>", "\n\n###### "),
            ("</h[1-6]>", "\n\n"),
            ("<p[^>]*>", "\n\n"),
            ("</p>", "\n\n"),
            ("<li[^>]*>", "\n- "),
            ("</li>", "\n"),
            ("<br\\s*/?>", "\n"),
            ("</blockquote>", "\n\n"),
            ("<blockquote[^>]*>", "\n\n> "),
            ("</tr>", "\n"),
            ("</td>", " | "),
            ("</th>", " | ")
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return value
    }

    var normalizedWhitespace: String {
        replacingOccurrences(of: "\\s+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var prefixSummary: String {
        let normalized = normalizedWhitespace
        if normalized.count <= 260 { return normalized }
        return String(normalized.prefix(260)) + "..."
    }

    var decodedHTMLEntities: String {
        var value = self
        let replacements: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " ")
        ]
        for (needle, replacement) in replacements {
            value = value.replacingOccurrences(of: needle, with: replacement)
        }
        value = value.replacingNumericHTMLEntities()
        return value
    }

    func normalizedResourceURLs(baseURL: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(href|src|poster)=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else {
            return self
        }
        var result = self
        let matches = regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self))
        for match in matches.reversed() {
            guard let full = Range(match.range(at: 0), in: result),
                  let attrRange = Range(match.range(at: 1), in: self),
                  let valueRange = Range(match.range(at: 2), in: self) else {
                continue
            }
            let attr = String(self[attrRange])
            let rawValue = String(self[valueRange])
            if rawValue.hasPrefix("data:") || rawValue.hasPrefix("javascript:") || rawValue.hasPrefix("mailto:") || rawValue.hasPrefix("#") {
                continue
            }
            guard let absolute = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            result.replaceSubrange(full, with: "\(attr)=\"\(absolute.absoluteString)\"")
        }
        return result
    }

    func mediaResourceURLs(baseURL: URL) -> [URL] {
        var urls: [URL] = []
        for tag in mediaTags {
            urls.append(contentsOf: tag.mediaAttributeURLs(baseURL: baseURL))
            urls.append(contentsOf: tag.srcsetURLs(baseURL: baseURL))
        }
        var seen = Set<URL>()
        return urls.filter { url in
            guard !seen.contains(url) else { return false }
            seen.insert(url)
            return true
        }
    }

    func replacingMediaResourceURLs(baseURL: URL, localURLs: [URL: URL]) -> String {
        var result = self
        for match in mediaTagMatches.reversed() {
            guard let tagRange = Range(match.range, in: result),
                  let originalRange = Range(match.range, in: self) else {
                continue
            }
            let originalTag = String(self[originalRange])
            let rewritten = originalTag.replacingMediaReferences(baseURL: baseURL, localURLs: localURLs)
            result.replaceSubrange(tagRange, with: rewritten)
        }
        return result
    }

    private var mediaTags: [String] {
        mediaTagMatches.compactMap { match in
            guard let range = Range(match.range, in: self) else { return nil }
            return String(self[range])
        }
    }

    private var mediaTagMatches: [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: "<(?:img|source|video|amp-img)\\b[^>]*>", options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self))
    }

    private func mediaAttributeURLs(baseURL: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: "\\b(src|poster)=(\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self)).compactMap { match in
            let valueRange = match.range(at: 3).location != NSNotFound ? match.range(at: 3) : match.range(at: 4)
            guard let range = Range(valueRange, in: self) else { return nil }
            return Self.resolvedMediaURL(String(self[range]), baseURL: baseURL)
        }
    }

    private func srcsetURLs(baseURL: URL) -> [URL] {
        srcsetValues.flatMap { value in
            value.split(separator: ",").compactMap { candidate -> URL? in
                let raw = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let first = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { return nil }
                return Self.resolvedMediaURL(String(first), baseURL: baseURL)
            }
        }
    }

    private var srcsetValues: [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\bsrcset=(\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self)).compactMap { match in
            let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            guard let range = Range(valueRange, in: self) else { return nil }
            return String(self[range])
        }
    }

    private func replacingMediaReferences(baseURL: URL, localURLs: [URL: URL]) -> String {
        var result = replacingSrcsetReferences(baseURL: baseURL, localURLs: localURLs)
        guard let regex = try? NSRegularExpression(pattern: "\\b(src|poster)=(\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]) else {
            return result
        }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
        for match in matches.reversed() {
            let valueIndex = match.range(at: 3).location != NSNotFound ? 3 : 4
            guard let valueRange = Range(match.range(at: valueIndex), in: result) else { continue }
            let rawValue = String(result[valueRange])
            guard let remoteURL = Self.resolvedMediaURL(rawValue, baseURL: baseURL),
                  let localURL = localURLs[remoteURL] else {
                continue
            }
            result.replaceSubrange(valueRange, with: localURL.absoluteString)
        }
        return result
    }

    private func replacingSrcsetReferences(baseURL: URL, localURLs: [URL: URL]) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\bsrcset=(\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]) else {
            return self
        }
        var result = self
        let matches = regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self))
        for match in matches.reversed() {
            let valueIndex = match.range(at: 2).location != NSNotFound ? 2 : 3
            guard let valueRange = Range(match.range(at: valueIndex), in: result),
                  let originalValueRange = Range(match.range(at: valueIndex), in: self) else {
                continue
            }
            let rewritten = String(self[originalValueRange])
                .split(separator: ",")
                .map { candidate -> String in
                    let raw = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts = raw.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                    guard let first = parts.first,
                          let remoteURL = Self.resolvedMediaURL(String(first), baseURL: baseURL),
                          let localURL = localURLs[remoteURL] else {
                        return raw
                    }
                    if parts.count > 1 {
                        return "\(localURL.absoluteString) \(parts[1])"
                    }
                    return localURL.absoluteString
                }
                .joined(separator: ", ")
            result.replaceSubrange(valueRange, with: rewritten)
        }
        return result
    }

    private static func resolvedMediaURL(_ rawValue: String, baseURL: URL) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        guard !lowercased.hasPrefix("data:"),
              !lowercased.hasPrefix("javascript:"),
              !lowercased.hasPrefix("mailto:"),
              !lowercased.hasPrefix("#") else {
            return nil
        }
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        return url
    }

    private func replacingNumericHTMLEntities() -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") else {
            return self
        }
        var result = self
        let range = NSRange(startIndex..<endIndex, in: self)
        let matches = regex.matches(in: self, range: range)
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let captureRange = Range(match.range(at: 1), in: self) else {
                continue
            }
            let raw = String(self[captureRange])
            let radix = raw.hasPrefix("x") || raw.hasPrefix("X") ? 16 : 10
            let digits = radix == 16 ? String(raw.dropFirst()) : raw
            guard let code = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(code) else {
                continue
            }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}

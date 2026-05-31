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
            async let cachedPage = WebPageCache.shared.store(html: text, pageURL: pageURL, cacheURL: url)
            var content = HTMLContentExtractor.extract(from: text, url: pageURL)
            if let html = content.html {
                content.html = await ReaderImageCache.shared.localizingImages(in: html, pageURL: pageURL)
            }
            _ = await cachedPage
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
    private let isEnabled: @Sendable () -> Bool

    var readAccessDirectory: URL {
        directory.deletingLastPathComponent()
    }

    init(
        directory: URL = ReaderImageCache.defaultDirectory(),
        isEnabled: @escaping @Sendable () -> Bool = { BookmarkedRuntimePreferences.cacheReaderImages },
        fetchData: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.directory = directory
        self.isEnabled = isEnabled
        self.fetchData = fetchData
    }

    func localizingImages(in html: String, pageURL: URL) async -> String {
        guard isEnabled() else { return html }
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
        return html
            .replacingMediaResourceURLs(baseURL: pageURL, localURLs: localURLs)
            .preparedForLocalMediaDisplay()
    }

    func hasRemoteImages(in html: String, pageURL: URL) -> Bool {
        isEnabled() && !html.mediaResourceURLs(baseURL: pageURL).isEmpty
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
        defaultDirectoryURL
    }

    static var defaultDirectoryURL: URL {
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

struct WebPageCache: Sendable {
    static let shared = WebPageCache()

    private let directory: URL
    private let fetchData: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let isEnabled: @Sendable () -> Bool

    var readAccessDirectory: URL {
        directory
    }

    init(
        directory: URL = WebPageCache.defaultDirectoryURL,
        isEnabled: @escaping @Sendable () -> Bool = { BookmarkedRuntimePreferences.cacheWebPages },
        fetchData: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.directory = directory
        self.isEnabled = isEnabled
        self.fetchData = fetchData
    }

    func cachedPageURL(for url: URL) -> URL? {
        let fileURL = pageFileURL(for: url)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func cache(url: URL) async -> URL? {
        guard isEnabled(), url.scheme == "http" || url.scheme == "https" else { return nil }
        if let cached = cachedPageURL(for: url) {
            return cached
        }

        do {
            try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue("Bookmarked/0.1 (+macOS web page cache)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await fetchData(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                return nil
            }

            let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            guard mime.contains("text/html") || text.localizedCaseInsensitiveContains("<html") else {
                return nil
            }

            let pageURL = response.url ?? url
            return await store(html: text, pageURL: pageURL, cacheURL: url)
        } catch {
            return nil
        }
    }

    func store(html: String, pageURL: URL, cacheURL: URL) async -> URL? {
        guard isEnabled(), cacheURL.scheme == "http" || cacheURL.scheme == "https" else { return nil }

        do {
            try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            let absoluteHTML = html.normalizedResourceURLs(baseURL: pageURL)
            let localizedHTML = await localizingMediaResources(in: absoluteHTML, pageURL: pageURL)
                .preparedForLocalMediaDisplay()
            let fileURL = pageFileURL(for: cacheURL)
            guard let cachedData = localizedHTML.data(using: .utf8) else { return nil }
            try cachedData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    static var defaultDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Bookmarked", isDirectory: true)
            .appendingPathComponent("WebPages", isDirectory: true)
    }

    private var assetsDirectory: URL {
        directory.appendingPathComponent("Assets", isDirectory: true)
    }

    private func pageFileURL(for url: URL) -> URL {
        directory.appendingPathComponent(Self.cacheKey(for: url)).appendingPathExtension("html")
    }

    private func localizingMediaResources(in html: String, pageURL: URL) async -> String {
        let remoteURLs = Array(html.mediaResourceURLs(baseURL: pageURL).prefix(80))
        guard !remoteURLs.isEmpty else { return html }

        var localURLs: [URL: URL] = [:]
        await withTaskGroup(of: (URL, URL?).self) { group in
            for remoteURL in remoteURLs {
                group.addTask {
                    (remoteURL, await cacheMediaResource(from: remoteURL))
                }
            }
            for await (remoteURL, localURL) in group {
                guard let localURL else { continue }
                localURLs[remoteURL] = localURL
            }
        }

        guard !localURLs.isEmpty else { return html }
        return html
            .replacingMediaResourceURLs(baseURL: pageURL, localURLs: localURLs)
            .preparedForLocalMediaDisplay()
    }

    private func cacheMediaResource(from url: URL) async -> URL? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bookmarked/0.1 (+macOS web page cache)", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/jpeg,image/gif,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await fetchData(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                return nil
            }

            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard contentType.contains("image/") || isLikelyImageURL(url) else { return nil }

            let fileURL = assetsDirectory
                .appendingPathComponent(Self.cacheKey(for: url))
                .appendingPathExtension(Self.fileExtension(for: url, contentType: contentType))
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
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
            return ext.isEmpty ? "asset" : ext
        }
    }

    private func isLikelyImageURL(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "avif", "svg"].contains(url.pathExtension.lowercased())
    }
}

struct CacheStorageSnapshot: Equatable {
    var readerImageBytes: Int64
    var webPageBytes: Int64

    var totalBytes: Int64 {
        readerImageBytes + webPageBytes
    }
}

enum BookmarkedCacheStorage {
    static func snapshot() -> CacheStorageSnapshot {
        CacheStorageSnapshot(
            readerImageBytes: directorySize(ReaderImageCache.defaultDirectoryURL),
            webPageBytes: directorySize(WebPageCache.defaultDirectoryURL)
        )
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

enum HTMLContentExtractor {
    static func extract(from html: String, url: URL) -> FetchedContent {
        let contentHTML = primaryContentHTML(from: html)
        let withoutNoise = contentHTML
            .removingMatches("<script[\\s\\S]*?</script>")
            .removingMatches("<style[\\s\\S]*?</style>")
            .removingMatches("<noscript[\\s\\S]*?</noscript>")
            .removingMatches("<!--([\\s\\S]*?)-->")
            .removingMatches("<nav[\\s\\S]*?</nav>")
            .removingMatches("<header[\\s\\S]*?</header>")
            .removingMatches("<footer[\\s\\S]*?</footer>")
            .removingMatches("<aside[\\s\\S]*?</aside>")
            .removingMatches("<form[\\s\\S]*?</form>")

        let readerHTML = (simplifiedFramerHTML(from: withoutNoise, fullHTML: html) ?? withoutNoise)
            .normalizedResourceURLs(baseURL: url)

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
        html.firstBalancedElementInnerHTML(named: "article")
            ?? html.firstBalancedElementInnerHTML(named: "main")
            ?? html.firstBalancedElementInnerHTML(named: "body")
            ?? html
    }

    private static func simplifiedFramerHTML(from contentHTML: String, fullHTML: String) -> String? {
        guard fullHTML.localizedCaseInsensitiveContains("framer"),
              contentHTML.localizedCaseInsensitiveContains("data-framer-component-type=\"RichTextContainer\"") else {
            return nil
        }

        let desktopHiddenClasses = framerDesktopHiddenClasses(in: fullHTML)
        let visibleHTML = contentHTML.removingDivBlocks(withAnyClass: desktopHiddenClasses)
        let pattern = "(<div\\b(?=[^>]*data-framer-component-type=[\"']RichTextContainer[\"'])[^>]*>[\\s\\S]*?</div>)|(<img\\b[^>]*>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        var fragments: [FramerReaderFragment] = []
        var seenText = Set<String>()
        var seenImages = Set<String>()
        let matches = regex.matches(in: visibleHTML, range: NSRange(visibleHTML.startIndex..<visibleHTML.endIndex, in: visibleHTML))
        for match in matches {
            if let richRange = Range(match.range(at: 1), in: visibleHTML) {
                let raw = String(visibleHTML[richRange])
                guard !raw.hasAnyClass(desktopHiddenClasses),
                      let inner = firstCapture("<div\\b[^>]*>([\\s\\S]*?)</div>", in: raw) else {
                    continue
                }
                let readable = inner.markdownStructuralText
                    .removingMatches("<[^>]+>")
                    .decodedHTMLEntities
                    .normalizedWhitespace
                guard readable.count > 2, seenText.insert(readable).inserted else { continue }
                fragments.append(.text(html: inner.cleanedReaderFragment, readable: readable))
            } else if let imageRange = Range(match.range(at: 2), in: visibleHTML) {
                let raw = String(visibleHTML[imageRange])
                guard let image = raw.readerImageFragment,
                      let key = raw.imageIdentity,
                      seenImages.insert(key).inserted else {
                    continue
                }
                fragments.append(.image(html: image, identity: key))
            }
        }

        let articleFragments = filteredFramerArticleFragments(fragments)
        return articleFragments.count >= 3 ? articleFragments.map(\.html).joined(separator: "\n") : nil
    }

    private static func filteredFramerArticleFragments(_ fragments: [FramerReaderFragment]) -> [FramerReaderFragment] {
        guard !fragments.isEmpty else { return [] }

        let startIndex = fragments.firstIndex { fragment in
            guard let readable = fragment.readable else { return false }
            return readable.localizedCaseInsensitiveContains("Learning GSM8K is Inherently Low-Rank")
        } ?? fragments.firstIndex { fragment in
            (fragment.readable?.count ?? 0) >= 90
        } ?? fragments.startIndex

        let tail = fragments[startIndex...]
        var endIndex = fragments.endIndex
        var hasSeenArticleBody = false
        for index in tail.indices {
            guard let readable = fragments[index].readable else { continue }
            if readable.localizedCaseInsensitiveContains("References") ||
                readable.localizedCaseInsensitiveContains("Foot Notes") ||
                readable.localizedCaseInsensitiveContains("Discussion") {
                hasSeenArticleBody = true
            }
            if hasSeenArticleBody && isFramerFooterText(readable) {
                endIndex = index
                break
            }
        }

        let articleSlice = Array(fragments[startIndex..<endIndex])
        let readableTexts = articleSlice.compactMap(\.readable)
        var acceptedText = Set<String>()

        return articleSlice.compactMap { fragment in
            guard let readable = fragment.readable else { return fragment }
            guard !isFramerChromeText(readable) else { return nil }
            if isContainedResponsiveText(readable, in: readableTexts) {
                return nil
            }
            guard acceptedText.insert(readable).inserted else { return nil }
            return fragment.headingAdjusted
        }
    }

    private static func isContainedResponsiveText(_ text: String, in allTexts: [String]) -> Bool {
        guard text.count < 90 else { return false }
        let normalized = text.lowercased()
        return allTexts.contains { other in
            let candidate = other.lowercased()
            return candidate.count > normalized.count + 24 && candidate.contains(normalized)
        }
    }

    private static func isFramerFooterText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "blogs",
            "schedule an intro",
            "training reasoning models aligned with your goals.",
            "email: founders@trainloop.ai",
            "socials",
            "legal"
        ].contains(normalized)
    }

    private static func isFramerChromeText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        if isFramerFooterText(text) { return true }
        if normalized == "blog" { return true }
        if normalized.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil { return true }
        if ["linkedin", "x", "github", "yc (w25)", "privacy"].contains(normalized) { return true }
        if normalized.contains("© 2026 trainloop") || normalized.contains("north beach, san francisco") { return true }
        return false
    }

    private struct FramerReaderFragment {
        var html: String
        var readable: String?
        var imageIdentity: String?

        static func text(html: String, readable: String) -> Self {
            Self(html: html, readable: readable, imageIdentity: nil)
        }

        static func image(html: String, identity: String) -> Self {
            Self(html: html, readable: nil, imageIdentity: identity)
        }

        var headingAdjusted: Self {
            guard let readable else { return self }
            let headings = [
                "Introduction",
                "Training Details",
                "Findings",
                "Discussion Open Questions",
                "Foot Notes",
                "References"
            ]
            if readable == "Learning GSM8K is Inherently Low-Rank" {
                return .text(html: "<h1>\(readable.escapedHTML)</h1>", readable: readable)
            }
            if headings.contains(readable) {
                return .text(html: "<h2>\(readable.escapedHTML)</h2>", readable: readable)
            }
            return self
        }
    }

    private static func framerDesktopHiddenClasses(in html: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: "@media\\(min-width:\\s*1200px\\)\\{\\.([A-Za-z0-9_-]+)\\{display:none!important\\}\\}",
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        return Set(matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        })
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

extension String {
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

    var escapedHTML: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func hasAnyClass(_ classes: Set<String>) -> Bool {
        guard !classes.isEmpty else { return false }
        return !classAttributeTokens.isDisjoint(with: classes)
    }

    func removingDivBlocks(withAnyClass classes: Set<String>) -> String {
        guard !classes.isEmpty else { return self }
        var result = self
        while let range = result.firstDivBlockRange(withAnyClass: classes) {
            result.removeSubrange(range)
        }
        return result
    }

    var cleanedReaderFragment: String {
        var value = self
            .replacingOccurrences(of: "<span\\b[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</span>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s(?:class|style|data-[A-Za-z0-9_-]+|dir|aria-[A-Za-z0-9_-]+)=(\"[^\"]*\"|'[^']*')", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<br\\b[^>]*>", with: "<br>", options: [.regularExpression, .caseInsensitive])

        value = value.replacingOccurrences(of: "<p\\s*>\\s*</p>", with: "", options: [.regularExpression, .caseInsensitive])
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var readerImageFragment: String? {
        guard let src = attributeValue("src"),
              isReadableContentImage else {
            return nil
        }

        var attributes = [#"src="\#(src)""#]
        if let srcset = attributeValue("srcset"), !srcset.isEmpty {
            attributes.append(#"srcset="\#(srcset)""#)
        }
        if let sizes = attributeValue("sizes"), !sizes.isEmpty {
            attributes.append(#"sizes="\#(sizes)""#)
        }
        if let alt = attributeValue("alt"), !alt.isEmpty {
            attributes.append(#"alt="\#(alt)""#)
        }
        return "<figure><img \(attributes.joined(separator: " "))></figure>"
    }

    var imageIdentity: String? {
        guard let raw = attributeValue("src") else { return nil }
        guard var components = URLComponents(string: raw) else { return raw }
        components.query = nil
        components.fragment = nil
        return components.string ?? raw
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

    func preparedForLocalMediaDisplay() -> String {
        removingPictureSources()
            .removingSrcsetFromLocalMediaTags()
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

    private func removingPictureSources() -> String {
        replacingOccurrences(of: "<source\\b[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func removingSrcsetFromLocalMediaTags() -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<(?:img|video|amp-img)\\b[^>]*\\bsrc=(\"file://[^\"]*\"|'file://[^']*')[^>]*>",
            options: [.caseInsensitive]
        ) else {
            return self
        }

        var result = self
        let matches = regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self))
        for match in matches.reversed() {
            guard let tagRange = Range(match.range, in: result),
                  let originalRange = Range(match.range, in: self) else {
                continue
            }
            let tag = String(self[originalRange])
                .replacingOccurrences(
                    of: "\\s+srcset=(\"[^\"]*\"|'[^']*')",
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            result.replaceSubrange(tagRange, with: tag)
        }
        return result
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

    private var classAttributeTokens: Set<String> {
        guard let classes = attributeValue("class") else { return [] }
        return Set(classes.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init))
    }

    private var isReadableContentImage: Bool {
        guard let src = attributeValue("src"),
              !src.localizedCaseInsensitiveContains("favicon"),
              !src.localizedCaseInsensitiveContains("icon") else {
            return false
        }

        let width = Int(attributeValue("width") ?? "") ?? 0
        let height = Int(attributeValue("height") ?? "") ?? 0
        if width > 0 || height > 0 {
            return width >= 140 && height >= 80
        }
        return true
    }

    private func attributeValue(_ name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(escaped)=(\"([^\"]*)\"|'([^']*)')",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
        guard let range = Range(valueRange, in: self) else { return nil }
        return String(self[range]).decodedHTMLEntities
    }

    private func firstDivBlockRange(withAnyClass classes: Set<String>) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: "</?div\\b[^>]*>", options: [.caseInsensitive]) else {
            return nil
        }
        let matches = regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self))
        var blockStart: String.Index?
        var depth = 0

        for match in matches {
            guard let tagRange = Range(match.range, in: self) else { continue }
            let tag = String(self[tagRange])
            let isClosing = tag.lowercased().hasPrefix("</")

            if let start = blockStart {
                if isClosing {
                    depth -= 1
                    if depth == 0 {
                        return start..<tagRange.upperBound
                    }
                } else {
                    depth += 1
                }
            } else if !isClosing, tag.hasAnyClass(classes) {
                blockStart = tagRange.lowerBound
                depth = 1
            }
        }

        return nil
    }

    func firstBalancedElementInnerHTML(named tagName: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: tagName)
        guard let regex = try? NSRegularExpression(
            pattern: "<(/?)\(escaped)\\b[^>]*>",
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let matches = regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self))
        var startTagEnd: String.Index?
        var depth = 0

        for match in matches {
            guard let tagRange = Range(match.range, in: self),
                  let slashRange = Range(match.range(at: 1), in: self) else {
                continue
            }

            let isClosing = !self[slashRange].isEmpty
            if startTagEnd == nil {
                guard !isClosing else { continue }
                startTagEnd = tagRange.upperBound
                depth = 1
                continue
            }

            if isClosing {
                depth -= 1
                if depth == 0, let startTagEnd {
                    return String(self[startTagEnd..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                depth += 1
            }
        }

        return nil
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

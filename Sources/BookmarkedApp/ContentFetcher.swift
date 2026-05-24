import Foundation

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
            return HTMLContentExtractor.extract(from: text, url: url)
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

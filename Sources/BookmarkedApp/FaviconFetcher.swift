import AppKit
import Foundation

/// Decoded-favicon cache so list rows don't re-decode image bytes on every
/// render pass.
enum FaviconImageCache {
    private static let cache = NSCache<NSData, NSImage>()

    static func image(for data: Data) -> NSImage? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

enum FaviconFetcher {
    static func fetch(for url: URL) async -> Data? {
        guard let host = url.host, !host.isEmpty else { return nil }

        let candidates = await iconCandidates(for: url)

        for candidate in candidates {
            switch candidate {
            case .dataURI(let raw):
                guard let data = dataFromImageDataURI(raw), isRenderableImage(data) else { continue }
                return data
            case .remote(let iconURL):
                guard let data = await fetchRemoteImage(iconURL) else { continue }
                return data
            }
        }

        return nil
    }

    static func isRenderableImage(_ data: Data) -> Bool {
        guard let image = NSImage(data: data) else { return false }
        return image.size.width > 0 && image.size.height > 0
    }

    static func iconCandidates(in html: String, baseURL: URL) -> [IconCandidate] {
        guard let linkRegex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return linkRegex.matches(in: html, range: range).compactMap { match in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let tag = String(html[tagRange])
            let attributes = attributes(in: tag)
            guard let rel = attributes["rel"]?.lowercased(), rel.contains("icon") else { return nil }
            guard let href = attributes["href"]?.decodedHTMLAttribute, !href.isEmpty else { return nil }
            if href.lowercased().hasPrefix("data:image/") {
                return .dataURI(href)
            }
            guard let absolute = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }
            return .remote(absolute)
        }
    }

    private static func iconCandidates(for url: URL) async -> [IconCandidate] {
        guard let host = url.host, !host.isEmpty else { return [] }
        let scheme = url.scheme ?? "https"

        var candidates = customIconCandidates(for: host)
        candidates.append(contentsOf: await pageIconCandidates(for: url))
        candidates.append(contentsOf: [
            .remote(URL(string: "\(scheme)://\(host)/apple-touch-icon.png")!),
            .remote(URL(string: "\(scheme)://\(host)/favicon.ico")!),
            .remote(URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")!)
        ])

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.key
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func customCandidateURLs(for host: String) -> [String] {
        let normalized = host.lowercased()
        if normalized == "x.com" || normalized == "www.x.com" || normalized == "twitter.com" || normalized == "www.twitter.com" {
            return ["https://abs.twimg.com/favicons/twitter.ico"]
        }
        return []
    }

    private static func customIconCandidates(for host: String) -> [IconCandidate] {
        customCandidateURLs(for: host).compactMap { raw in
            URL(string: raw).map(IconCandidate.remote)
        }
    }

    private static func pageIconCandidates(for url: URL) async -> [IconCandidate] {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard type.contains("html") || type.isEmpty else { return [] }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
            return iconCandidates(in: html, baseURL: response.url ?? url)
        } catch {
            return []
        }
    }

    private static func fetchRemoteImage(_ url: URL) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                return nil
            }

            let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard !type.contains("text/html"), !data.starts(with: Data("<!DOCTYPE html".utf8)) else {
                return nil
            }

            return isRenderableImage(data) ? data : nil
        } catch {
            return nil
        }
    }

    private static func dataFromImageDataURI(_ raw: String) -> Data? {
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let metadata = raw[..<comma].lowercased()
        let payload = String(raw[raw.index(after: comma)...])
        if metadata.contains(";base64") {
            return Data(base64Encoded: payload)
        }
        return (payload.removingPercentEncoding ?? payload).data(using: .utf8)
    }

    private static func attributes(in tag: String) -> [String: String] {
        guard let attrRegex = try? NSRegularExpression(
            pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            options: []
        ) else {
            return [:]
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var values: [String: String] = [:]
        for match in attrRegex.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let valueRange = (2...4).compactMap { idx -> Range<String.Index>? in
                guard match.range(at: idx).location != NSNotFound else { return nil }
                return Range(match.range(at: idx), in: tag)
            }.first
            guard let valueRange else { continue }
            values[String(tag[nameRange]).lowercased()] = String(tag[valueRange])
        }
        return values
    }

    private static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
}

enum IconCandidate: Equatable {
    case remote(URL)
    case dataURI(String)

    var key: String {
        switch self {
        case .remote(let url): return url.absoluteString
        case .dataURI(let raw): return raw
        }
    }
}

private extension String {
    var decodedHTMLAttribute: String {
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
        return value
    }
}

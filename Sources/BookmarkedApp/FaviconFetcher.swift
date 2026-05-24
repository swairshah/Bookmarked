import Foundation

enum FaviconFetcher {
    static func fetch(for url: URL) async -> Data? {
        guard let host = url.host, !host.isEmpty else { return nil }

        let candidates = customCandidates(for: host) + [
            "https://www.google.com/s2/favicons?domain=\(host)&sz=64",
            "\(url.scheme ?? "https")://\(host)/favicon.ico",
            "\(url.scheme ?? "https")://\(host)/apple-touch-icon.png"
        ]

        for raw in candidates {
            guard let iconURL = URL(string: raw) else { continue }
            do {
                var request = URLRequest(url: iconURL)
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                    continue
                }
                return data
            } catch {
                continue
            }
        }

        return nil
    }

    private static func customCandidates(for host: String) -> [String] {
        let normalized = host.lowercased()
        if normalized == "x.com" || normalized == "www.x.com" || normalized == "twitter.com" || normalized == "www.twitter.com" {
            return ["https://abs.twimg.com/favicons/twitter.ico"]
        }
        return []
    }
}

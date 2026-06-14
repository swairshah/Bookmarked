import Foundation
import BookmarkedClient

enum BookmarkedDeepLink {
    private static let openActions = Set(["open", "bookmark", "item"])

    static func idOrPrefix(from url: URL) -> String? {
        guard url.scheme?.lowercased() == BookmarkedLinks.appScheme else { return nil }

        let host = url.host?.removingPercentEncoding
        let normalizedHost = host?.lowercased()
        let pathParts = url.pathComponents
            .filter { $0 != "/" }
            .compactMap { $0.removingPercentEncoding }

        if let normalizedHost, openActions.contains(normalizedHost) {
            return pathParts.first
        }

        if let first = pathParts.first?.lowercased(), openActions.contains(first) {
            return pathParts.dropFirst().first
        }

        if let host, !host.isEmpty {
            return host
        }

        return pathParts.first
    }
}

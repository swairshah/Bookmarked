import Foundation

/// 1:1 port of the macOS app's `BookmarkItem`. Field names, types, and the
/// JSON encoding (ISO-8601 dates, base64 `Data` for the favicon) are identical,
/// so this app decodes the exact `bookmarks.json` the Mac app writes.
struct BookmarkItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var kind: BookmarkKind
    var url: URL?
    var fileURL: URL?
    var creator: String?
    var sourceApp: String?
    var summary: String?
    var note: String?
    var contentText: String
    var readerHTML: String?
    var readerEditedAt: Date?
    var faviconData: Data?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        kind: BookmarkKind,
        url: URL? = nil,
        fileURL: URL? = nil,
        creator: String? = nil,
        sourceApp: String? = nil,
        summary: String? = nil,
        note: String? = nil,
        contentText: String = "",
        readerHTML: String? = nil,
        readerEditedAt: Date? = nil,
        faviconData: Data? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.url = url
        self.fileURL = fileURL
        self.creator = creator
        self.sourceApp = sourceApp
        self.summary = summary
        self.note = note
        self.contentText = contentText
        self.readerHTML = readerHTML
        self.readerEditedAt = readerEditedAt
        self.faviconData = faviconData
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
    }
}

extension BookmarkItem {
    /// True when there is a rich captured document to render in the WebView reader.
    var hasReaderHTML: Bool {
        guard let readerHTML else { return false }
        return !readerHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only web pages and repos are "openable in browser"; everything else stays in-app.
    var canOpenInBrowser: Bool {
        guard let url, url.scheme?.hasPrefix("http") == true else { return false }
        return kind == .webPage || kind == .githubRepo
    }

    var displaySubtitle: String {
        var parts = [kind.rawValue]
        if let creator, !creator.isEmpty { parts.append(creator) }
        return parts.joined(separator: " · ")
    }
}

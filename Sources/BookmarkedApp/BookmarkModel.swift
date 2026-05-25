import Foundation

enum BookmarkKind: String, Codable, CaseIterable, Identifiable {
    case webPage = "Web Page"
    case githubRepo = "GitHub Repo"
    case image = "Image"
    case video = "Video"
    case podcast = "Podcast"
    case audio = "Audio"
    case file = "File"
    case note = "Note"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .webPage: return "globe"
        case .githubRepo: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .podcast: return "dot.radiowaves.left.and.right"
        case .audio: return "waveform"
        case .file: return "doc"
        case .note: return "note.text"
        }
    }
}

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

struct BookmarkDraft {
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
    var faviconData: Data?
    var tags: [String]
}

enum BookmarkClassifier {
    static func classify(url: URL?) -> BookmarkKind {
        guard let url else { return .note }
        if url.isFileURL {
            return classifyFileExtension(url.pathExtension)
        }

        let host = (url.host ?? "").lowercased()
        let pathExtension = url.pathExtension.lowercased()
        let absolute = url.absoluteString.lowercased()

        if host == "github.com", url.pathComponents.count >= 3 {
            return .githubRepo
        }
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(pathExtension) {
            return .image
        }
        if ["mp4", "mov", "m4v", "webm"].contains(pathExtension) || host.contains("youtube.com") || host.contains("youtu.be") || host.contains("vimeo.com") {
            return .video
        }
        if ["mp3", "m4a", "wav", "aac", "flac", "ogg"].contains(pathExtension) {
            return .audio
        }
        if absolute.contains("podcast") || host.contains("overcast.fm") || host.contains("pocketcasts.com") || host.contains("podcasts.apple.com") || host.contains("spotify.com") {
            return .podcast
        }
        return .webPage
    }

    private static func classifyFileExtension(_ ext: String) -> BookmarkKind {
        let value = ext.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(value) { return .image }
        if ["mp4", "mov", "m4v", "webm"].contains(value) { return .video }
        if ["mp3", "m4a", "wav", "aac", "flac", "ogg"].contains(value) { return .audio }
        return .file
    }
}

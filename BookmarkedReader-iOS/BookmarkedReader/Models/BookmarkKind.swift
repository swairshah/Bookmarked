import SwiftUI

/// Mirrors `BookmarkKind` in the macOS app so the shared JSON decodes 1:1.
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

    /// Same accent mapping the macOS sidebar uses for the row glyph.
    var tint: Color {
        switch self {
        case .githubRepo: return .purple
        case .image: return .pink
        case .video: return .red
        case .podcast, .audio: return .blue
        case .file: return .green
        case .note: return .gray
        case .webPage: return .orange
        }
    }
}

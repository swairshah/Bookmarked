import Foundation
import Combine

/// Read-only store for the iOS reader.
///
/// It shares the macOS app's on-disk format (a JSON array of `BookmarkItem`,
/// ISO-8601 dates). It looks for that file in, in order:
///   1. an App Group container  — `Self.appGroupID` (the future iCloud / shared sync target)
///   2. the app's Documents dir — drop a `bookmarks.json` export here to test against real data
///   3. the bundled `sample-bookmarks.json` seed
///
/// When real sync is wired up later, point `bookmarksFileURL` at the synced
/// container and nothing else in the app has to change.
@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    /// Set this to your real App Group once provisioning is configured.
    /// Until then it stays nil and the store falls back to Documents / bundle.
    static let appGroupID: String? = nil
    static let fileName = "bookmarks.json"

    @Published private(set) var items: [BookmarkItem] = []
    @Published private(set) var sourceDescription: String = ""

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let icloud = ICloudBookmarkSync()
    private var usingICloud = false
    private var peer: PeerSync?

    private init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        load()
        startICloudSync()
        peer = PeerSync(store: self)
        peer?.start()
    }

    /// Apply records mirrored from the Mac over the local network: upsert by id
    /// (last-writer-wins by `updatedAt`), remove deleted ids, persist, and refresh.
    func applyPeerPush(upserts: [BookmarkItem], deletes: [UUID]) {
        guard !upserts.isEmpty || !deletes.isEmpty else { return }
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for incoming in upserts {
            if let existing = byID[incoming.id], existing.updatedAt > incoming.updatedAt { continue }
            byID[incoming.id] = incoming
        }
        for id in deletes { byID.removeValue(forKey: id) }
        items = byID.values.sorted { $0.createdAt > $1.createdAt }
        sourceDescription = "Local sync (\(items.count))"
        persistToDocuments()
    }

    /// Re-start local-network browsing after pairing/trust changes or a manual
    /// refresh so a trusted Mac can reconnect and push the latest diff.
    func restartPeerSync() { peer?.restart() }

    private func persistToDocuments() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent(Self.fileName)
        if let data = try? encoder.encode(items) { try? data.write(to: url, options: .atomic) }
    }

    /// Show bundled/local data instantly, then let iCloud take over once it has
    /// delivered at least one bookmark (so a not-yet-synced device still shows
    /// something rather than an empty list).
    private func startICloudSync() {
        icloud.onChange = { [weak self] synced in
            guard let self else { return }
            guard !synced.isEmpty else {
                if self.usingICloud { self.items = [] }   // honor deletions once iCloud is the source
                return
            }
            self.usingICloud = true
            self.items = synced
            self.sourceDescription = "iCloud (\(synced.count))"
        }
        icloud.start()
    }

    var recentItems: [BookmarkItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    func item(id: UUID?) -> BookmarkItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    /// Same token-AND search as the macOS store.
    func search(_ query: String) -> [BookmarkItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = recentItems
        guard !trimmed.isEmpty else { return source }
        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        return source.filter { item in
            let haystack = [
                item.title,
                item.kind.rawValue,
                item.creator ?? "",
                item.sourceApp ?? "",
                item.summary ?? "",
                item.note ?? "",
                item.url?.absoluteString ?? "",
                item.fileURL?.path ?? "",
                item.tags.joined(separator: " "),
                item.contentText
            ].joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    func reload() { load() }

    func refreshAndReconnect() {
        load()
        restartPeerSync()
    }

    // MARK: - Loading

    private func load() {
        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate.url) else { continue }
            do {
                items = try decoder.decode([BookmarkItem].self, from: data)
                sourceDescription = candidate.label
                return
            } catch {
                // Try the next source rather than crashing on a malformed file.
                continue
            }
        }
        items = []
        sourceDescription = "No library found"
    }

    private func candidateURLs() -> [(url: URL, label: String)] {
        var result: [(URL, String)] = []

        if let groupID = Self.appGroupID,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            result.append((container.appendingPathComponent(Self.fileName), "Shared container"))
        }

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            result.append((docs.appendingPathComponent(Self.fileName), "Documents"))
        }

        // A real library snapshot bundled at build time (release.sh copies it in).
        if let bundledReal = Bundle.main.url(forResource: "bookmarks", withExtension: "json") {
            result.append((bundledReal, "Bundled library"))
        }

        if let bundled = Bundle.main.url(forResource: "sample-bookmarks", withExtension: "json") {
            result.append((bundled, "Bundled sample"))
        }

        return result
    }
}

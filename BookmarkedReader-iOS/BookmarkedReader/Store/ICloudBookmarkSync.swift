import Foundation

/// Live, incremental sync via iCloud Drive: one `<uuid>.json` file per bookmark
/// in the shared container's `Documents/Bookmarks/` folder. Only changed files
/// move over the wire — adding one article syncs one small file, not the whole
/// library. The macOS app writes these files; this watches them with
/// `NSMetadataQuery` and decodes whatever is present.
final class ICloudBookmarkSync {
    static let containerID = "iCloud.com.swairshah.Bookmarked"
    static let folderName = "Bookmarks"

    /// Called on the main thread whenever the synced set changes.
    ///
    /// Delivers a *diff*, not a snapshot: `upserts` are the bookmarks whose files
    /// are currently downloaded and decodable, and `knownIDs` is every bookmark id
    /// present in the container (derived from the `<uuid>.json` filenames, so it
    /// includes files that haven't finished downloading yet). The store upserts the
    /// former and treats anything missing from the latter as deleted — this avoids
    /// dropping items whose files simply haven't landed in this round of updates.
    var onChange: ((_ upserts: [BookmarkItem], _ knownIDs: Set<UUID>) -> Void)?

    private var query: NSMetadataQuery?
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// True only if the device has an iCloud account and the container resolves.
    var isAvailable: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID) != nil
    }

    func start() {
        // Resolving the ubiquity container is blocking — do it off the main thread,
        // then start the query back on the main run loop.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID) else {
                return
            }
            let dir = container.appendingPathComponent("Documents/\(Self.folderName)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            DispatchQueue.main.async { self.startQuery() }
        }
    }

    private func startQuery() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*.json")
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(queryUpdated(_:)),
                           name: .NSMetadataQueryDidFinishGathering, object: q)
        center.addObserver(self, selector: #selector(queryUpdated(_:)),
                           name: .NSMetadataQueryDidUpdate, object: q)
        query = q
        q.start()
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        var readyURLs: [URL] = []
        var knownIDs = Set<UUID>()
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.path.contains("/Documents/\(Self.folderName)/") else { continue }

            // The filename is `<uuid>.json`, so every file present in the container —
            // downloaded or not — contributes its id to the known set. A file still
            // downloading therefore never looks like a deletion.
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                knownIDs.insert(id)
            }

            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                readyURLs.append(url)
            } else {
                // Not downloaded yet — request it; the query fires again when it lands.
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }

        let decoder = self.decoder
        DispatchQueue.global(qos: .userInitiated).async {
            var items: [BookmarkItem] = []
            for url in readyURLs {
                guard let data = try? Data(contentsOf: url),
                      let bookmark = try? decoder.decode(BookmarkItem.self, from: data) else { continue }
                items.append(bookmark)
            }
            DispatchQueue.main.async { self.onChange?(items, knownIDs) }
        }
    }

    deinit {
        query?.stop()
        NotificationCenter.default.removeObserver(self)
    }
}

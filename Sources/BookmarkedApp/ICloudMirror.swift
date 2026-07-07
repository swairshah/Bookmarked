import Foundation

/// Mirrors the library into the shared iCloud container as one `<uuid>.json`
/// file per bookmark, so the iOS reader (and any other device) syncs only the
/// items that actually changed — not the whole JSON blob.
///
/// Bookmarked is a non-sandboxed menu-bar app (it needs Accessibility / Apple
/// Events for capture), so the entitled `url(forUbiquityContainerIdentifier:)`
/// may be unavailable. We try it first, then fall back to writing directly into
/// the container's on-disk location under ~/Library/Mobile Documents, which a
/// non-sandboxed app can do and iCloud still syncs.
enum ICloudMirror {
    static let containerID = "iCloud.com.swairshah.Bookmarked"
    static let folderName = "Bookmarks"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // sortedKeys keeps output deterministic for the byte-compare below;
        // compact (no prettyPrinted) keeps per-item encodes cheap.
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let ioQueue = DispatchQueue(label: "bookmarked.icloud.mirror", qos: .utility)

    /// Resolve the `Documents/Bookmarks` directory inside the iCloud container.
    private static func bookmarksDirectory() -> URL? {
        let base: URL?
        if let entitled = FileManager.default.url(forUbiquityContainerIdentifier: containerID) {
            base = entitled
        } else {
            // On-disk container path, e.g. iCloud.com.swairshah.Bookmarked ->
            // ~/Library/Mobile Documents/iCloud~com~swairshah~Bookmarked
            let onDiskName = containerID.replacingOccurrences(of: ".", with: "~")
            let candidate = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/\(onDiskName)", isDirectory: true)
            base = FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
        guard let base else { return nil }
        let dir = base.appendingPathComponent("Documents/\(folderName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write/update changed bookmarks and remove files for deleted ones.
    static func sync(_ items: [BookmarkItem]) {
        ioQueue.async {
            guard let dir = bookmarksDirectory() else {
                NSLog("Bookmarked iCloud: container folder not found — skipping mirror")
                return
            }
            let fm = FileManager.default
            var written = 0
            var writeFailure: Error?

            var wanted = Set<String>()
            for item in items {
                let name = "\(item.id.uuidString).json"
                wanted.insert(name)
                let url = dir.appendingPathComponent(name)
                guard let data = try? encoder.encode(item) else { continue }
                // Only write when the contents actually changed, to avoid
                // needless iCloud churn on every save.
                let existing = try? Data(contentsOf: url)
                if existing != data {
                    do {
                        try data.write(to: url, options: .atomic)
                        written += 1
                    } catch {
                        writeFailure = error
                    }
                }
            }
            if let writeFailure {
                // Surface silent mirror failures (e.g. TCC denying writes into
                // ~/Library/Mobile Documents) instead of pretending we synced.
                NSLog("Bookmarked iCloud: mirror writes failing: \(writeFailure)")
            }

            var removed = 0
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "json" && !wanted.contains(file.lastPathComponent) {
                    try? fm.removeItem(at: file)
                    removed += 1
                }
            }
            NSLog("Bookmarked iCloud: mirrored \(items.count) bookmarks (wrote \(written), removed \(removed)) -> \(dir.path)")
        }
    }
}

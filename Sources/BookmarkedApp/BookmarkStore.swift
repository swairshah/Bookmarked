import Foundation
import Combine
import AppKit

@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published private(set) var items: [BookmarkItem] = []
    @Published private(set) var isCapturing = false
    @Published private(set) var flashToken = 0
    @Published var statusMessage: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let ioQueue = DispatchQueue(label: "bookmarked.store.io", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Bookmarked", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bookmarks.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    var recentItems: [BookmarkItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    func item(id: UUID?) -> BookmarkItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

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
                item.url?.absoluteString ?? "",
                item.fileURL?.path ?? "",
                item.tags.joined(separator: " "),
                item.contentText,
                Self.searchDateFormatter.string(from: item.createdAt)
            ].joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    @discardableResult
    func add(_ draft: BookmarkDraft) -> BookmarkItem {
        let item = BookmarkItem(
            title: draft.title.isEmpty ? "Untitled Bookmark" : draft.title,
            kind: draft.kind,
            url: draft.url,
            fileURL: draft.fileURL,
            creator: draft.creator,
            sourceApp: draft.sourceApp,
            summary: draft.summary,
            contentText: draft.contentText,
            readerHTML: draft.readerHTML,
            faviconData: draft.faviconData,
            tags: Array(Set(draft.tags)).sorted()
        )
        items.insert(item, at: 0)
        scheduleSave()
        statusMessage = "Saved \(item.kind.rawValue.lowercased())"
        flashToken += 1
        return item
    }

    func addURLString(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url: URL?
        if let direct = URL(string: trimmed), direct.scheme != nil {
            url = direct
        } else {
            url = URL(string: "https://\(trimmed)")
        }

        guard let url else {
            statusMessage = "Could not read URL"
            return
        }

        Task {
            await capture(url: url, titleHint: url.host ?? trimmed, sourceApp: "Manual")
        }
    }

    func open(_ item: BookmarkItem) {
        let destination = item.url ?? item.fileURL
        guard let destination else { return }
        NSWorkspace.shared.open(destination)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].lastOpenedAt = Date()
            items[idx].updatedAt = Date()
            scheduleSave()
        }
    }

    func delete(_ item: BookmarkItem) {
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }

    func refresh(_ item: BookmarkItem) {
        guard let url = item.url else { return }
        Task {
            await capture(url: url, titleHint: item.title, sourceApp: item.sourceApp, replacing: item.id)
        }
    }

    func ensureAssets(for item: BookmarkItem) {
        let hasValidFavicon = item.faviconData.map(FaviconFetcher.isRenderableImage) ?? false
        if !hasValidFavicon, let url = item.url {
            Task {
                guard let data = await FaviconFetcher.fetch(for: url) else { return }
                await MainActor.run {
                    guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                    self.items[idx].faviconData = data
                    self.items[idx].updatedAt = Date()
                    self.scheduleSave()
                }
            }
        }

        if item.readerHTML == nil, item.url != nil, (item.kind == .webPage || item.kind == .githubRepo) {
            refresh(item)
        }
    }

    func captureFrontmostContext(openWindowAfterCapture: Bool = false) {
        guard !isCapturing else { return }
        isCapturing = true
        statusMessage = "Capturing current page..."
        Task {
            defer { Task { @MainActor in self.isCapturing = false } }
            do {
                let context = try CaptureService.currentContext()
                await capture(url: context.url, titleHint: context.title, sourceApp: context.browser)
                if openWindowAfterCapture {
                    await MainActor.run {
                        MainWindowController.shared.show()
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    if openWindowAfterCapture {
                        MainWindowController.shared.show()
                    }
                }
            }
        }
    }

    private func capture(url: URL, titleHint: String, sourceApp: String?, replacing id: UUID? = nil) async {
        do {
            async let fetchedContent = ContentFetcher.fetch(url: url)
            async let fetchedFavicon = FaviconFetcher.fetch(for: url)
            let fetched = try await fetchedContent
            let favicon = await fetchedFavicon
            let kind = BookmarkClassifier.classify(url: url)
            let title = fetched.title?.isEmpty == false ? fetched.title! : titleHint
            let draft = BookmarkDraft(
                title: title,
                kind: kind,
                url: url,
                fileURL: nil,
                creator: fetched.creator,
                sourceApp: sourceApp,
                summary: fetched.summary,
                contentText: fetched.text,
                readerHTML: fetched.html,
                faviconData: favicon,
                tags: inferredTags(for: url, kind: kind)
            )
            if let id, let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].title = draft.title
                items[idx].kind = draft.kind
                items[idx].creator = draft.creator
                items[idx].summary = draft.summary
                items[idx].contentText = draft.contentText
                items[idx].readerHTML = draft.readerHTML
                items[idx].faviconData = draft.faviconData ?? items[idx].faviconData
                items[idx].tags = draft.tags
                items[idx].updatedAt = Date()
                scheduleSave()
                statusMessage = "Refreshed bookmark"
            } else {
                _ = add(draft)
            }
        } catch {
            let kind = BookmarkClassifier.classify(url: url)
            _ = add(BookmarkDraft(
                title: titleHint.isEmpty ? (url.host ?? url.absoluteString) : titleHint,
                kind: kind,
                url: url,
                fileURL: nil,
                creator: nil,
                sourceApp: sourceApp,
                summary: "Saved URL. Content indexing failed: \(error.localizedDescription)",
                contentText: url.absoluteString,
                readerHTML: nil,
                faviconData: await FaviconFetcher.fetch(for: url),
                tags: inferredTags(for: url, kind: kind)
            ))
        }
    }

    private func inferredTags(for url: URL, kind: BookmarkKind) -> [String] {
        var tags = [kind.rawValue.lowercased()]
        if let host = url.host?.replacingOccurrences(of: "www.", with: "") {
            tags.append(host)
        }
        return tags
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try decoder.decode([BookmarkItem].self, from: data)
        } catch {
            NSLog("Bookmarked: failed to read bookmarks.json: \(error)")
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = items
        let url = fileURL
        let encoder = encoder
        let work = DispatchWorkItem {
            do {
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Bookmarked: failed to save bookmarks.json: \(error)")
            }
        }
        saveWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private static let searchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

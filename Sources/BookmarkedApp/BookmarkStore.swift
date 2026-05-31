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
    private var imageLocalizationTasks = Set<UUID>()
    private var webPageCacheTasks = Set<UUID>()

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
                item.note ?? "",
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
            note: draft.note,
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

    func resolveItem(idOrPrefix: String) -> BookmarkItem? {
        let normalized = idOrPrefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if let uuid = UUID(uuidString: normalized) {
            return item(id: uuid)
        }
        return items.first { $0.id.uuidString.lowercased().hasPrefix(normalized) }
    }

    @discardableResult
    func appendNote(id: UUID, text: String) -> BookmarkItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items[idx] }
        if let existing = items[idx].note, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items[idx].note = existing + "\n\n" + trimmed
        } else {
            items[idx].note = trimmed
        }
        items[idx].updatedAt = Date()
        scheduleSave()
        return items[idx]
    }

    @discardableResult
    func setNote(id: UUID, text: String) -> BookmarkItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        let newNote: String? = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        guard newNote != items[idx].note else { return items[idx] }
        items[idx].note = newNote
        items[idx].updatedAt = Date()
        scheduleSave()
        statusMessage = "Saved notes"
        return items[idx]
    }

    @discardableResult
    func setTags(id: UUID, tags: [String]) -> BookmarkItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        items[idx].tags = Self.normalizedTags(tags)
        items[idx].updatedAt = Date()
        scheduleSave()
        return items[idx]
    }

    @discardableResult
    func addTag(id: UUID, tag: String) -> BookmarkItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        items[idx].tags = Self.normalizedTags(items[idx].tags + [tag])
        items[idx].updatedAt = Date()
        scheduleSave()
        return items[idx]
    }

    @discardableResult
    func removeTag(id: UUID, tag: String) -> BookmarkItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        let normalized = Self.normalizedTag(tag)
        items[idx].tags = items[idx].tags.filter { Self.normalizedTag($0) != normalized }
        items[idx].updatedAt = Date()
        scheduleSave()
        return items[idx]
    }

    func refresh(_ item: BookmarkItem) {
        guard let url = item.url else { return }
        Task {
            await capture(url: url, titleHint: item.title, sourceApp: item.sourceApp, replacing: item.id)
        }
    }

    func saveReaderEdits(for itemID: UUID, text: String, isHTML: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isHTML {
            let fallbackURL = URL(string: "https://bookmarked.local")!
            let extracted = HTMLContentExtractor.extract(from: cleaned, url: items[idx].url ?? fallbackURL)
            items[idx].contentText = extracted.text
            items[idx].readerHTML = cleaned
        } else {
            items[idx].contentText = cleaned
            items[idx].readerHTML = nil
        }
        items[idx].readerEditedAt = Date()
        items[idx].updatedAt = Date()
        scheduleSave()
        statusMessage = "Saved reader edits"
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

        if item.readerHTML == nil, item.readerEditedAt == nil, item.url != nil, (item.kind == .webPage || item.kind == .githubRepo) {
            refresh(item)
        }

        if let url = item.url,
           let html = item.readerHTML,
           ReaderImageCache.shared.hasRemoteImages(in: html, pageURL: url) {
            localizeReaderImages(for: item.id, html: html, pageURL: url)
        }

        if BookmarkedRuntimePreferences.cacheWebPages,
           let url = item.url,
           item.kind == .webPage || item.kind == .githubRepo {
            cacheWebPage(for: item.id, url: url)
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
                note: nil,
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
                items[idx].readerEditedAt = nil
                items[idx].faviconData = draft.faviconData ?? items[idx].faviconData
                items[idx].tags = draft.tags
                items[idx].updatedAt = Date()
                scheduleSave()
                statusMessage = "Refreshed bookmark"
                cacheWebPage(for: id, url: url)
            } else {
                let item = add(draft)
                cacheWebPage(for: item.id, url: url)
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
                note: nil,
                contentText: url.absoluteString,
                readerHTML: nil,
                faviconData: await FaviconFetcher.fetch(for: url),
                tags: inferredTags(for: url, kind: kind)
            ))
        }
    }

    private func localizeReaderImages(for itemID: UUID, html: String, pageURL: URL) {
        guard !imageLocalizationTasks.contains(itemID) else { return }
        imageLocalizationTasks.insert(itemID)
        Task {
            let localizedHTML = await ReaderImageCache.shared.localizingImages(in: html, pageURL: pageURL)
            await MainActor.run {
                self.imageLocalizationTasks.remove(itemID)
                guard localizedHTML != html,
                      let idx = self.items.firstIndex(where: { $0.id == itemID }),
                      self.items[idx].readerHTML == html else {
                    return
                }
                self.items[idx].readerHTML = localizedHTML
                self.items[idx].updatedAt = Date()
                self.scheduleSave()
            }
        }
    }

    private func cacheWebPage(for itemID: UUID, url: URL) {
        guard BookmarkedRuntimePreferences.cacheWebPages,
              !webPageCacheTasks.contains(itemID) else {
            return
        }
        webPageCacheTasks.insert(itemID)
        Task {
            _ = await WebPageCache.shared.cache(url: url)
            await MainActor.run {
                _ = self.webPageCacheTasks.remove(itemID)
            }
        }
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map(normalizedTag).filter { !$0.isEmpty })).sorted()
    }

    private static func normalizedTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

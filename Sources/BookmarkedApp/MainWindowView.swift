import SwiftUI
import AppKit
import WebKit
import AVKit

extension Notification.Name {
    static let bookmarkedSelectPreviousItem = Notification.Name("BookmarkedSelectPreviousItem")
    static let bookmarkedSelectNextItem = Notification.Name("BookmarkedSelectNextItem")
    static let bookmarkedSelectPreviousPreviewTab = Notification.Name("BookmarkedSelectPreviousPreviewTab")
    static let bookmarkedSelectNextPreviewTab = Notification.Name("BookmarkedSelectNextPreviewTab")
    static let bookmarkedToggleCompactDetailHeader = Notification.Name("BookmarkedToggleCompactDetailHeader")
    static let bookmarkedToggleSidebar = Notification.Name("BookmarkedToggleSidebar")
    static let bookmarkedToggleSearchFocus = Notification.Name("BookmarkedToggleSearchFocus")
    static let bookmarkedScrollPostUp = Notification.Name("BookmarkedScrollPostUp")
    static let bookmarkedScrollPostDown = Notification.Name("BookmarkedScrollPostDown")
    static let bookmarkedAdjustPreviewFontSize = Notification.Name("BookmarkedAdjustPreviewFontSize")
    static let bookmarkedSaveReaderEdits = Notification.Name("BookmarkedSaveReaderEdits")
    static let bookmarkedFocusNoteEditor = Notification.Name("BookmarkedFocusNoteEditor")
    static let bookmarkedNavigateWebBack = Notification.Name("BookmarkedNavigateWebBack")
    static let bookmarkedNavigateWebForward = Notification.Name("BookmarkedNavigateWebForward")
}

private enum MainWindowFocusField: Hashable {
    case search
}

private enum BookmarkPreviewMode: String, CaseIterable, Identifiable {
    case reader = "Reader"
    case notes = "Notes"
    case web = "Web"
    case settings = "Settings"

    var id: String { rawValue }
}

struct MainWindowView: View {
    @ObservedObject var store: BookmarkStore
    @ObservedObject var controller: MainWindowController
    @State private var query = ""
    @State private var isSidebarVisible = true
    @AppStorage("mainSidebarWidth") private var sidebarWidth = 360.0
    @AppStorage("readerMonoFontName") private var sidebarMonoFontName = ReaderFontPreferences.defaultMonoName
    @FocusState private var focusedField: MainWindowFocusField?

    private var results: [BookmarkItem] {
        store.search(query)
    }

    private var selectedItem: BookmarkItem? {
        store.item(id: controller.selection) ?? results.first
    }

    private var sidebarFontPreferences: ReaderFontPreferences {
        ReaderFontPreferences(
            serifName: ReaderFontPreferences.defaultSerifName,
            sansName: ReaderFontPreferences.defaultSansName,
            monoName: sidebarMonoFontName
        )
    }

    var body: some View {
        Group {
            if controller.isFullScreen, let selectedItem {
                FullScreenReaderView(item: selectedItem, store: store)
            } else {
                HStack(spacing: 0) {
                    if isSidebarVisible {
                        sidebar
                            .frame(width: sidebarWidth)
                        ResizableSidebarDivider(width: $sidebarWidth)
                    }
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusedSceneValue(\.toggleSidebarAction) {
            toggleSidebar()
        }
        .focusedSceneValue(\.increaseReaderFontAction) {
            NotificationCenter.default.post(name: .bookmarkedAdjustPreviewFontSize, object: nil, userInfo: ["delta": 1.0])
        }
        .focusedSceneValue(\.decreaseReaderFontAction) {
            NotificationCenter.default.post(name: .bookmarkedAdjustPreviewFontSize, object: nil, userInfo: ["delta": -1.0])
        }
        .onAppear {
            if controller.selection == nil {
                controller.selection = results.first?.id
            }
        }
        .onChange(of: results) { newValue in
            if let selection = controller.selection, newValue.contains(where: { $0.id == selection }) {
                return
            }
            controller.selection = newValue.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedSelectPreviousItem)) { _ in
            moveSelection(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedSelectNextItem)) { _ in
            moveSelection(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedToggleSearchFocus)) { _ in
            toggleSearchFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedToggleSidebar)) { _ in
            toggleSidebar()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AppBrandIcon(size: 22)

                TextField("Search bookmarks", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(sidebarFontPreferences.codeFont(size: 12))
                    .focused($focusedField, equals: .search)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            HStack {
                Text("\(results.count) bookmarks")
                    .font(sidebarFontPreferences.codeFont(size: 12).weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isCapturing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Capturing")
                        .font(sidebarFontPreferences.codeFont(size: 11).weight(.medium))
                        .foregroundStyle(.secondary)
                } else if let status = store.statusMessage {
                    Text(status)
                        .font(sidebarFontPreferences.codeFont(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { item in
                            BookmarkRow(item: item, fontPreferences: sidebarFontPreferences)
                                .id(item.id)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(controller.selection == item.id ? Color.accentColor : Color.clear)
                                )
                                .foregroundStyle(controller.selection == item.id ? Color.white : Color.primary)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    controller.selection = item.id
                                }
                                .contextMenu {
                                    Button("Open") { store.open(item) }
                                    Button("Refresh Index") { store.refresh(item) }
                                    Divider()
                                    Button("Delete", role: .destructive) { store.delete(item) }
                                }
                                .onAppear {
                                    store.ensureAssets(for: item)
                                }
                            }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: controller.selection) { id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.14)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .background(Color.clear)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedItem {
            BookmarkDetailView(
                item: selectedItem,
                store: store,
                settingsTabRequestID: controller.settingsTabRequestID
            )
        } else if controller.settingsTabRequestID > 0 {
            GlobalSettingsView(settings: BookmarkedSettings.shared, fillsAvailableSpace: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text("No bookmark selected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            controller.selection = nil
            return
        }

        guard let selection = controller.selection,
              let currentIndex = results.firstIndex(where: { $0.id == selection }) else {
            controller.selection = offset < 0 ? results.last?.id : results.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        controller.selection = results[nextIndex].id
    }

    private func toggleSearchFocus() {
        if focusedField == .search {
            focusedField = nil
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        } else {
            if !isSidebarVisible {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarVisible = true
                }
            }
            focusedField = .search
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSidebarVisible.toggle()
        }
    }

}

struct FullScreenReaderView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    @ObservedObject private var settings = BookmarkedSettings.shared
    @State private var previewMode: BookmarkPreviewMode = .reader
    @State private var noteFocusToken = 0
    @State private var webFontScale = 1.0
    @AppStorage("readerFontChoice") private var readerFontChoiceRaw = ReaderFontChoice.serif.rawValue
    @AppStorage("readerFontScale") private var readerFontScale = 1.0
    @AppStorage("readerSerifFontName") private var readerSerifFontName = ReaderFontPreferences.defaultSerifName
    @AppStorage("readerSansFontName") private var readerSansFontName = ReaderFontPreferences.defaultSansName
    @AppStorage("readerMonoFontName") private var readerMonoFontName = ReaderFontPreferences.defaultMonoName

    private var readerFontChoice: ReaderFontChoice {
        ReaderFontChoice(rawValue: readerFontChoiceRaw) ?? .serif
    }

    private var readerFontPreferences: ReaderFontPreferences {
        ReaderFontPreferences(
            serifName: readerSerifFontName,
            sansName: readerSansFontName,
            monoName: readerMonoFontName
        )
    }

    private var previewModes: [BookmarkPreviewMode] {
        canShowWeb ? [.reader, .notes, .web] : [.reader, .notes]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if previewModes.count > 1 {
                Picker("", selection: $previewMode) {
                    ForEach(previewModes) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .font(.system(size: 10, weight: .regular))
                .frame(width: CGFloat(previewModes.count) * 54)
                .scaleEffect(0.82, anchor: .topTrailing)
                .opacity(0.52)
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
        }
        .background(noteKeyboardShortcut)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            store.ensureAssets(for: item)
        }
        .onChange(of: item.id) { _ in
            previewMode = .reader
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedSelectPreviousPreviewTab)) { _ in
            movePreviewTab(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedSelectNextPreviewTab)) { _ in
            movePreviewTab(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedAdjustPreviewFontSize)) { notification in
            adjustFontScale(delta: fontScaleDelta(from: notification))
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedFocusNoteEditor)) { _ in
            focusNoteEditor()
        }
    }

    private var canShowWeb: Bool {
        item.url != nil && (item.kind == .webPage || item.kind == .githubRepo)
    }

    @ViewBuilder
    private var preview: some View {
        if previewMode == .notes {
            noteReader
        } else if canShowWeb, let url = item.url {
            ZStack {
                textReader
                    .opacity(previewMode == .reader ? 1 : 0)
                    .allowsHitTesting(previewMode == .reader)
                WebPreview(
                    url: url,
                    title: item.title,
                    fallbackHTML: item.readerHTML,
                    fallbackText: item.contentText,
                    fontScale: webFontScale,
                    useCachedPage: settings.cacheWebPages
                )
                    .opacity(previewMode == .web ? 1 : 0)
                    .allowsHitTesting(previewMode == .web)
            }
        } else {
            textReader
        }
    }

    @ViewBuilder
    private var textReader: some View {
        EditableReaderView(
            item: item,
            store: store,
            fontChoice: readerFontChoice,
            fontPreferences: readerFontPreferences,
            fontScale: readerFontScale
        )
    }

    @ViewBuilder
    private var noteReader: some View {
        EditableBookmarkNoteView(
            item: item,
            store: store,
            fontChoice: readerFontChoice,
            fontPreferences: readerFontPreferences,
            fontScale: readerFontScale,
            focusToken: noteFocusToken
        )
    }

    private var noteKeyboardShortcut: some View {
        Group {
            if previewMode == .notes {
                Button("") {
                    focusNoteEditor()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func movePreviewTab(by offset: Int) {
        let modes = previewModes
        guard !modes.isEmpty else { return }
        guard let currentIndex = modes.firstIndex(of: previewMode) else {
            previewMode = modes[0]
            return
        }
        previewMode = modes[(currentIndex + offset + modes.count) % modes.count]
    }

    private func adjustFontScale(delta: Double) {
        if previewMode == .web {
            webFontScale = clampedFontScale(webFontScale + delta * 0.08)
        } else {
            readerFontScale = clampedFontScale(readerFontScale + delta * 0.08)
        }
    }

    private func focusNoteEditor() {
        previewMode = .notes
        noteFocusToken += 1
    }
}

struct EditableReaderView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    let fontChoice: ReaderFontChoice
    let fontPreferences: ReaderFontPreferences
    let fontScale: Double

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var isEditingHTML = false
    @State private var htmlEditorCommand = ReaderHTMLEditorCommand()
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                reader
            }
        }
        .focusedSceneValue(\.saveReaderEditAction, saveAction)
        .onChange(of: item.id) { _ in
            isEditing = false
            isEditingHTML = false
            draftText = editableSource
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedSaveReaderEdits)) { _ in
            guard isEditing else { return }
            save()
        }
    }

    private var saveAction: (() -> Void)? {
        isEditing ? { save() } : nil
    }

    @ViewBuilder
    private var reader: some View {
        if let html = item.readerHTML, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ReaderHTMLView(
                title: item.title,
                html: html,
                baseURL: item.url,
                fontChoice: fontChoice,
                fontPreferences: fontPreferences,
                fontScale: fontScale,
                onEditSource: beginEditing,
                onElementRemoved: { updatedHTML in
                    store.saveReaderEdits(for: item.id, text: updatedHTML, isHTML: true)
                }
            )
        } else {
            ReaderContentView(
                text: item.contentText,
                fontChoice: fontChoice,
                fontPreferences: fontPreferences,
                fontScale: fontScale,
                onEditSource: beginEditing
            )
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(isEditingHTML ? "Editing Reader HTML" : "Editing Reader Text")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(BookmarkedSettings.shared.shortcut(for: .saveReaderEdits).displayText) saves")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if isEditingHTML {
                    Button("Strip Images") {
                        htmlEditorCommand = htmlEditorCommand.next(.stripImages)
                    }
                    .help("Remove image and figure markup from this reader version")
                    Button("Remove Selected") {
                        htmlEditorCommand = htmlEditorCommand.next(.removeSelected)
                    }
                    .help("Remove the highlighted block from this reader version")
                }
                Button("Cancel") {
                    isEditing = false
                    isEditingHTML = false
                    draftText = editableSource
                }
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if isEditingHTML {
                ReaderHTMLEditorView(
                    html: $draftText,
                    baseURL: item.url,
                    fontChoice: fontChoice,
                    fontPreferences: fontPreferences,
                    fontScale: fontScale,
                    command: htmlEditorCommand
                )
            } else {
                TextEditor(text: $draftText)
                    .font(fontChoice.swiftUIFont(scale: fontScale, preferences: fontPreferences))
                    .lineSpacing(6)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 30)
                    .focused($editorFocused)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func beginEditing() {
        isEditingHTML = item.readerHTML?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        draftText = editableSource
        isEditing = true
        if !isEditingHTML {
            DispatchQueue.main.async {
                editorFocused = true
            }
        }
    }

    private func save() {
        store.saveReaderEdits(for: item.id, text: draftText, isHTML: isEditingHTML)
        isEditing = false
    }

    private var editableSource: String {
        if let html = item.readerHTML, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return html
        }
        return item.contentText
    }
}

struct EditableBookmarkNoteView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    let fontChoice: ReaderFontChoice
    let fontPreferences: ReaderFontPreferences
    let fontScale: Double
    let focusToken: Int

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var focusEditor = false
    @State private var editingItemID: UUID?

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                reader
            }
        }
        .onAppear {
            draftText = item.note ?? ""
            if focusToken > 0 {
                beginEditing()
            }
        }
        .onDisappear {
            if isEditing {
                save()
            }
        }
        .onChange(of: item.id) { _ in
            if isEditing {
                save()
            }
            draftText = item.note ?? ""
            isEditing = false
        }
        .onChange(of: focusToken) { _ in
            beginEditing()
        }
    }

    private var reader: some View {
        ReaderContentView(
            text: item.note ?? "",
            fontChoice: fontChoice,
            fontPreferences: fontPreferences,
            fontScale: fontScale,
            emptyMessage: "No notes yet."
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            beginEditing()
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    cancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .help("Discard note edits")

                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .help("Save note")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            EscapeCommitTextEditor(
                text: $draftText,
                onEscape: save,
                focusRequest: $focusEditor
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func beginEditing() {
        draftText = item.note ?? ""
        isEditing = true
        editingItemID = item.id
        focusEditor = true
    }

    private func save() {
        store.setNote(id: editingItemID ?? item.id, text: draftText)
        isEditing = false
        focusEditor = false
        editingItemID = nil
    }

    private func cancel() {
        draftText = item.note ?? ""
        isEditing = false
        focusEditor = false
        editingItemID = nil
    }
}

private struct EscapeCommitTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onEscape: () -> Void
    @Binding var focusRequest: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let contentSize = scroll.contentSize
        let container = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false

        let layout = NSLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let textView = EscapeCommitNSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.onEscape = onEscape
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 44, height: 30)
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.string = text

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if focusRequest {
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                window.makeFirstResponder(textView)
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                textView.scrollRangeToVisible(NSRange(location: end, length: 0))
                focusRequest = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EscapeCommitTextEditor

        init(_ parent: EscapeCommitTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class EscapeCommitNSTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
            return
        }
        super.keyDown(with: event)
    }
}

private extension String {
    func strippingHTMLImages() -> String {
        var value = self
        value = value.replacingOccurrences(
            of: "<figure\\b[^>]*>[\\s\\S]*?</figure>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: "<picture\\b[^>]*>[\\s\\S]*?</picture>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: "<img\\b[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BookmarkRow: View {
    let item: BookmarkItem
    let fontPreferences: ReaderFontPreferences

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BookmarkIcon(item: item, fallbackColor: kindColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(fontPreferences.codeFont(size: 13).weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.kind.rawValue)
                    if let creator = item.creator, !creator.isEmpty {
                        Text("·")
                        Text(creator)
                    }
                }
                .font(fontPreferences.codeFont(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(fontPreferences.codeFont(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var kindColor: Color {
        switch item.kind {
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

struct BookmarkDetailView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    let settingsTabRequestID: Int
    @ObservedObject private var settings = BookmarkedSettings.shared
    @State private var previewMode: BookmarkPreviewMode = .reader
    @State private var previousPreviewMode: BookmarkPreviewMode = .reader
    @State private var noteFocusToken = 0
    @State private var webFontScale = 1.0
    @AppStorage("detailHeaderCompact") private var isHeaderCompact = false
    @AppStorage("readerFontChoice") private var readerFontChoiceRaw = ReaderFontChoice.serif.rawValue
    @AppStorage("readerFontScale") private var readerFontScale = 1.0
    @AppStorage("readerSerifFontName") private var readerSerifFontName = ReaderFontPreferences.defaultSerifName
    @AppStorage("readerSansFontName") private var readerSansFontName = ReaderFontPreferences.defaultSansName
    @AppStorage("readerMonoFontName") private var readerMonoFontName = ReaderFontPreferences.defaultMonoName

    private var readerFontChoice: ReaderFontChoice {
        get { ReaderFontChoice(rawValue: readerFontChoiceRaw) ?? .serif }
        nonmutating set { readerFontChoiceRaw = newValue.rawValue }
    }

    private var readerFontPreferences: ReaderFontPreferences {
        ReaderFontPreferences(
            serifName: readerSerifFontName,
            sansName: readerSansFontName,
            monoName: readerMonoFontName
        )
    }

    private var previewModes: [BookmarkPreviewMode] {
        switch item.kind {
        case .webPage, .githubRepo:
            return item.url == nil ? [.reader, .notes] : [.reader, .notes, .web]
        default:
            return [.reader, .notes]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            preview
        }
        .background(previewKeyboardShortcuts)
        .onChange(of: item.id) { _ in
            previewMode = .reader
            previousPreviewMode = .reader
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedSelectPreviousPreviewTab)) { _ in
            movePreviewTab(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedSelectNextPreviewTab)) { _ in
            movePreviewTab(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedToggleCompactDetailHeader)) { _ in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHeaderCompact.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedAdjustPreviewFontSize)) { notification in
            adjustFontScale(delta: fontScaleDelta(from: notification))
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarkedFocusNoteEditor)) { _ in
            focusNoteEditor()
        }
        .onChange(of: settingsTabRequestID) { _ in
            openSettingsTab()
        }
    }

    @ViewBuilder
    private var header: some View {
        if isHeaderCompact {
            compactHeader
        } else {
            expandedHeader
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            if let data = item.faviconData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    store.open(item)
                }
                .help(item.url != nil || item.fileURL != nil ? "Double-click to open" : "")

            Spacer(minLength: 12)

            Button {
                openSettingsTab()
            } label: {
                Image(systemName: previewMode == .settings ? "gearshape.fill" : "gearshape")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(previewMode == .settings ? Color.accentColor : Color.primary)
            .help("Settings")

            if previewModes.count > 1 {
                Picker("", selection: $previewMode) {
                    ForEach(previewModes) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: CGFloat(previewModes.count) * 62)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 34)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            store.ensureAssets(for: item)
        }
    }

    private var expandedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let data = item.faviconData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            store.open(item)
                        }
                        .help(item.url != nil || item.fileURL != nil ? "Double-click to open" : "")
                    HStack(spacing: 8) {
                        Label(item.kind.rawValue, systemImage: "tag")
                        if let creator = item.creator, !creator.isEmpty {
                            Label(creator, systemImage: "person.crop.circle")
                        }
                        Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                if previewModes.count > 1 {
                    Picker("", selection: $previewMode) {
                        ForEach(previewModes) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: CGFloat(previewModes.count) * 72)
                }

                Button {
                    store.refresh(item)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 22, height: 22)
                }
                .frame(width: 54, height: 32)
                .buttonStyle(.bordered)
                .help("Refresh indexed content")
                .disabled(item.url == nil)

                Button {
                    openSettingsTab()
                } label: {
                    Image(systemName: previewMode == .settings ? "gearshape.fill" : "gearshape")
                        .frame(width: 22, height: 22)
                }
                .frame(width: 54, height: 32)
                .buttonStyle(.bordered)
                .foregroundStyle(previewMode == .settings ? Color.accentColor : Color.primary)
                .help("Settings")
            }

            if !item.tags.isEmpty {
                FlowTags(tags: item.tags)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            store.ensureAssets(for: item)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if previewMode == .settings {
            GlobalSettingsView(settings: settings, fillsAvailableSpace: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        } else if previewMode == .notes {
            noteReader
        } else {
            switch item.kind {
            case .image:
                if let url = item.url ?? item.fileURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().padding(16)
                        case .failure:
                            textReader
                        case .empty:
                            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        @unknown default:
                            textReader
                        }
                    }
                } else {
                    textReader
                }
            case .video, .podcast, .audio:
                if let url = item.url ?? item.fileURL {
                    VStack(spacing: 12) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(minHeight: 300)
                        textReader
                    }
                } else {
                    textReader
                }
            case .webPage, .githubRepo:
                if let url = item.url {
                    if previewMode == .web {
                        WebPreview(
                            url: url,
                            title: item.title,
                            fallbackHTML: item.readerHTML,
                            fallbackText: item.contentText,
                            fontScale: webFontScale,
                            useCachedPage: settings.cacheWebPages
                        )
                    } else {
                        textReader
                    }
                } else {
                    textReader
                }
            case .file, .note:
                textReader
            }
        }
    }

    @ViewBuilder
    private var textReader: some View {
        EditableReaderView(
            item: item,
            store: store,
            fontChoice: readerFontChoice,
            fontPreferences: readerFontPreferences,
            fontScale: readerFontScale
        )
    }

    @ViewBuilder
    private var noteReader: some View {
        EditableBookmarkNoteView(
            item: item,
            store: store,
            fontChoice: readerFontChoice,
            fontPreferences: readerFontPreferences,
            fontScale: readerFontScale,
            focusToken: noteFocusToken
        )
    }

    private var previewKeyboardShortcuts: some View {
        Group {
            if previewMode == .notes {
                Button("") {
                    focusNoteEditor()
                }
                .keyboardShortcut(.return, modifiers: [])
            }

            if previewMode == .settings {
                Button("") {
                    closeSettingsTab()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func movePreviewTab(by offset: Int) {
        let modes = previewModes
        guard !modes.isEmpty else { return }
        guard let currentIndex = modes.firstIndex(of: previewMode) else {
            previewMode = modes[0]
            return
        }
        previewMode = modes[(currentIndex + offset + modes.count) % modes.count]
    }

    private func adjustFontScale(delta: Double) {
        if previewMode == .web {
            webFontScale = clampedFontScale(webFontScale + delta * 0.08)
        } else {
            readerFontScale = clampedFontScale(readerFontScale + delta * 0.08)
        }
    }

    private func focusNoteEditor() {
        previewMode = .notes
        noteFocusToken += 1
    }

    private func openSettingsTab() {
        if previewMode != .settings {
            previousPreviewMode = previewMode
        }
        previewMode = .settings
    }

    private func closeSettingsTab() {
        previewMode = previewModes.contains(previousPreviewMode) ? previousPreviewMode : (previewModes.first ?? .reader)
    }
}

private struct ResizableSidebarDivider: View {
    @Binding var width: Double
    @State private var startWidth = 0.0

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if startWidth == 0 {
                                    startWidth = width
                                }
                                width = min(520, max(260, startWidth + value.translation.width))
                            }
                            .onEnded { _ in
                                startWidth = 0
                            }
                    )
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct GlobalSettingsView: View {
    @ObservedObject var settings: BookmarkedSettings
    var fillsAvailableSpace = false

    var body: some View {
        TabView {
            ShortcutsSettingsPane(settings: settings)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            ImagesSettingsPane(settings: settings)
                .tabItem {
                    Label("Cache", systemImage: "internaldrive")
                }

            FontSettingsPane()
                .tabItem {
                    Label("Fonts", systemImage: "textformat")
                }
        }
        .frame(width: fillsAvailableSpace ? nil : 620, height: fillsAvailableSpace ? nil : 520)
        .frame(
            maxWidth: fillsAvailableSpace ? .infinity : nil,
            maxHeight: fillsAvailableSpace ? .infinity : nil
        )
        .padding(10)
    }
}

private struct ShortcutsSettingsPane: View {
    @ObservedObject var settings: BookmarkedSettings
    @State private var recordingAction: BookmarkedShortcutAction?

    private var groupedActions: [(String, [BookmarkedShortcutAction])] {
        let grouped = Dictionary(grouping: BookmarkedShortcutAction.allCases, by: \.groupTitle)
        return ["Global", "Window", "Navigation", "Reader"].compactMap { title in
            guard let actions = grouped[title] else { return nil }
            return (title, actions)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groupedActions, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.0)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            ForEach(group.1) { action in
                                ShortcutSettingsRow(
                                    action: action,
                                    shortcut: settings.shortcut(for: action),
                                    isOverridden: settings.isOverridden(action),
                                    conflicts: settings.conflictingActions(for: action),
                                    onRecord: { recordingAction = action },
                                    onReset: { settings.resetShortcut(for: action) }
                                )
                                if action != group.1.last {
                                    Divider().padding(.leading, 148)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
            }
            .padding(18)
        }
        .sheet(item: $recordingAction) { action in
            ShortcutCaptureSheet(action: action, settings: settings)
        }
    }
}

private struct ShortcutSettingsRow: View {
    let action: BookmarkedShortcutAction
    let shortcut: BookmarkedKeyboardShortcut
    let isOverridden: Bool
    let conflicts: [BookmarkedShortcutAction]
    let onRecord: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                if !conflicts.isEmpty {
                    Text("Also used by \(conflicts.map(\.title).joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if isOverridden {
                    Text("Overridden")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(shortcut.displayText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(minWidth: 74, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

            Button("Change", action: onRecord)
                .controlSize(.small)

            Button("Reset", action: onReset)
                .controlSize(.small)
                .disabled(!isOverridden)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct ShortcutCaptureSheet: View {
    let action: BookmarkedShortcutAction
    @ObservedObject var settings: BookmarkedSettings
    @Environment(\.dismiss) private var dismiss
    @State private var preview: BookmarkedKeyboardShortcut?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(action.title)
                .font(.system(size: 15, weight: .semibold))
            Text(preview?.displayText ?? "Press the new shortcut")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .frame(minWidth: 180, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

            ShortcutCaptureView { shortcut in
                preview = shortcut
                settings.setShortcut(shortcut, for: action)
                dismiss()
            }
            .frame(width: 1, height: 1)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Button("Reset to Default") {
                    settings.resetShortcut(for: action)
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (BookmarkedKeyboardShortcut) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        CaptureNSView(onCapture: onCapture)
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class CaptureNSView: NSView {
        var onCapture: (BookmarkedKeyboardShortcut) -> Void

        init(onCapture: @escaping (BookmarkedKeyboardShortcut) -> Void) {
            self.onCapture = onCapture
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard let shortcut = BookmarkedKeyboardShortcut.from(event: event) else { return }
            onCapture(shortcut)
        }
    }
}

private struct ImagesSettingsPane: View {
    @ObservedObject var settings: BookmarkedSettings
    @State private var storageSnapshot = BookmarkedCacheStorage.snapshot()

    var body: some View {
        Form {
            Toggle("Cache reader images locally", isOn: $settings.cacheReaderImages)
            Text("When enabled, newly indexed reader pages copy article images into Application Support so the Reader view keeps working when remote images change or disappear.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("Cache Web tab pages for offline reading", isOn: $settings.cacheWebPages)
            Text("When enabled, Bookmarked saves a local copy of newly indexed web pages and uses that copy in the Web tab when available.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Section("Disk Usage") {
                CacheUsageRow(title: "Reader images", bytes: storageSnapshot.readerImageBytes)
                CacheUsageRow(title: "Web pages", bytes: storageSnapshot.webPageBytes)
                CacheUsageRow(title: "Total cache", bytes: storageSnapshot.totalBytes, isEmphasized: true)

                Button {
                    storageSnapshot = BookmarkedCacheStorage.snapshot()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            storageSnapshot = BookmarkedCacheStorage.snapshot()
        }
    }
}

private struct CacheUsageRow: View {
    let title: String
    let bytes: Int64
    var isEmphasized = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: isEmphasized ? .semibold : .regular))
            Spacer()
            Text(Self.formatter.string(fromByteCount: bytes))
                .font(.system(size: 13, weight: isEmphasized ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isEmphasized ? .primary : .secondary)
        }
    }

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}

private struct FontSettingsPane: View {
    @AppStorage("readerFontChoice") private var readerFontChoiceRaw = ReaderFontChoice.serif.rawValue
    @AppStorage("readerSerifFontName") private var readerSerifFontName = ReaderFontPreferences.defaultSerifName
    @AppStorage("readerSansFontName") private var readerSansFontName = ReaderFontPreferences.defaultSansName
    @AppStorage("readerMonoFontName") private var readerMonoFontName = ReaderFontPreferences.defaultMonoName

    private var readerFontChoice: ReaderFontChoice {
        get { ReaderFontChoice(rawValue: readerFontChoiceRaw) ?? .serif }
        nonmutating set { readerFontChoiceRaw = newValue.rawValue }
    }

    var body: some View {
        Form {
            Section("Body Style") {
                Picker("", selection: Binding(
                    get: { readerFontChoice },
                    set: { readerFontChoice = $0 }
                )) {
                    ForEach(ReaderFontChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }

            Section("Font Families") {
                ReaderFontNameField(
                    title: "Serif",
                    text: $readerSerifFontName,
                    defaultName: ReaderFontPreferences.defaultSerifName
                )
                ReaderFontNameField(
                    title: "Sans",
                    text: $readerSansFontName,
                    defaultName: ReaderFontPreferences.defaultSansName
                )
                ReaderFontNameField(
                    title: "Mono",
                    text: $readerMonoFontName,
                    defaultName: ReaderFontPreferences.defaultMonoName
                )
            }

            Section("Preview") {
                Text("A reader paragraph with code")
                    .font(readerFontChoice.swiftUIFont(preferences: fontPreferences))
                Text("Headings use the sans font")
                    .font(fontPreferences.headingFont(level: 3).weight(.semibold))
                Text("let mono = \"code\"")
                    .font(fontPreferences.codeFont(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var fontPreferences: ReaderFontPreferences {
        ReaderFontPreferences(
            serifName: readerSerifFontName,
            sansName: readerSansFontName,
            monoName: readerMonoFontName
        )
    }
}

private struct ReaderFontNameField: View {
    let title: String
    @Binding var text: String
    let defaultName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                FontFamilyComboBox(
                    text: $text,
                    placeholder: defaultName,
                    fontFamilies: ReaderFontPreferences.availableFontFamilyNames
                )
                .frame(minWidth: 240, maxWidth: 460)
                .frame(height: 24)

                Button("Reset") {
                    text = defaultName
                }
                .controlSize(.small)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines) == defaultName)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FontFamilyComboBox: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontFamilies: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 12
        comboBox.placeholderString = placeholder
        comboBox.font = NSFont.systemFont(ofSize: 12)
        comboBox.delegate = context.coordinator
        comboBox.addItems(withObjectValues: fontFamilies)
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.text = $text
        if comboBox.numberOfItems != fontFamilies.count {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: fontFamilies)
        }
        comboBox.placeholderString = placeholder
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text.wrappedValue = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text.wrappedValue = comboBox.stringValue
        }
    }
}

struct AppBrandIcon: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .modifier(ConditionalColorInvert(isInverted: colorScheme == .dark))
                .accessibilityLabel("Bookmarked")
        } else {
            Image(systemName: "bookmark")
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.orange)
                .frame(width: size, height: size)
                .accessibilityLabel("Bookmarked")
        }
    }

    private static let image: NSImage? = {
        guard let url1x = Bundle.module.url(forResource: "brand-icon", withExtension: "png", subdirectory: "Resources"),
              let rep1x = NSBitmapImageRep(data: (try? Data(contentsOf: url1x)) ?? Data()) else {
            return nil
        }
        let pointSize = NSSize(width: 24, height: 24)
        rep1x.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep1x)
        if let url2x = Bundle.module.url(forResource: "brand-icon@2x", withExtension: "png", subdirectory: "Resources"),
           let rep2x = NSBitmapImageRep(data: (try? Data(contentsOf: url2x)) ?? Data()) {
            rep2x.size = pointSize
            image.addRepresentation(rep2x)
        }
        return image
    }()
}

private struct ConditionalColorInvert: ViewModifier {
    let isInverted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isInverted {
            content.colorInvert()
        } else {
            content
        }
    }
}

struct BookmarkIcon: View {
    let item: BookmarkItem
    let fallbackColor: Color

    var body: some View {
        Group {
            if let data = item.faviconData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(fallbackColor)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(width: 24, height: 24)
    }
}

struct FlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags.prefix(6), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .separatorColor).opacity(0.12))
                    )
            }
        }
    }
}

struct WebPreview: NSViewRepresentable {
    let url: URL
    let title: String
    let fallbackHTML: String?
    let fallbackText: String
    let fontScale: Double
    let useCachedPage: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = view
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.webView = nsView
        context.coordinator.load(
            url: url,
            title: title,
            fallbackHTML: fallbackHTML,
            fallbackText: fallbackText,
            useCachedPage: useCachedPage,
            in: nsView
        )
        let pageZoom = CGFloat(fontScale)
        if abs(nsView.pageZoom - pageZoom) > 0.001 {
            nsView.pageZoom = pageZoom
        }
    }

    final class Coordinator {
        weak var webView: WKWebView?
        private var observers: [NSObjectProtocol] = []
        private var loadingTask: Task<Void, Never>?
        private var loadedRequest: LoadRequest?
        private let fallbackDocumentURL = WebPageCache.defaultDirectoryURL
            .appendingPathComponent("PreviewDocuments", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).html")
        private let step = 420

        init() {
            observers.append(NotificationCenter.default.addObserver(
                forName: .bookmarkedScrollPostDown,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scroll(by: 1)
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .bookmarkedScrollPostUp,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scroll(by: -1)
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .bookmarkedNavigateWebBack,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.navigateBack()
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .bookmarkedNavigateWebForward,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.navigateForward()
            })
        }

        deinit {
            loadingTask?.cancel()
            try? FileManager.default.removeItem(at: fallbackDocumentURL)
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func load(
            url: URL,
            title: String,
            fallbackHTML: String?,
            fallbackText: String,
            useCachedPage: Bool,
            in webView: WKWebView
        ) {
            let fallbackDocument = Self.fallbackDocument(title: title, html: fallbackHTML, text: fallbackText)
            let request = LoadRequest(url: url, useCachedPage: useCachedPage, fallbackDocument: fallbackDocument)
            guard loadedRequest != request else { return }
            loadedRequest = request
            loadingTask?.cancel()

            if useCachedPage && Self.shouldLoadStaticCache(for: url) {
                if let cachedURL = WebPageCache.shared.cachedPageURL(for: url),
                   let staticDocument = Self.staticCachedDocument(from: cachedURL),
                   let documentURL = writeFallbackDocument(staticDocument) {
                    webView.loadFileURL(documentURL, allowingReadAccessTo: WebPageCache.shared.readAccessDirectory)
                } else if let fallbackDocument,
                          let documentURL = writeFallbackDocument(fallbackDocument) {
                    webView.loadFileURL(documentURL, allowingReadAccessTo: WebPageCache.shared.readAccessDirectory)
                    loadingTask = Task {
                        _ = await WebPageCache.shared.cache(url: url)
                    }
                } else {
                    webView.load(URLRequest(url: url))
                    loadingTask = Task {
                        _ = await WebPageCache.shared.cache(url: url)
                    }
                }
                return
            }

            if useCachedPage {
                if let cachedURL = WebPageCache.shared.cachedPageURL(for: url) {
                    webView.loadFileURL(cachedURL, allowingReadAccessTo: WebPageCache.shared.readAccessDirectory)
                } else if let fallbackDocument,
                          let documentURL = writeFallbackDocument(fallbackDocument) {
                    webView.loadFileURL(documentURL, allowingReadAccessTo: WebPageCache.shared.readAccessDirectory)
                    loadingTask = Task {
                        _ = await WebPageCache.shared.store(html: fallbackDocument, pageURL: url, cacheURL: url)
                    }
                } else {
                    webView.load(URLRequest(url: url))
                    loadingTask = Task {
                        _ = await WebPageCache.shared.cache(url: url)
                    }
                }
            } else {
                webView.load(URLRequest(url: url))
            }
        }

        private static func shouldLoadStaticCache(for url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return host == "substack.com" || host.hasSuffix(".substack.com")
        }

        private static func staticCachedDocument(from url: URL) -> String? {
            guard var html = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            html = html
                .replacingOccurrences(of: "<script\\b[\\s\\S]*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "\\s(on[a-zA-Z]+)=(\"[^\"]*\"|'[^']*')", with: "", options: [.regularExpression])
                .preparedForLocalMediaDisplay()
            return html
        }

        private func scroll(by direction: Int) {
            webView?.evaluateJavaScript("window.scrollBy({ top: \(step * direction), left: 0, behavior: 'smooth' });")
        }

        private func navigateBack() {
            guard webView?.canGoBack == true else { return }
            webView?.goBack()
        }

        private func navigateForward() {
            guard webView?.canGoForward == true else { return }
            webView?.goForward()
        }

        private func writeFallbackDocument(_ document: String) -> URL? {
            do {
                try FileManager.default.createDirectory(
                    at: fallbackDocumentURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try document.write(to: fallbackDocumentURL, atomically: true, encoding: .utf8)
                return fallbackDocumentURL
            } catch {
                return nil
            }
        }

        private static func fallbackDocument(title: String, html: String?, text: String) -> String? {
            let trimmedHTML = html?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHTML.isEmpty || !trimmedText.isEmpty else { return nil }
            let body = trimmedHTML.isEmpty ? "<pre>\(escape(trimmedText))</pre>" : trimmedHTML
            return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(escape(title))</title>
            <style>
            :root { color-scheme: light dark; }
            body {
              margin: 0;
              background: Canvas;
              color: CanvasText;
              font: 17px/1.62 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            }
            main {
              max-width: 820px;
              margin: 0 auto;
              padding: 38px 48px 80px;
            }
            h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.45em 0 0.45em; }
            p, ul, ol, blockquote, pre, figure { margin: 0 0 1.05em; }
            img, video { display: block; max-width: 100%; max-height: min(70vh, 560px); width: auto; height: auto; object-fit: contain; }
            pre { white-space: pre-wrap; font: inherit; }
            a { color: #2563eb; }
            </style>
            </head>
            <body><main>\(body)</main></body>
            </html>
            """
        }

        private static func escape(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        private struct LoadRequest: Equatable {
            var url: URL
            var useCachedPage: Bool
            var fallbackDocument: String?
        }
    }
}

private func fontScaleDelta(from notification: Notification) -> Double {
    notification.userInfo?["delta"] as? Double ?? 0
}

private func clampedFontScale(_ value: Double) -> Double {
    min(1.6, max(0.72, value))
}

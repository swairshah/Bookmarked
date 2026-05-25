import SwiftUI
import WebKit
import AVKit

extension Notification.Name {
    static let bookmarkedSelectPreviousItem = Notification.Name("BookmarkedSelectPreviousItem")
    static let bookmarkedSelectNextItem = Notification.Name("BookmarkedSelectNextItem")
    static let bookmarkedSelectPreviousPreviewTab = Notification.Name("BookmarkedSelectPreviousPreviewTab")
    static let bookmarkedSelectNextPreviewTab = Notification.Name("BookmarkedSelectNextPreviewTab")
    static let bookmarkedToggleCompactDetailHeader = Notification.Name("BookmarkedToggleCompactDetailHeader")
    static let bookmarkedToggleSearchFocus = Notification.Name("BookmarkedToggleSearchFocus")
    static let bookmarkedScrollPostUp = Notification.Name("BookmarkedScrollPostUp")
    static let bookmarkedScrollPostDown = Notification.Name("BookmarkedScrollPostDown")
    static let bookmarkedAdjustPreviewFontSize = Notification.Name("BookmarkedAdjustPreviewFontSize")
}

private enum MainWindowFocusField: Hashable {
    case search
}

private enum BookmarkPreviewMode: String, CaseIterable, Identifiable {
    case reader = "Reader"
    case notes = "Notes"
    case web = "Web"

    var id: String { rawValue }
}

struct MainWindowView: View {
    @ObservedObject var store: BookmarkStore
    @ObservedObject var controller: MainWindowController
    @State private var query = ""
    @State private var isSidebarVisible = true
    @AppStorage("mainSidebarWidth") private var sidebarWidth = 360.0
    @FocusState private var focusedField: MainWindowFocusField?

    private var results: [BookmarkItem] {
        store.search(query)
    }

    private var selectedItem: BookmarkItem? {
        store.item(id: controller.selection) ?? results.first
    }

    var body: some View {
        Group {
            if controller.isFullScreen, let selectedItem {
                FullScreenReaderView(item: selectedItem, store: store)
            } else {
                VStack(spacing: 0) {
                    topBar
                    Divider()
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
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusedSceneValue(\.toggleSidebarAction) {
            withAnimation(.easeInOut(duration: 0.18)) {
                isSidebarVisible.toggle()
            }
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
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 24)

            TextField("Search content, creator, date, source, or URL", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)
                .focused($focusedField, equals: .search)

            Spacer()

            if store.isCapturing {
                ProgressView()
                    .controlSize(.small)
                Text("Capturing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            controller.toggleZoom()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(results.count) bookmarks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let status = store.statusMessage {
                    Text(status)
                        .font(.system(size: 11))
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
                            BookmarkRow(item: item)
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
            BookmarkDetailView(item: selectedItem, store: store)
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
            focusedField = .search
        }
    }

}

struct FullScreenReaderView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    @State private var previewMode: BookmarkPreviewMode = .reader
    @State private var webFontScale = 1.0
    @AppStorage("readerFontChoice") private var readerFontChoiceRaw = ReaderFontChoice.serif.rawValue
    @AppStorage("readerFontScale") private var readerFontScale = 1.0

    private var readerFontChoice: ReaderFontChoice {
        ReaderFontChoice(rawValue: readerFontChoiceRaw) ?? .serif
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
                WebPreview(url: url, fontScale: webFontScale)
                    .opacity(previewMode == .web ? 1 : 0)
                    .allowsHitTesting(previewMode == .web)
            }
        } else {
            textReader
        }
    }

    @ViewBuilder
    private var textReader: some View {
        EditableReaderView(item: item, store: store, fontChoice: readerFontChoice, fontScale: readerFontScale)
    }

    @ViewBuilder
    private var noteReader: some View {
        ReaderContentView(
            text: item.note ?? "",
            fontChoice: readerFontChoice,
            fontScale: readerFontScale,
            emptyMessage: "No notes yet."
        )
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
}

struct EditableReaderView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    let fontChoice: ReaderFontChoice
    let fontScale: Double

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var isEditingHTML = false
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
                fontScale: fontScale,
                onEditSource: beginEditing,
                onElementRemoved: { updatedHTML in
                    store.saveReaderEdits(for: item.id, text: updatedHTML, isHTML: true)
                }
            )
        } else {
            ReaderContentView(text: item.contentText, fontChoice: fontChoice, fontScale: fontScale, onEditSource: beginEditing)
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(isEditingHTML ? "Editing Reader HTML" : "Editing Reader Text")
                    .font(.system(size: 13, weight: .semibold))
                Text("Command-S saves")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if isEditingHTML {
                    Button("Strip Images") {
                        draftText = draftText.strippingHTMLImages()
                    }
                    .help("Remove image and figure markup from this reader version")
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

            TextEditor(text: $draftText)
                .font(isEditingHTML ? .system(size: 13, design: .monospaced) : fontChoice.swiftUIFont(scale: fontScale))
                .lineSpacing(6)
                .padding(.horizontal, 44)
                .padding(.vertical, 30)
                .focused($editorFocused)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func beginEditing() {
        isEditingHTML = item.readerHTML?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        draftText = editableSource
        isEditing = true
        DispatchQueue.main.async {
            editorFocused = true
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BookmarkIcon(item: item, fallbackColor: kindColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.kind.rawValue)
                    if let creator = item.creator, !creator.isEmpty {
                        Text("·")
                        Text(creator)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
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
    @State private var previewMode: BookmarkPreviewMode = .reader
    @State private var showingSettings = false
    @State private var webFontScale = 1.0
    @AppStorage("detailHeaderCompact") private var isHeaderCompact = false
    @AppStorage("readerFontChoice") private var readerFontChoiceRaw = ReaderFontChoice.serif.rawValue
    @AppStorage("readerFontScale") private var readerFontScale = 1.0

    private var readerFontChoice: ReaderFontChoice {
        get { ReaderFontChoice(rawValue: readerFontChoiceRaw) ?? .serif }
        nonmutating set { readerFontChoiceRaw = newValue.rawValue }
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
        .onChange(of: item.id) { _ in
            previewMode = .reader
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
                    showingSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 22, height: 22)
                }
                .frame(width: 54, height: 32)
                .buttonStyle(.bordered)
                .help("Reader settings")
                .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                    ReaderSettingsPanel(
                        fontChoice: Binding(
                            get: { readerFontChoice },
                            set: { readerFontChoice = $0 }
                        )
                    )
                }
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
        if previewMode == .notes {
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
                        WebPreview(url: url, fontScale: webFontScale)
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
        EditableReaderView(item: item, store: store, fontChoice: readerFontChoice, fontScale: readerFontScale)
    }

    @ViewBuilder
    private var noteReader: some View {
        ReaderContentView(
            text: item.note ?? "",
            fontChoice: readerFontChoice,
            fontScale: readerFontScale,
            emptyMessage: "No notes yet."
        )
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

struct ReaderSettingsPanel: View {
    @Binding var fontChoice: ReaderFontChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                Text("Reader Settings")
                    .font(.system(size: 14, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Font")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $fontChoice) {
                    ForEach(ReaderFontChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
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
    let fontScale: Double

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
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
        let pageZoom = CGFloat(fontScale)
        if abs(nsView.pageZoom - pageZoom) > 0.001 {
            nsView.pageZoom = pageZoom
        }
    }

    final class Coordinator {
        weak var webView: WKWebView?
        private var observers: [NSObjectProtocol] = []
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
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func scroll(by direction: Int) {
            webView?.evaluateJavaScript("window.scrollBy({ top: \(step * direction), left: 0, behavior: 'smooth' });")
        }
    }
}

private func fontScaleDelta(from notification: Notification) -> Double {
    notification.userInfo?["delta"] as? Double ?? 0
}

private func clampedFontScale(_ value: Double) -> Double {
    min(1.6, max(0.72, value))
}

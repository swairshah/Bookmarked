import SwiftUI
import WebKit
import AVKit

private enum BookmarkPreviewMode: String, CaseIterable, Identifiable {
    case reader = "Reader"
    case web = "Web"

    var id: String { rawValue }
}

struct MainWindowView: View {
    @ObservedObject var store: BookmarkStore
    @ObservedObject var controller: MainWindowController
    @State private var query = ""
    @State private var isSidebarVisible = true
    @AppStorage("mainSidebarWidth") private var sidebarWidth = 360.0

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
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 24)

            Text("Bookmarked")
                .font(.system(size: 18, weight: .semibold))

            TextField("Search content, creator, date, source, or URL", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)

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

            List(selection: $controller.selection) {
                ForEach(results) { item in
                    BookmarkRow(item: item)
                        .tag(item.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .contextMenu {
                            Button("Open") { store.open(item) }
                            Button("Refresh Index") { store.refresh(item) }
                            Divider()
                            Button("Delete", role: .destructive) { store.delete(item) }
                        }
                        .onTapGesture(count: 2) {
                            store.open(item)
                        }
                        .onAppear {
                            store.ensureAssets(for: item)
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 34)
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

}

struct FullScreenReaderView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    @State private var previewMode: BookmarkPreviewMode = .reader
    @AppStorage("readerFontChoice") private var readerFontChoiceRaw = ReaderFontChoice.serif.rawValue

    private var readerFontChoice: ReaderFontChoice {
        ReaderFontChoice(rawValue: readerFontChoiceRaw) ?? .serif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if canShowWeb {
                Picker("", selection: $previewMode) {
                    ForEach(BookmarkPreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .font(.system(size: 10, weight: .regular))
                .frame(width: 92)
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
    }

    private var canShowWeb: Bool {
        item.url != nil && (item.kind == .webPage || item.kind == .githubRepo)
    }

    @ViewBuilder
    private var preview: some View {
        if canShowWeb, let url = item.url {
            ZStack {
                textReader
                    .opacity(previewMode == .reader ? 1 : 0)
                    .allowsHitTesting(previewMode == .reader)
                WebPreview(url: url)
                    .opacity(previewMode == .web ? 1 : 0)
                    .allowsHitTesting(previewMode == .web)
            }
        } else {
            textReader
        }
    }

    @ViewBuilder
    private var textReader: some View {
        EditableReaderView(item: item, store: store, fontChoice: readerFontChoice)
    }
}

struct EditableReaderView: View {
    let item: BookmarkItem
    @ObservedObject var store: BookmarkStore
    let fontChoice: ReaderFontChoice

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
                onDoubleClick: beginEditing
            )
        } else {
            ReaderContentView(text: item.contentText, fontChoice: fontChoice, onDoubleClick: beginEditing)
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
                .font(isEditingHTML ? .system(size: 13, design: .monospaced) : fontChoice.swiftUIFont)
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
    @AppStorage("readerFontChoice") private var readerFontChoiceRaw = ReaderFontChoice.serif.rawValue

    private var readerFontChoice: ReaderFontChoice {
        get { ReaderFontChoice(rawValue: readerFontChoiceRaw) ?? .serif }
        nonmutating set { readerFontChoiceRaw = newValue.rawValue }
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
    }

    private var header: some View {
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

                if item.url != nil && (item.kind == .webPage || item.kind == .githubRepo) {
                    Picker("", selection: $previewMode) {
                        ForEach(BookmarkPreviewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
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
                ZStack {
                    textReader
                        .opacity(previewMode == .reader ? 1 : 0)
                        .allowsHitTesting(previewMode == .reader)
                    WebPreview(url: url)
                        .opacity(previewMode == .web ? 1 : 0)
                        .allowsHitTesting(previewMode == .web)
                }
            } else {
                textReader
            }
        case .file, .note:
            textReader
        }
    }

    @ViewBuilder
    private var textReader: some View {
        EditableReaderView(item: item, store: store, fontChoice: readerFontChoice)
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

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityLabel("Bookmarked")
        } else {
            Image(systemName: "bookmark")
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(.orange)
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

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}

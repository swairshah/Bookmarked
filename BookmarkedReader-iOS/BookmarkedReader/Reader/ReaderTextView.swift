import SwiftUI

/// Native reader for plain-text / indexed content (no captured HTML).
/// Same lightweight block model as the macOS `ReaderContentView`:
/// `#` headings, `-`/`*` bullets, blank-line-separated paragraphs, inline markdown.
struct ReaderTextView: View {
    let text: String
    let preferences: ReaderFontPreferences
    var emptyMessage = "No indexed text yet."
    var topInset: CGFloat = 16
    var bottomInset: CGFloat = 96
    var onScroll: ((CGFloat) -> Void)? = nil
    private let blocks: [ReaderBlock]

    init(
        text: String,
        preferences: ReaderFontPreferences,
        emptyMessage: String = "No indexed text yet.",
        topInset: CGFloat = 16,
        bottomInset: CGFloat = 96,
        onScroll: ((CGFloat) -> Void)? = nil
    ) {
        self.text = text
        self.preferences = preferences
        self.emptyMessage = emptyMessage
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.onScroll = onScroll
        self.blocks = ReaderBlock.parse(text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if blocks.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .textSelection(.enabled)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ReaderScrollOffsetKey.self,
                        value: -geo.frame(in: .named("readerScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "readerScroll")
        .onPreferenceChange(ReaderScrollOffsetKey.self) { onScroll?($0) }
    }

    @ViewBuilder
    private func blockView(_ block: ReaderBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.inlineAttributed)
                .font(preferences.headingFont(level: level))
                .lineSpacing(3)
                .padding(.top, level == 1 ? 8 : 12)
                .padding(.bottom, 2)
        case .paragraph:
            Text(block.inlineAttributed)
                .font(preferences.articleFont())
                .lineSpacing(preferences.lineSpacing)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").font(preferences.bulletFont())
                Text(block.inlineAttributed)
                    .font(preferences.articleFont())
                    .lineSpacing(preferences.lineSpacing - 1)
            }
            .padding(.leading, 8)
        }
    }
}

private struct ReaderScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ReaderBlock: Identifiable {
    enum Kind: Equatable {
        case heading(Int)
        case paragraph
        case bullet
    }

    let id: Int
    let kind: Kind
    let text: String
    let inlineAttributed: AttributedString

    init(id: Int, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
        self.inlineAttributed = Self.inlineAttributed(from: text)
    }

    private static func inlineAttributed(from text: String) -> AttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var attributed = (try? AttributedString(markdown: trimmed)) ?? AttributedString(trimmed)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = .secondary
            attributed[run.range].underlineStyle = nil
        }
        return attributed
    }

    static func parse(_ raw: String) -> [ReaderBlock] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var blocks: [ReaderBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphLines.removeAll()
            guard !paragraph.isEmpty else { return }
            blocks.append(ReaderBlock(id: blocks.count, kind: .paragraph, text: paragraph))
        }

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { flushParagraph(); continue }
            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(ReaderBlock(id: blocks.count, kind: .heading(heading.level), text: heading.text))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(ReaderBlock(id: blocks.count, kind: .bullet, text: String(line.dropFirst(2))))
                continue
            }
            paragraphLines.append(line)
        }
        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (hashes, text)
    }
}

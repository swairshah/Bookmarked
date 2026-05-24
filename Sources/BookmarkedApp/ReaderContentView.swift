import SwiftUI

struct ReaderContentView: View {
    let text: String
    let fontChoice: ReaderFontChoice
    var onEditSource: (() -> Void)?

    private var blocks: [ReaderBlock] {
        ReaderBlock.parse(text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if blocks.isEmpty {
                    Text("No indexed text yet.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity, alignment: .top)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contextMenu {
            Button("Edit Reader Source") {
                onEditSource?()
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ReaderBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.inlineAttributed)
                .font(.system(size: headingSize(level), weight: .semibold))
                .lineSpacing(3)
                .padding(.top, level == 1 ? 8 : 12)
                .padding(.bottom, 2)
        case .paragraph:
            Text(block.inlineAttributed)
                .font(fontChoice.swiftUIFont)
                .lineSpacing(7)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .font(.system(size: 17, weight: .semibold))
                Text(block.inlineAttributed)
                    .font(fontChoice.swiftUIFont)
                    .lineSpacing(6)
            }
            .padding(.leading, 8)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 30
        case 2: return 24
        case 3: return 20
        default: return 18
        }
    }
}

struct ReaderBlock: Identifiable {
    enum Kind: Equatable {
        case heading(Int)
        case paragraph
        case bullet
    }

    let id = UUID()
    let kind: Kind
    let text: String

    var inlineAttributed: AttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? AttributedString(markdown: trimmed)) ?? AttributedString(trimmed)
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
            let paragraph = paragraphLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphLines.removeAll()
            guard !paragraph.isEmpty else { return }
            blocks.append(ReaderBlock(kind: .paragraph, text: paragraph))
        }

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(ReaderBlock(kind: .heading(heading.level), text: heading.text))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(ReaderBlock(kind: .bullet, text: String(line.dropFirst(2))))
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

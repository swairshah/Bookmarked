import SwiftUI

enum ReaderFontChoice: String, CaseIterable, Identifiable {
    case serif = "Serif"
    case sans = "Sans"
    case mono = "Mono"

    var id: String { rawValue }

    var swiftUIFont: Font {
        switch self {
        case .serif:
            return .custom("New York", size: 18)
        case .sans:
            return .system(size: 17)
        case .mono:
            return .system(size: 16, design: .monospaced)
        }
    }

    var cssFontFamily: String {
        switch self {
        case .serif:
            return #"ui-serif, "New York", "Iowan Old Style", Georgia, serif"#
        case .sans:
            return #"-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif"#
        case .mono:
            return #""SF Mono", ui-monospace, Menlo, monospace"#
        }
    }

    var cssFontSize: String {
        switch self {
        case .serif: return "19px"
        case .sans: return "18px"
        case .mono: return "16px"
        }
    }

    var cssLineHeight: String {
        switch self {
        case .serif: return "1.66"
        case .sans: return "1.62"
        case .mono: return "1.72"
        }
    }
}

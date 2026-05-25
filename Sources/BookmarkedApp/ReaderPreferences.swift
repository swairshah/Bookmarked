import SwiftUI

enum ReaderFontChoice: String, CaseIterable, Identifiable {
    case serif = "Serif"
    case sans = "Sans"
    case mono = "Mono"

    var id: String { rawValue }

    func swiftUIFont(scale: Double = 1) -> Font {
        switch self {
        case .serif:
            return .custom("New York", size: 18 * scale)
        case .sans:
            return .system(size: 17 * scale)
        case .mono:
            return .system(size: 16 * scale, design: .monospaced)
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

    func cssFontSize(scale: Double = 1) -> String {
        let baseSize: Double
        switch self {
        case .serif: baseSize = 19
        case .sans: baseSize = 18
        case .mono: baseSize = 16
        }
        return "\(Int((baseSize * scale).rounded()))px"
    }

    var cssLineHeight: String {
        switch self {
        case .serif: return "1.66"
        case .sans: return "1.62"
        case .mono: return "1.72"
        }
    }
}

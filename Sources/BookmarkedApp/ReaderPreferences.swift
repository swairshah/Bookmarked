import SwiftUI
import AppKit

enum ReaderFontChoice: String, CaseIterable, Identifiable {
    case serif = "Serif"
    case sans = "Sans"
    case mono = "Mono"

    var id: String { rawValue }

    func swiftUIFont(scale: Double = 1, preferences: ReaderFontPreferences = .defaults) -> Font {
        preferences.swiftUIFont(for: self, scale: scale)
    }

    func cssFontFamily(preferences: ReaderFontPreferences = .defaults) -> String {
        preferences.cssFontFamily(for: self)
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

struct ReaderFontPreferences: Equatable {
    static let defaultSerifName = "New York"
    static let defaultSansName = "SF Pro Text"
    static let defaultMonoName = "SF Mono"
    static let defaultArticleSize = 18.0
    static let defaultInterfaceSize = 13.0
    static let defaultCodeSize = 13.0
    static let defaults = ReaderFontPreferences(
        serifName: defaultSerifName,
        sansName: defaultSansName,
        monoName: defaultMonoName,
        articleSize: defaultArticleSize,
        interfaceSize: defaultInterfaceSize,
        codeSize: defaultCodeSize
    )
    static let availableFontFamilyNames = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    var serifName: String
    var sansName: String
    var monoName: String
    var articleSize: Double = Self.defaultArticleSize
    var interfaceSize: Double = Self.defaultInterfaceSize
    var codeSize: Double = Self.defaultCodeSize

    func swiftUIFont(for choice: ReaderFontChoice, scale: Double = 1) -> Font {
        let size: Double
        switch choice {
        case .serif: size = 18
        case .sans: size = 17
        case .mono: size = 16
        }

        return font(named: fontName(for: choice), size: size * scale, fallback: choice)
    }

    func articleFont(scale: Double = 1) -> Font {
        font(named: serifName, size: articleSize * scale, fallback: .serif)
    }

    func headingFont(level: Int) -> Font {
        font(named: serifName, size: headingSize(level), fallback: .serif)
    }

    func interfaceFont(size: Double) -> Font {
        font(named: sansName, size: scaledInterfaceSize(size), fallback: .sans)
    }

    func codeFont(size: Double) -> Font {
        font(named: monoName, size: scaledCodeSize(size), fallback: .mono)
    }

    func cssFontFamily(for choice: ReaderFontChoice) -> String {
        switch choice {
        case .serif:
            return cssFamily(primary: serifName, defaultName: Self.defaultSerifName, fallback: #"ui-serif, "Iowan Old Style", Georgia, serif"#)
        case .sans:
            return cssFamily(primary: sansName, defaultName: Self.defaultSansName, fallback: #"-apple-system, BlinkMacSystemFont, system-ui, sans-serif"#)
        case .mono:
            return cssFamily(primary: monoName, defaultName: Self.defaultMonoName, fallback: #"ui-monospace, Menlo, monospace"#)
        }
    }

    var cssHeadingFontFamily: String {
        cssArticleFontFamily
    }

    var cssArticleFontFamily: String {
        cssFontFamily(for: .serif)
    }

    func cssArticleFontSize(scale: Double = 1) -> String {
        "\(Int((articleSize * scale).rounded()))px"
    }

    var cssArticleLineHeight: String {
        "1.66"
    }

    var cssInterfaceFontFamily: String {
        cssFontFamily(for: .sans)
    }

    var cssMonoFontFamily: String {
        cssFamily(primary: monoName, defaultName: Self.defaultMonoName, fallback: #"ui-monospace, Menlo, monospace"#)
    }

    var cssCodeFontSize: String {
        "\(Int(codeSize.rounded()))px"
    }

    private func fontName(for choice: ReaderFontChoice) -> String {
        switch choice {
        case .serif: return serifName
        case .sans: return sansName
        case .mono: return monoName
        }
    }

    private func font(named name: String, size: Double, fallback: ReaderFontChoice) -> Font {
        let cleanName = sanitizedFontName(name, fallback: defaultName(for: fallback))
        if let resolvedName = resolvedFontName(cleanName, size: size) {
            return .custom(resolvedName, size: size)
        }

        switch fallback {
        case .serif:
            return .custom(Self.defaultSerifName, size: size)
        case .sans:
            return .system(size: size)
        case .mono:
            return .system(size: size, design: .monospaced)
        }
    }

    private func resolvedFontName(_ name: String, size: Double) -> String? {
        if NSFont(name: name, size: CGFloat(size)) != nil {
            return name
        }

        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: name) else {
            return nil
        }

        let candidates: [(fontName: String, faceName: String)] = members.compactMap { member in
            guard let fontName = member.first as? String else {
                return nil
            }
            let faceName = member.dropFirst().first as? String ?? ""
            return (fontName, faceName)
        }

        return candidates.first { candidate in
            candidate.faceName.localizedCaseInsensitiveContains("regular")
        }?.fontName ?? candidates.first?.fontName
    }

    private func defaultName(for choice: ReaderFontChoice) -> String {
        switch choice {
        case .serif: return Self.defaultSerifName
        case .sans: return Self.defaultSansName
        case .mono: return Self.defaultMonoName
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        let scale: Double
        switch level {
        case 1: scale = 30 / Self.defaultArticleSize
        case 2: scale = 24 / Self.defaultArticleSize
        case 3: scale = 20 / Self.defaultArticleSize
        default: scale = 1
        }
        return CGFloat(articleSize * scale)
    }

    private func scaledInterfaceSize(_ size: Double) -> Double {
        size * interfaceSize / Self.defaultInterfaceSize
    }

    private func scaledCodeSize(_ size: Double) -> Double {
        size * codeSize / Self.defaultCodeSize
    }

    private func cssFamily(primary: String, defaultName: String, fallback: String) -> String {
        #""\#(Self.cssEscaped(sanitizedFontName(primary, fallback: defaultName)))", \#(fallback)"#
    }

    private func sanitizedFontName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func cssEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum ReaderLinkStyle {
    static let cssColor = "color-mix(in srgb, CanvasText 58%, transparent)"
    static let cssDeclaration = "color: \(cssColor); text-decoration: none"
    static let swiftUIColor = Color(nsColor: .secondaryLabelColor)

    static func apply(to attributed: AttributedString) -> AttributedString {
        var styled = attributed
        for run in styled.runs where run.link != nil {
            styled[run.range].foregroundColor = swiftUIColor
            styled[run.range].underlineStyle = nil
        }
        return styled
    }
}

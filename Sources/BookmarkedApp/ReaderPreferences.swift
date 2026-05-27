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
    static let defaults = ReaderFontPreferences(
        serifName: defaultSerifName,
        sansName: defaultSansName,
        monoName: defaultMonoName
    )
    static let availableFontFamilyNames = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    var serifName: String
    var sansName: String
    var monoName: String

    func swiftUIFont(for choice: ReaderFontChoice, scale: Double = 1) -> Font {
        let size: Double
        switch choice {
        case .serif: size = 18
        case .sans: size = 17
        case .mono: size = 16
        }

        return font(named: fontName(for: choice), size: size * scale, fallback: choice)
    }

    func headingFont(level: Int) -> Font {
        font(named: sansName, size: headingSize(level), fallback: .sans)
    }

    func codeFont(size: Double) -> Font {
        font(named: monoName, size: size, fallback: .mono)
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
        cssFamily(primary: sansName, defaultName: Self.defaultSansName, fallback: #"-apple-system, BlinkMacSystemFont, system-ui, sans-serif"#)
    }

    var cssMonoFontFamily: String {
        cssFamily(primary: monoName, defaultName: Self.defaultMonoName, fallback: #"ui-monospace, Menlo, monospace"#)
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
        switch level {
        case 1: return 30
        case 2: return 24
        case 3: return 20
        default: return 18
        }
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

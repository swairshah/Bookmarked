import SwiftUI
import UIKit

/// The three reader faces, matching the macOS app: New York (serif),
/// SF Pro Text (sans), SF Mono (mono). These are the system optical fonts;
/// the native reader resolves them via `UIFontDescriptor.withDesign` and the
/// WebView reader leads its CSS stack with the matching `ui-*` token so both
/// render the exact same families as the Mac app.
enum ReaderFontChoice: String, CaseIterable, Identifiable {
    case serif = "Serif"
    case sans = "Sans"
    case mono = "Mono"

    var id: String { rawValue }

    var uiDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .serif: return .serif        // New York
        case .sans:  return .default      // SF Pro
        case .mono:  return .monospaced   // SF Mono
        }
    }

    /// CSS family stack for the WebView reader. Serif leads with the bundled
    /// custom "Reader" family (defined via @font-face), matching the Mac app,
    /// then falls back to New York. Sans/Mono use the system optical fonts.
    var cssFontFamily: String {
        switch self {
        case .serif: return #""Reader", ui-serif, "New York", Georgia, serif"#
        case .sans:  return #"-apple-system, ui-sans-serif, "SF Pro Text", system-ui, sans-serif"#
        case .mono:  return #""Google Sans Code", ui-monospace, "SF Mono", Menlo, monospace"#
        }
    }
}

/// Article sizing. `articleSize` is the base point size; `scale` is the
/// user's +/- adjustment. iPhone users need a wider ceiling than the Mac
/// preview because the device is used closer to the eye and often one-handed.
struct ReaderFontPreferences: Equatable {
    var choice: ReaderFontChoice = .serif
    var articleSize: Double = 18
    var codeSize: Double = 14
    var scale: Double = 1.0

    static let minScale = 0.65
    static let maxScale = 2.4
    static let scaleStep = 0.10

    // MARK: SwiftUI (native text reader)

    /// Sans/Mono: the exact system optical font via a system font descriptor.
    /// Serif: the bundled custom "Reader" faces (registered at launch).
    private func font(size: Double, weight: UIFont.Weight) -> Font {
        let bold = weight != .regular
        if choice == .serif {
            return .custom(bold ? ReaderFonts.boldName : ReaderFonts.regularName, size: size)
        }
        if choice == .mono {
            return .custom(bold ? ReaderFonts.codeBoldName : ReaderFonts.codeRegularName, size: size)
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(choice.uiDesign) {
            return Font(UIFont(descriptor: descriptor, size: size))
        }
        return Font(base)
    }

    func articleFont() -> Font {
        font(size: articleSize * scale, weight: .regular)
    }

    func headingFont(level: Int) -> Font {
        let size: Double
        switch level {
        case 1: size = 30
        case 2: size = 24
        case 3: size = 20
        default: size = articleSize
        }
        return font(size: size * scale, weight: .semibold)
    }

    func bulletFont() -> Font {
        font(size: 17 * scale, weight: .semibold)
    }

    var lineSpacing: CGFloat { CGFloat(articleSize * scale * 0.34) }

    // MARK: CSS (WebView reader) — identical strings to the macOS reader

    var cssFontFamily: String { choice.cssFontFamily }
    var cssFontSize: String { "\(Int((articleSize * scale).rounded()))px" }
    var cssLineHeight: String {
        switch choice {
        case .serif: return "1.66"
        case .sans:  return "1.62"
        case .mono:  return "1.72"
        }
    }
    var cssCodeFontFamily: String { ReaderFontChoice.mono.cssFontFamily }
    var cssCodeFontSize: String { "\(Int(codeSize.rounded()))px" }

    func bumpedScale(by delta: Double) -> Double {
        min(max(scale + delta, Self.minScale), Self.maxScale)
    }
}

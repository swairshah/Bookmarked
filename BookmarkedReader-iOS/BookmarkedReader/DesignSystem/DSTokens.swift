import SwiftUI

// Vendored verbatim from the `ios-native` DesignSystem package
// (Tokens/DSColor.swift, DSFont.swift, DSLayout.swift, DSMotion.swift).
// Kept in-app so the project opens and runs with no external checkout.
// To track the package as the single source of truth later, delete this file
// and add `/Users/swair/work/UX/design-systems/ios-native` as a local SPM
// dependency, then `import DesignSystem`.

enum DSColor {
    static let accent = Color.accentColor

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.primary.opacity(0.45)

    static let surface = Color.primary.opacity(0.0)
    static let surfaceSubtle = Color.primary.opacity(0.035)
    static let surfaceHover = Color.primary.opacity(0.08)
    static let surfaceSelected = Color.accentColor.opacity(0.15)

    static let divider = Color.primary.opacity(0.08)
    static let stroke = Color.primary.opacity(0.12)

    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.blue
}

enum DSFont {
    static func system(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let micro = Font.system(size: 10)
    static let microEmphasis = Font.system(size: 10, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionEmphasis = Font.system(size: 11, weight: .medium)
    static let footnote = Font.system(size: 12)
    static let footnoteEmphasis = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .semibold)
    static let callout = Font.system(size: 14, weight: .medium)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let title3 = Font.system(size: 17, weight: .semibold)
    static let title2 = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 28, weight: .regular)
    static let largeTitle = Font.system(size: 34, weight: .regular)
    static let display = Font.system(size: 40, weight: .light)
}

enum DSSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let ml: CGFloat = 10
    static let l: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
}

enum DSRadius {
    static let small: CGFloat = 4
    static let row: CGFloat = 8
    static let card: CGFloat = 12
    static let pill: CGFloat = 999
}

enum DSSize {
    static let iconButton: CGFloat = 18
    static let iconButtonLarge: CGFloat = 24
    static let statusDot: CGFloat = 8
    static let hairline: CGFloat = 1
}

enum DSMotion {
    static let quick = Animation.easeOut(duration: 0.12)
    static let standard = Animation.easeInOut(duration: 0.2)
    static let hover = Animation.easeOut(duration: 0.15)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

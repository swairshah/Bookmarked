import SwiftUI

// Vendored from the `ios-native` DesignSystem package
// (Components/DSTag.swift, Styles/DSSurface.swift). See DSTokens.swift.

struct DSTag: View {
    let text: String
    var tint: Color?
    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }
    var body: some View {
        Text(text)
            .font(DSFont.micro)
            .foregroundStyle(tint ?? DSColor.textSecondary)
            .padding(.horizontal, DSSpacing.xs + 1)
            .padding(.vertical, 1)
            .background(
                Capsule().fill((tint ?? DSColor.textPrimary).opacity(tint == nil ? 0.07 : 0.12))
            )
    }
}

struct DSDividerLine: View {
    var body: some View {
        Rectangle()
            .fill(DSColor.divider)
            .frame(height: DSSize.hairline)
    }
}

struct DSRowBackgroundModifier: ViewModifier {
    var selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                    .fill(selected ? DSColor.surfaceSelected : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func dsRowBackground(selected: Bool = false) -> some View {
        modifier(DSRowBackgroundModifier(selected: selected))
    }
}

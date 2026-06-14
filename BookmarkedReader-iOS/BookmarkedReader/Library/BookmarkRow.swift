import SwiftUI
import UIKit

/// Library row, matching the macOS sidebar: favicon (or tinted kind glyph),
/// title, "Kind · Creator", and the created date.
struct BookmarkRow: View {
    let item: BookmarkItem

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.ml) {
            BookmarkIcon(item: item)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(item.title)
                    .font(DSFont.callout)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)

                Text(item.displaySubtitle)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DSFont.micro)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DSSpacing.xs)
        .contentShape(Rectangle())
    }
}

struct BookmarkIcon: View {
    let item: BookmarkItem
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let data = item.faviconData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size - 4, height: size - 4)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous))
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: size * 0.62, weight: .medium))
                    .foregroundStyle(item.kind.tint)
            }
        }
        .frame(width: size, height: size)
    }
}

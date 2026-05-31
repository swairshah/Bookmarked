import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: BookmarkStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [BookmarkItem] {
        Array(store.search(query).prefix(query.isEmpty ? 7 : 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            search
            Divider().opacity(0.5)
            list
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 390)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack {
            AppBrandIcon(size: 24)
            Text("Bookmarked")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if store.isCapturing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var search: some View {
        VStack(spacing: 8) {
            TextField("Search bookmarks", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var list: some View {
        Group {
            if results.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "No bookmarks yet" : "No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(results) { item in
                            MenuBookmarkRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    MainWindowController.shared.show(select: item.id)
                                }
                                .onTapGesture(count: 2) {
                                    store.open(item)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(height: 320)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                MainWindowController.shared.show()
            } label: {
                Label("Open Library", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                MainWindowController.shared.showSettingsTab()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Bookmarked")
        }
        .padding(12)
    }
}

struct MenuBookmarkRow: View {
    let item: BookmarkItem

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            BookmarkIcon(item: item, fallbackColor: .orange)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(item.kind.rawValue)
                    if let creator = item.creator, !creator.isEmpty {
                        Text("·")
                        Text(creator)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

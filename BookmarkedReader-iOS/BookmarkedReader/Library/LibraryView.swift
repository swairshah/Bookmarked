import SwiftUI

/// The whole app, essentially: a searchable list of bookmarks that pushes into
/// the reader. No capture, no editing, no in-app web — read-only by design.
struct LibraryView: View {
    @ObservedObject var store: BookmarkStore
    @ObservedObject private var pairing = PairingController.shared
    @State private var query = ""
    @State private var showingSync = false

    private var results: [BookmarkItem] { store.search(query) }

    private var syncIcon: String {
        if pairing.connectedPeers > 0 { return "wifi" }
        return pairing.trusted.isEmpty ? "wifi.slash" : "wifi.exclamationmark"
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Bookmarked")
            .toolbarTitleDisplayMode(.inlineLarge)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search bookmarks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSync = true } label: {
                        Image(systemName: syncIcon)
                    }
                    .accessibilityLabel("Local sync")
                }
            }
            .sheet(isPresented: $showingSync) {
                SyncSheet(store: store)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(results) { item in
                    NavigationLink(value: item) {
                        BookmarkRow(item: item)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 12))
                }
            } footer: {
                Text("\(results.count) bookmark\(results.count == 1 ? "" : "s") · \(store.sourceDescription)")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: BookmarkItem.self) { item in
            ReaderScreen(item: item)
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .refreshable { store.refreshAndReconnect() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Library Found", systemImage: "bookmark.slash")
        } description: {
            Text("Add a bookmarks.json export to the app's Documents folder, or wire up the shared container to sync with the Mac app.")
        }
    }
}

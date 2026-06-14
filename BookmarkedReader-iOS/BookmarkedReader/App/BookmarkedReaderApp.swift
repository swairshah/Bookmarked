import SwiftUI

@main
struct BookmarkedReaderApp: App {
    @StateObject private var store = BookmarkStore.shared

    init() {
        ReaderFonts.registerBundled()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(store: store)
        }
    }
}

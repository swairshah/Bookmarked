import XCTest
@testable import Bookmarked
import BookmarkedClient

final class BookmarkedLinkTests: XCTestCase {
    func testAppLinkUsesOpenRoute() {
        let id = UUID(uuidString: "87DF5A21-DEA9-4ABD-8DAC-FF8D65EDCD99")!

        XCTAssertEqual(
            BookmarkedLinks.appLink(for: id),
            "bookmarked://open/87DF5A21-DEA9-4ABD-8DAC-FF8D65EDCD99"
        )
    }

    func testBookmarkDefaultsAppLink() {
        let id = UUID(uuidString: "87DF5A21-DEA9-4ABD-8DAC-FF8D65EDCD99")!
        let bookmark = BookmarkedBookmark(
            id: id,
            title: "Teaching a Smol Model to Write SQL Queries",
            kind: "Web Page",
            url: "https://diicell.bearblog.dev/teaching-a-smol-model-to-write-sql-queries/",
            tags: [],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(bookmark.resolvedAppLink, "bookmarked://open/87DF5A21-DEA9-4ABD-8DAC-FF8D65EDCD99")
    }

    func testDeepLinkParserAcceptsCanonicalOpenLink() {
        let url = URL(string: "bookmarked://open/87DF5A21-DEA9-4ABD-8DAC-FF8D65EDCD99")!

        XCTAssertEqual(
            BookmarkedDeepLink.idOrPrefix(from: url),
            "87DF5A21-DEA9-4ABD-8DAC-FF8D65EDCD99"
        )
    }

    func testDeepLinkParserAcceptsShortPrefix() {
        let url = URL(string: "bookmarked://open/87DF5A21")!

        XCTAssertEqual(BookmarkedDeepLink.idOrPrefix(from: url), "87DF5A21")
    }

    func testDeepLinkParserAcceptsHostOnlyShortcut() {
        let url = URL(string: "bookmarked://87DF5A21")!

        XCTAssertEqual(BookmarkedDeepLink.idOrPrefix(from: url), "87DF5A21")
    }
}

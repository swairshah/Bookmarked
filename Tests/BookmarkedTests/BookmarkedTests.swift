import XCTest
@testable import Bookmarked

final class BookmarkedTests: XCTestCase {
    func testClassifiesCommonBookmarkKinds() {
        XCTAssertEqual(BookmarkClassifier.classify(url: URL(string: "https://github.com/apple/swift")), .githubRepo)
        XCTAssertEqual(BookmarkClassifier.classify(url: URL(string: "https://example.com/image.jpg")), .image)
        XCTAssertEqual(BookmarkClassifier.classify(url: URL(string: "https://youtu.be/abc")), .video)
        XCTAssertEqual(BookmarkClassifier.classify(url: URL(string: "https://podcasts.apple.com/us/podcast/example/id1")), .podcast)
        XCTAssertEqual(BookmarkClassifier.classify(url: URL(string: "https://example.com/article")), .webPage)
    }

    func testHTMLExtractorFindsMetadataAndReadableText() {
        let html = """
        <html><head>
        <title>Fallback</title>
        <meta property="og:title" content="Readable Page">
        <meta name="author" content="Ada">
        <meta name="description" content="A compact summary.">
        <style>.hidden{}</style>
        </head><body><nav>Skip to main content</nav><article><h1>Readable Page</h1><p>Hello &amp; welcome. Here&#x27;s text.</p><script>noise()</script></article></body></html>
        """

        let content = HTMLContentExtractor.extract(from: html, url: URL(string: "https://example.com")!)
        XCTAssertEqual(content.title, "Readable Page")
        XCTAssertEqual(content.creator, "Ada")
        XCTAssertEqual(content.summary, "A compact summary.")
        XCTAssertTrue(content.text.contains("# Readable Page"))
        XCTAssertTrue(content.text.contains("Hello & welcome."))
        XCTAssertTrue(content.text.contains("Here's text."))
        XCTAssertFalse(content.text.contains("Skip to main content"))
        XCTAssertFalse(content.text.contains("noise"))
    }

    func testReaderBlocksParseMarkdownStructure() {
        let blocks = ReaderBlock.parse("# Title\n\nIntro paragraph with **bold**.\n\n- One\n- Two")

        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0].kind, .heading(1))
        XCTAssertEqual(blocks[1].kind, .paragraph)
        XCTAssertEqual(blocks[2].kind, .bullet)
        XCTAssertEqual(blocks[3].kind, .bullet)
    }
}

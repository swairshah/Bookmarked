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

    func testFaviconCandidatesParseDataAndRelativeIcons() {
        let html = """
        <html><head>
        <link rel="stylesheet" href="/style.css">
        <link rel="shortcut icon" href="data:image/svg+xml,&lt;svg xmlns=&quot;http://www.w3.org/2000/svg&quot;&gt;&lt;/svg&gt;">
        <link rel="apple-touch-icon" href="/touch.png">
        </head></html>
        """

        let candidates = FaviconFetcher.iconCandidates(in: html, baseURL: URL(string: "https://example.com/posts/a")!)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0], .dataURI("data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"))
        XCTAssertEqual(candidates[1], .remote(URL(string: "https://example.com/touch.png")!))
    }

    func testReaderImageCacheStoresImagesAndRewritesHTML() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkedTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let cache = ReaderImageCache(directory: directory) { request in
            XCTAssertTrue([
                URL(string: "https://example.com/images/photo.png")!,
                URL(string: "https://example.com/images/photo-small.png")!
            ].contains(request.url!))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (Data([0x89, 0x50, 0x4E, 0x47]), response)
        }

        let html = #"<article><img src="/images/photo.png" srcset="/images/photo-small.png 1x, /images/photo.png 2x" alt="Local"><a href="/images/photo.png">open</a></article>"#
        let rewritten = await cache.localizingImages(in: html, pageURL: URL(string: "https://example.com/posts/a")!)

        XCTAssertTrue(rewritten.contains("src=\"file://"))
        XCTAssertTrue(rewritten.contains("srcset=\"file://"))
        XCTAssertTrue(rewritten.contains(#"href="/images/photo.png""#))
        XCTAssertFalse(rewritten.contains(#"src="/images/photo.png""#))
        XCTAssertFalse(rewritten.contains(#"/images/photo-small.png"#))

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(try Data(contentsOf: files[0]), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testReaderImageCacheDetectsOnlyRemoteMedia() {
        let cache = ReaderImageCache()
        let pageURL = URL(string: "https://example.com/posts/a")!

        XCTAssertTrue(cache.hasRemoteImages(in: #"<img src="/image.png">"#, pageURL: pageURL))
        XCTAssertFalse(cache.hasRemoteImages(in: #"<img src="file:///tmp/image.png">"#, pageURL: pageURL))
        XCTAssertFalse(cache.hasRemoteImages(in: #"<a href="/image.png">open</a>"#, pageURL: pageURL))
    }

    func testReaderFontPreferencesBuildEscapedCSSFamilies() {
        let preferences = ReaderFontPreferences(
            serifName: "Literata",
            sansName: "Avenir Next",
            monoName: "JetBrains \"Mono\""
        )

        XCTAssertTrue(preferences.cssFontFamily(for: .serif).contains(#""Literata""#))
        XCTAssertTrue(preferences.cssHeadingFontFamily.contains(#""Avenir Next""#))
        XCTAssertTrue(preferences.cssMonoFontFamily.contains(#""JetBrains \"Mono\"""#))
        XCTAssertTrue(preferences.cssMonoFontFamily.contains("ui-monospace"))
    }
}

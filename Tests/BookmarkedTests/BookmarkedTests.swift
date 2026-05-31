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

    func testHTMLExtractorSimplifiesFramerResponsiveVariants() {
        let html = """
        <!doctype html>
        <!-- Made in Framer -->
        <html><head>
        <style>@media(min-width: 1200px){.hidden-mobile{display:none!important}}</style>
        <meta property="og:title" content="Framer Article">
        </head><body>
        <div class="ssr-variant hidden-mobile"><div data-framer-component-type="RichTextContainer"><p>Mobile intro split</p></div></div>
        <div class="desktop-copy"><div data-framer-component-type="RichTextContainer"><p>Introduction</p></div></div>
        <div style="position:absolute;top:0;left:0"><img width="2400" height="1200" src="/chart.jpg" style="width:100%;height:100%"></div>
        <div data-framer-component-type="RichTextContainer"><p>Introduction</p></div>
        <div data-framer-component-type="RichTextContainer"><p>The real article paragraph.</p></div>
        </body></html>
        """

        let content = HTMLContentExtractor.extract(from: html, url: URL(string: "https://example.com/research")!)

        XCTAssertEqual(content.title, "Framer Article")
        XCTAssertEqual(content.html?.components(separatedBy: "Introduction").count, 2)
        XCTAssertFalse(content.html?.contains("Mobile intro split") ?? true)
        XCTAssertFalse(content.html?.contains("position:absolute") ?? true)
        XCTAssertTrue(content.html?.contains(#"<figure><img src="https://example.com/chart.jpg""#) ?? false)
        XCTAssertTrue(content.text.contains("The real article paragraph."))
    }

    func testHTMLExtractorKeepsFramerArticleRangeAndDropsChrome() {
        let html = """
        <!doctype html>
        <!-- Made in Framer -->
        <html><head>
        <style>@media(min-width: 1200px){.hidden-mobile{display:none!important}}</style>
        </head><body>
        <div data-framer-component-type="RichTextContainer"><p>BLOG</p></div>
        <div data-framer-component-type="RichTextContainer"><p>Learning GSM8K is Inherently Low-Rank</p></div>
        <div data-framer-component-type="RichTextContainer"><p>Introduction</p></div>
        <div data-framer-component-type="RichTextContainer"><p>This plane carries has two very interesting properties: each point is low rank and scores are high.</p></div>
        <div data-framer-component-type="RichTextContainer"><p>each point is low rank</p></div>
        <img width="5644" height="5360" src="/plot.jpg">
        <div data-framer-component-type="RichTextContainer"><p>References</p></div>
        <div data-framer-component-type="RichTextContainer"><p>Morris et al. Learning to reason in 13 parameters.</p></div>
        <div data-framer-component-type="RichTextContainer"><p>Blogs</p></div>
        <div data-framer-component-type="RichTextContainer"><p>LinkedIn</p></div>
        </body></html>
        """

        let content = HTMLContentExtractor.extract(from: html, url: URL(string: "https://example.com/research/lora")!)

        XCTAssertTrue(content.html?.contains("<h1>Learning GSM8K is Inherently Low-Rank</h1>") ?? false)
        XCTAssertTrue(content.html?.contains("<h2>Introduction</h2>") ?? false)
        XCTAssertTrue(content.html?.contains(#"<figure><img src="https://example.com/plot.jpg""#) ?? false)
        XCTAssertFalse(content.html?.contains("BLOG") ?? true)
        XCTAssertFalse(content.html?.contains("each point is low rank</p>") ?? true)
        XCTAssertFalse(content.html?.contains("LinkedIn") ?? true)
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

        let cache = ReaderImageCache(directory: directory, fetchData: { request in
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
        })

        let html = #"<article><img src="/images/photo.png" srcset="/images/photo-small.png 1x, /images/photo.png 2x" alt="Local"><a href="/images/photo.png">open</a></article>"#
        let rewritten = await cache.localizingImages(in: html, pageURL: URL(string: "https://example.com/posts/a")!)

        XCTAssertTrue(rewritten.contains("src=\"file://"))
        XCTAssertFalse(rewritten.contains("srcset="))
        XCTAssertTrue(rewritten.contains(#"href="/images/photo.png""#))
        XCTAssertFalse(rewritten.contains(#"src="/images/photo.png""#))
        XCTAssertFalse(rewritten.contains(#"/images/photo-small.png"#))

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(try Data(contentsOf: files[0]), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testReaderImageCacheRemovesPictureSourcesThatOverrideLocalImages() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkedPictureTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let imageURL = URL(string: "https://example.com/images/photo.png")!
        let cache = ReaderImageCache(directory: directory, fetchData: { request in
            XCTAssertEqual(request.url, imageURL)
            let response = HTTPURLResponse(
                url: imageURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (Data([0x89, 0x50, 0x4E, 0x47]), response)
        })

        let html = #"<picture><source srcset="https://example.com/images/photo.png 1x"><img src="/images/photo.png" srcset="https://example.com/images/photo.png 1x"></picture>"#
        let rewritten = await cache.localizingImages(in: html, pageURL: URL(string: "https://example.com/posts/a")!)

        XCTAssertTrue(rewritten.contains("src=\"file://"))
        XCTAssertFalse(rewritten.contains("<source"))
        XCTAssertFalse(rewritten.contains("srcset="))
        XCTAssertFalse(rewritten.contains("https://example.com/images/photo.png"))
    }

    func testReaderImageCacheDetectsOnlyRemoteMedia() {
        let cache = ReaderImageCache()
        let pageURL = URL(string: "https://example.com/posts/a")!

        XCTAssertTrue(cache.hasRemoteImages(in: #"<img src="/image.png">"#, pageURL: pageURL))
        XCTAssertFalse(cache.hasRemoteImages(in: #"<img src="file:///tmp/image.png">"#, pageURL: pageURL))
        XCTAssertFalse(cache.hasRemoteImages(in: #"<a href="/image.png">open</a>"#, pageURL: pageURL))
    }

    func testReaderImageCacheCanBeDisabled() async {
        let cache = ReaderImageCache(isEnabled: { false }) { _ in
            XCTFail("Disabled cache should not fetch images")
            throw URLError(.cancelled)
        }
        let pageURL = URL(string: "https://example.com/posts/a")!
        let html = #"<article><img src="/images/photo.png"></article>"#

        let rewritten = await cache.localizingImages(in: html, pageURL: pageURL)
        XCTAssertEqual(rewritten, html)
        XCTAssertFalse(cache.hasRemoteImages(in: html, pageURL: pageURL))
    }

    func testWebPageCacheStoresHTMLAndLocalizesMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkedWebTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let pageURL = URL(string: "https://example.com/posts/a")!
        let imageURL = URL(string: "https://example.com/images/photo.png")!
        let cache = WebPageCache(directory: directory, isEnabled: { true }, fetchData: { request in
            if request.url == pageURL {
                let html = #"<html><body><article><img src="/images/photo.png"><a href="/next">Next</a></article></body></html>"#
                let response = HTTPURLResponse(
                    url: pageURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html; charset=utf-8"]
                )!
                return (Data(html.utf8), response)
            }
            if request.url == imageURL {
                let response = HTTPURLResponse(
                    url: imageURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )!
                return (Data([0x89, 0x50, 0x4E, 0x47]), response)
            }
            XCTFail("Unexpected URL \(request.url?.absoluteString ?? "nil")")
            throw URLError(.badURL)
        })

        let maybeCachedURL = await cache.cache(url: pageURL)
        let cachedURL = try XCTUnwrap(maybeCachedURL)
        let cachedHTML = try String(contentsOf: cachedURL)

        XCTAssertTrue(cachedHTML.contains(#"src="file://"#))
        XCTAssertTrue(cachedHTML.contains(#"href="https://example.com/next""#))
        XCTAssertFalse(cachedHTML.contains(#"src="/images/photo.png""#))
        XCTAssertEqual(cache.cachedPageURL(for: pageURL), cachedURL)
    }

    func testWebPageCacheStoresAlreadyFetchedHTML() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkedFetchedWebTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let pageURL = URL(string: "https://example.com/posts/a")!
        let cache = WebPageCache(directory: directory, isEnabled: { true }, fetchData: { _ in
            XCTFail("Storing already fetched HTML should not refetch the page")
            throw URLError(.cancelled)
        })

        let maybeCachedURL = await cache.store(
            html: #"<html><body><a href="/next">Next</a></body></html>"#,
            pageURL: pageURL,
            cacheURL: pageURL
        )
        let cachedURL = try XCTUnwrap(maybeCachedURL)
        let cachedHTML = try String(contentsOf: cachedURL)

        XCTAssertTrue(cachedHTML.contains(#"href="https://example.com/next""#))
        XCTAssertEqual(cache.cachedPageURL(for: pageURL), cachedURL)
    }

    func testWebPageCacheCanBeDisabled() async {
        let cache = WebPageCache(isEnabled: { false }) { _ in
            XCTFail("Disabled cache should not fetch web pages")
            throw URLError(.cancelled)
        }

        let cachedURL = await cache.cache(url: URL(string: "https://example.com/posts/a")!)
        XCTAssertNil(cachedURL)
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

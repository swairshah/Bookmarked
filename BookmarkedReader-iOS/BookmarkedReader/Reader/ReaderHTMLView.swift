import SwiftUI
import WebKit
import UIKit

/// Rich reader for captured pages. Uses the same stylesheet and KaTeX setup as
/// the macOS reader so an article looks identical on both. Read-only: the
/// editing / element-removal handlers from the Mac app are intentionally dropped.
struct ReaderHTMLView: UIViewRepresentable {
    let title: String
    let html: String
    let baseURL: URL?
    let preferences: ReaderFontPreferences
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var onScroll: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.observeScroll(of: webView.scrollView)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // We manage insets ourselves so the page fills under the status bar and
        // scrolls beneath it, with content held below the safe area.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.currentCSSFontSize = Self.cssFontSize(for: preferences)
        let insets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        if webView.scrollView.contentInset != insets {
            webView.scrollView.contentInset = insets
            webView.scrollView.verticalScrollIndicatorInsets = insets
        }
        if abs(webView.pageZoom - 1) > 0.001 {
            webView.pageZoom = 1
        }
        var baseScalePrefs = preferences
        baseScalePrefs.scale = 1
        let documentKey = DocumentKey(
            title: title,
            html: html,
            baseURL: baseURL,
            preferences: baseScalePrefs
        )
        if context.coordinator.lastDocumentKey != documentKey {
            context.coordinator.lastDocumentKey = documentKey
            let document = Self.documentHTML(title: title, html: html, preferences: preferences)
            webView.loadHTMLString(document, baseURL: baseURL)
        }
        context.coordinator.applyFontSize(to: webView)
    }

    static func documentHTML(title: String, html: String, preferences: ReaderFontPreferences) -> String {
        var fontFaces = preferences.choice == .serif ? ReaderFonts.fontFaceCSS : ""
        let hasCode = html.range(of: "<code", options: .caseInsensitive) != nil
            || html.range(of: "<pre", options: .caseInsensitive) != nil
        if hasCode || preferences.choice == .mono {
            fontFaces += ReaderFonts.codeFontFaceCSS
        }
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title>\(title.escapedForHTML)</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.css">
        <style>
        \(fontFaces)
        :root {
          color-scheme: light dark;
          --reader-font-size: \(cssFontSize(for: preferences));
        }
        body {
          margin: 0;
          background: transparent;
          color: CanvasText;
          -webkit-text-size-adjust: 100%;
          overflow-wrap: break-word;
          word-break: break-word;
          font-family: \(preferences.cssFontFamily);
          font-size: var(--reader-font-size);
          line-height: \(preferences.cssLineHeight);
        }
        main {
          max-width: 820px;
          margin: 0 auto;
          padding: 8px 20px 24px;
        }
        h1, h2, h3, h4, h5, h6 {
          font-family: \(preferences.cssFontFamily) !important;
          line-height: 1.18;
          margin: 1.45em 0 0.45em;
          font-weight: 720;
        }
        h1 { font-size: 2.05em; margin-top: 0.2em; }
        h2 { font-size: 1.45em; }
        h3 { font-size: 1.18em; }
        p, ul, ol, blockquote, pre, figure { margin: 0 0 1.05em; }
        main * { max-width: 100%; box-sizing: border-box; }
        main article[style], main section[style], main div[style],
        main p[style], main figure[style], main img[style], main video[style] {
          position: static !important;
          transform: none !important;
          inset: auto !important;
        }
        ul, ol { padding-left: 1.45em; }
        li { margin: 0.32em 0; }
        a { color: color-mix(in srgb, CanvasText 58%, transparent); text-decoration: none; overflow-wrap: anywhere; word-break: break-word; }
        code { overflow-wrap: anywhere; }
        blockquote {
          border-left: 3px solid color-mix(in srgb, CanvasText 24%, transparent);
          padding-left: 1em;
          color: color-mix(in srgb, CanvasText 76%, transparent);
        }
        img, video {
          display: block !important;
          max-width: 100%;
          max-height: min(70vh, 560px);
          width: auto !important;
          height: auto !important;
          object-fit: contain;
          border-radius: 8px;
        }
        figure img { display: block; margin: 0 auto; }
        pre, pre *, code, code *, kbd, samp {
          font-family: \(preferences.cssCodeFontFamily) !important;
        }
        pre, code, kbd, samp { font-size: 0.92em; }
        pre {
          overflow: auto;
          padding: 14px 16px;
          border-radius: 8px;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          line-height: 1.5;
        }
        code {
          background: color-mix(in srgb, CanvasText 8%, transparent);
          padding: 0.12em 0.28em;
          border-radius: 4px;
        }
        pre code { background: transparent; padding: 0; font-size: 1em; }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); padding: 0.45em 0.6em; text-align: left; }
        .katex { font-size: 1.02em; color: CanvasText; }
        .katex-display { overflow-x: auto; overflow-y: hidden; padding: 0.15em 0 0.35em; margin: 1.2em 0; }
        .katex *, .katex-display * { max-width: none; box-sizing: content-box; }
        </style>
        </head>
        <body><main>\(html)</main>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/contrib/auto-render.min.js"></script>
        <script>
        (() => {
          function renderReaderMath() {
            const root = document.querySelector("main");
            if (!root || typeof renderMathInElement !== "function") return;
            renderMathInElement(root, {
              delimiters: [
                { left: "$$", right: "$$", display: true },
                { left: "\\\\[", right: "\\\\]", display: true },
                { left: "$", right: "$", display: false },
                { left: "\\\\(", right: "\\\\)", display: false }
              ],
              ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code"],
              throwOnError: false
            });
          }
          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", renderReaderMath);
          } else {
            renderReaderMath();
          }
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func cssFontSize(for preferences: ReaderFontPreferences) -> String {
        let scale = min(max(preferences.scale, ReaderFontPreferences.minScale), ReaderFontPreferences.maxScale)
        let size = preferences.articleSize * scale
        return String(format: "%.2fpx", locale: Locale(identifier: "en_US_POSIX"), size)
    }

    struct DocumentKey: Equatable {
        var title: String
        var html: String
        var baseURL: URL?
        var preferences: ReaderFontPreferences
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastDocumentKey: DocumentKey?
        var onScroll: ((CGFloat) -> Void)?
        var currentCSSFontSize: String?
        private var scrollObs: NSKeyValueObservation?

        /// Observe scroll via KVO rather than the scroll-view delegate — WKWebView
        /// can silently replace its scrollView's delegate, so KVO is reliable.
        /// Reports a top-normalized offset (0 at the very top).
        func observeScroll(of scrollView: UIScrollView) {
            scrollObs = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                self?.onScroll?(sv.contentOffset.y + sv.adjustedContentInset.top)
            }
        }

        deinit { scrollObs?.invalidate() }

        /// Let the initial document load; send any link tap to the system browser.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                decisionHandler(.cancel)
                Task { @MainActor in _ = await UIApplication.shared.open(url) }
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFontSize(to: webView)
        }

        func applyFontSize(to webView: WKWebView) {
            guard let currentCSSFontSize else { return }
            let js = "document.documentElement.style.setProperty('--reader-font-size', '\(currentCSSFontSize)')"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

extension String {
    var escapedForHTML: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

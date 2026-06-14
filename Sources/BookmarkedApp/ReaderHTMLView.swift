import SwiftUI
import WebKit

struct ReaderHTMLView: NSViewRepresentable {
    let title: String
    let html: String
    let baseURL: URL?
    let fontPreferences: ReaderFontPreferences
    let fontScale: Double
    var onEditSource: (() -> Void)?
    var onElementRemoved: ((String) -> Void)?

    static func documentHTML(
        title: String,
        html: String,
        fontPreferences: ReaderFontPreferences,
        fontScale: Double
    ) -> String {
        let displayHTML = html.preparedForLocalMediaDisplay()
        let hasCode = html.range(of: "<code", options: .caseInsensitive) != nil
            || html.range(of: "<pre", options: .caseInsensitive) != nil
        let codeFaces = hasCode ? BundledFonts.codeFontFaceCSS : ""
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title.escapedHTML)</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.css">
        <style>
        \(codeFaces)
        :root { color-scheme: light dark; }
        body {
          margin: 0;
          background: transparent;
          color: CanvasText;
          font-family: \(fontPreferences.cssArticleFontFamily);
          font-size: \(fontPreferences.cssArticleFontSize(scale: fontScale));
          line-height: \(fontPreferences.cssArticleLineHeight);
        }
        main {
          max-width: 820px;
          margin: 0 auto;
          padding: 38px 48px 80px;
        }
        h1, h2, h3, h4, h5, h6 {
          font-family: \(fontPreferences.cssHeadingFontFamily) !important;
          line-height: 1.18;
          margin: 1.45em 0 0.45em;
          font-weight: 720;
        }
        h1 { font-size: 2.05em; margin-top: 0.2em; }
        h2 { font-size: 1.45em; }
        h3 { font-size: 1.18em; }
        p, ul, ol, blockquote, pre, figure { margin: 0 0 1.05em; }
        main * {
          max-width: 100%;
          box-sizing: border-box;
        }
        main article[style],
        main section[style],
        main div[style],
        main p[style],
        main figure[style],
        main img[style],
        main video[style] {
          position: static !important;
          transform: none !important;
          inset: auto !important;
        }
        ul, ol { padding-left: 1.45em; }
        li { margin: 0.32em 0; }
        a { \(ReaderLinkStyle.cssDeclaration); }
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
          font-family: "Google Sans Code", \(fontPreferences.cssMonoFontFamily) !important;
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
        .katex-display {
          overflow-x: auto;
          overflow-y: hidden;
          padding: 0.15em 0 0.35em;
          margin: 1.2em 0;
        }
        .katex *,
        .katex-display * {
          max-width: none;
          box-sizing: content-box;
        }
        </style>
        </head>
        <body><main>\(displayHTML)</main>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/contrib/auto-render.min.js"></script>
        <script>
        (() => {
          const selector = "figure,picture,img,video,pre,blockquote,table,li,p,h1,h2,h3,h4,h5,h6,section,article";
          let pendingNode = null;

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

          function removableElement(target) {
            const main = document.querySelector("main");
            if (!main) return null;
            let node = target.closest(selector);
            if (!node || !main.contains(node)) return null;
            const mediaWrapper = node.closest("figure,picture");
            if (mediaWrapper && main.contains(mediaWrapper)) return mediaWrapper;
            return node;
          }

          document.addEventListener("contextmenu", event => {
            const node = removableElement(event.target);
            if (!node) return;
            window.getSelection()?.removeAllRanges();
            pendingNode = node;
          }, true);

          window.bookmarkedRemoveContextElement = () => {
            if (!pendingNode || !pendingNode.isConnected) return;
            pendingNode.remove();
            pendingNode = null;
            window.webkit.messageHandlers.readerEdit.postMessage(document.querySelector("main").innerHTML);
          };

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

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.userContentController.add(context.coordinator, name: "readerEdit")
        let view = ReaderWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.onEditSource = { context.coordinator.onEditSource?() }
        context.coordinator.webView = view
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.webView = nsView
        context.coordinator.onEditSource = onEditSource
        context.coordinator.onElementRemoved = onElementRemoved
        // Build the document at a fixed base scale so it does NOT change when the
        // reader font size changes — the size is applied with pageZoom instead,
        // which is instant and avoids reloading the whole WebView (and re-parsing
        // the embedded font) on every Cmd+/Cmd-.
        let document = Self.documentHTML(
            title: title,
            html: html,
            fontPreferences: fontPreferences,
            fontScale: 1
        )

        if context.coordinator.lastHTML != document {
            context.coordinator.lastHTML = document
            if document.contains("file://"),
               let documentURL = context.coordinator.writeLocalDocument(document) {
                nsView.loadFileURL(
                    documentURL,
                    allowingReadAccessTo: ReaderImageCache.shared.readAccessDirectory
                )
            } else {
                nsView.loadHTMLString(document, baseURL: baseURL)
            }
        }

        let zoom = max(0.5, CGFloat(fontScale))
        if abs(nsView.pageZoom - zoom) > 0.001 {
            nsView.pageZoom = zoom
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "readerEdit")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var lastHTML: String?
        var onEditSource: (() -> Void)?
        var onElementRemoved: ((String) -> Void)?
        weak var webView: WKWebView?
        private var observers: [NSObjectProtocol] = []
        private let documentURL = ReaderImageCache.shared.readAccessDirectory
            .appendingPathComponent("ReaderDocuments", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).html")

        override init() {
            super.init()
            observers.append(NotificationCenter.default.addObserver(
                forName: .bookmarkedScrollPostDown,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scroll(by: 1)
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .bookmarkedScrollPostUp,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scroll(by: -1)
            })
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            try? FileManager.default.removeItem(at: documentURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "readerEdit", let html = message.body as? String else { return }
            Task { @MainActor in
                self.onElementRemoved?(html)
            }
        }

        func writeLocalDocument(_ document: String) -> URL? {
            do {
                try FileManager.default.createDirectory(
                    at: documentURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try document.write(to: documentURL, atomically: true, encoding: .utf8)
                return documentURL
            } catch {
                return nil
            }
        }

        private func scroll(by direction: Int) {
            webView?.evaluateJavaScript("window.scrollBy({ top: \(420 * direction), left: 0, behavior: 'smooth' });")
        }
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class ReaderWebView: WKWebView {
    var onEditSource: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        evaluateJavaScript("window.getSelection && window.getSelection().removeAllRanges();")
        super.rightMouseDown(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        if menu.items.contains(where: { $0.action == #selector(editReaderSource) }) {
            return
        }

        if menu.items.isEmpty == false {
            menu.insertItem(.separator(), at: 0)
        }

        let remove = NSMenuItem(title: "Remove Element", action: #selector(removeContextElement), keyEquivalent: "")
        remove.target = self
        menu.insertItem(remove, at: 0)

        let edit = NSMenuItem(title: "Edit Reader Source", action: #selector(editReaderSource), keyEquivalent: "")
        edit.target = self
        menu.insertItem(edit, at: 0)
    }

    @objc private func removeContextElement() {
        evaluateJavaScript("window.bookmarkedRemoveContextElement && window.bookmarkedRemoveContextElement();")
    }

    @objc private func editReaderSource() {
        onEditSource?()
    }
}

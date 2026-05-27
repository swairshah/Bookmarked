import SwiftUI
import WebKit

struct ReaderHTMLView: NSViewRepresentable {
    let title: String
    let html: String
    let baseURL: URL?
    let fontChoice: ReaderFontChoice
    let fontPreferences: ReaderFontPreferences
    let fontScale: Double
    var onEditSource: (() -> Void)?
    var onElementRemoved: ((String) -> Void)?

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
        let document = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body {
          margin: 0;
          background: transparent;
          color: CanvasText;
          font-family: \(fontChoice.cssFontFamily(preferences: fontPreferences));
          font-size: \(fontChoice.cssFontSize(scale: fontScale));
          line-height: \(fontChoice.cssLineHeight);
        }
        main {
          max-width: 820px;
          margin: 0 auto;
          padding: 38px 48px 80px;
        }
        h1, h2, h3, h4, h5, h6 {
          font-family: \(fontPreferences.cssHeadingFontFamily);
          line-height: 1.18;
          margin: 1.45em 0 0.45em;
          font-weight: 720;
        }
        h1 { font-size: 2.05em; margin-top: 0.2em; }
        h2 { font-size: 1.45em; }
        h3 { font-size: 1.18em; }
        p, ul, ol, blockquote, pre, figure { margin: 0 0 1.05em; }
        ul, ol { padding-left: 1.45em; }
        li { margin: 0.32em 0; }
        a { color: #2563eb; text-decoration-thickness: 0.08em; text-underline-offset: 0.16em; }
        blockquote {
          border-left: 3px solid color-mix(in srgb, CanvasText 24%, transparent);
          padding-left: 1em;
          color: color-mix(in srgb, CanvasText 76%, transparent);
        }
        img, video {
          max-width: 100%;
          max-height: min(70vh, 560px);
          width: auto;
          height: auto;
          object-fit: contain;
          border-radius: 8px;
        }
        figure img { display: block; margin: 0 auto; }
        pre {
          overflow: auto;
          padding: 14px 16px;
          border-radius: 8px;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          font-size: 0.86em;
        }
        code {
          font-family: \(fontPreferences.cssMonoFontFamily);
          font-size: 0.88em;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          padding: 0.12em 0.28em;
          border-radius: 4px;
        }
        pre code { background: transparent; padding: 0; }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); padding: 0.45em 0.6em; text-align: left; }
        </style>
        </head>
        <body><main>\(html)</main>
        <script>
        (() => {
          const selector = "figure,picture,img,video,pre,blockquote,table,li,p,h1,h2,h3,h4,h5,h6,section,article";
          let pendingNode = null;

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
        })();
        </script>
        </body>
        </html>
        """

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

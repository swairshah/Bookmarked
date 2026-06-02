import SwiftUI
import WebKit

struct ReaderHTMLEditorCommand: Equatable {
    enum Action: Equatable {
        case none
        case removeSelected
        case stripImages
    }

    var id = 0
    var action: Action = .none

    func next(_ action: Action) -> ReaderHTMLEditorCommand {
        ReaderHTMLEditorCommand(id: id + 1, action: action)
    }
}

struct ReaderHTMLEditorView: NSViewRepresentable {
    @Binding var html: String
    let baseURL: URL?
    let fontChoice: ReaderFontChoice
    let fontPreferences: ReaderFontPreferences
    let fontScale: Double
    let command: ReaderHTMLEditorCommand

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.userContentController.add(context.coordinator, name: "readerHTMLEditor")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = nsView

        let styleKey = [
            fontChoice.cssFontFamily(preferences: fontPreferences),
            fontChoice.cssFontSize(scale: fontScale),
            fontChoice.cssLineHeight,
            fontPreferences.cssHeadingFontFamily,
            fontPreferences.cssMonoFontFamily
        ].joined(separator: "|")

        if context.coordinator.currentHTML == nil || context.coordinator.currentHTML != html || context.coordinator.styleKey != styleKey {
            context.coordinator.currentHTML = html
            context.coordinator.styleKey = styleKey
            let document = documentHTML(for: html.preparedForLocalMediaDisplay())
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

        guard command.id != context.coordinator.lastCommandID else { return }
        context.coordinator.lastCommandID = command.id
        switch command.action {
        case .none:
            break
        case .removeSelected:
            nsView.evaluateJavaScript("window.bookmarkedHTMLEditor?.removeSelected();")
        case .stripImages:
            nsView.evaluateJavaScript("window.bookmarkedHTMLEditor?.stripImages();")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "readerHTMLEditor")
    }

    private func documentHTML(for displayHTML: String) -> String {
        """
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
        .editor-shell {
          max-width: 860px;
          margin: 0 auto;
          padding: 30px 48px 90px;
        }
        .editor-note {
          margin: 0 0 20px;
          color: color-mix(in srgb, CanvasText 58%, transparent);
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          font-size: 12px;
          line-height: 1.45;
        }
        main {
          min-height: 70vh;
          outline: none;
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
        main * {
          max-width: 100%;
          box-sizing: border-box;
        }
        main [style] {
          position: static !important;
          transform: none !important;
          inset: auto !important;
        }
        main [data-bookmarked-selected] {
          outline: 2px solid #3b82f6;
          outline-offset: 4px;
          border-radius: 6px;
          background: color-mix(in srgb, #3b82f6 7%, transparent);
        }
        ul, ol { padding-left: 1.45em; }
        li { margin: 0.32em 0; }
        a { color: #2563eb; text-decoration-thickness: 0.08em; text-underline-offset: 0.16em; }
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
        figcaption {
          margin-top: 0.55em;
          color: color-mix(in srgb, CanvasText 62%, transparent);
          font-size: 0.86em;
          text-align: center;
        }
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
        <body>
        <div class="editor-shell">
          <p class="editor-note">Click into the rendered article to edit text. Click an image, paragraph, heading, quote, list item, or table to select that block for removal.</p>
          <main contenteditable="true" spellcheck="true">\(displayHTML)</main>
        </div>
        <script>
        (() => {
          const main = document.querySelector("main");
          const selectable = "figure,picture,img,video,pre,blockquote,table,li,p,h1,h2,h3,h4,h5,h6,section,article";
          let selectedElement = null;
          let syncTimer = null;

          function cleanedHTML() {
            clearSelectionMarker();
            return main.innerHTML;
          }

          function postChange() {
            window.webkit.messageHandlers.readerHTMLEditor.postMessage({
              type: "change",
              html: cleanedHTML()
            });
          }

          function scheduleChange() {
            window.clearTimeout(syncTimer);
            syncTimer = window.setTimeout(postChange, 120);
          }

          function clearSelectionMarker() {
            if (selectedElement) {
              selectedElement.removeAttribute("data-bookmarked-selected");
            }
          }

          function selectableElement(target) {
            let node = target.closest(selectable);
            if (!node || !main.contains(node)) return null;
            const mediaWrapper = node.closest("figure,picture");
            if (mediaWrapper && main.contains(mediaWrapper)) return mediaWrapper;
            return node;
          }

          function selectElement(node) {
            clearSelectionMarker();
            selectedElement = node;
            if (selectedElement) {
              selectedElement.setAttribute("data-bookmarked-selected", "true");
            }
          }

          main.addEventListener("click", event => {
            const node = selectableElement(event.target);
            if (node) selectElement(node);
          }, true);

          main.addEventListener("input", scheduleChange);
          main.addEventListener("paste", scheduleChange);
          main.addEventListener("blur", postChange);

          main.addEventListener("keydown", event => {
            if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
              postChange();
            }
            if ((event.key === "Backspace" || event.key === "Delete") && selectedElement && selectedElement.contains(event.target) === false) {
              event.preventDefault();
              window.bookmarkedHTMLEditor.removeSelected();
            }
          });

          window.bookmarkedHTMLEditor = {
            removeSelected() {
              if (!selectedElement || !selectedElement.isConnected) return;
              const next = selectedElement.nextElementSibling || selectedElement.previousElementSibling || main;
              selectedElement.remove();
              selectedElement = null;
              if (next && next !== main) selectElement(next);
              postChange();
            },
            stripImages() {
              main.querySelectorAll("figure, picture, img, video").forEach(node => node.remove());
              selectedElement = null;
              postChange();
            },
            sync: postChange
          };

          main.focus();
        })();
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: ReaderHTMLEditorView
        weak var webView: WKWebView?
        var currentHTML: String?
        var styleKey: String?
        var lastCommandID = 0
        private let documentURL = ReaderImageCache.shared.readAccessDirectory
            .appendingPathComponent("ReaderDocuments", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).html")

        init(parent: ReaderHTMLEditorView) {
            self.parent = parent
        }

        deinit {
            try? FileManager.default.removeItem(at: documentURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  body["type"] as? String == "change",
                  let html = body["html"] as? String else {
                return
            }
            currentHTML = html
            Task { @MainActor in
                self.parent.html = html
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
    }
}

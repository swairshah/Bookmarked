import SwiftUI
import WebKit

struct ReaderHTMLView: NSViewRepresentable {
    let title: String
    let html: String
    let baseURL: URL?
    let fontChoice: ReaderFontChoice

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
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
          font-family: \(fontChoice.cssFontFamily);
          font-size: \(fontChoice.cssFontSize);
          line-height: \(fontChoice.cssLineHeight);
        }
        main {
          max-width: 820px;
          margin: 0 auto;
          padding: 38px 48px 80px;
        }
        h1, h2, h3, h4, h5, h6 {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif;
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
        img, video { max-width: 100%; height: auto; border-radius: 8px; }
        pre {
          overflow: auto;
          padding: 14px 16px;
          border-radius: 8px;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          font-size: 0.86em;
        }
        code {
          font-family: "SF Mono", ui-monospace, Menlo, monospace;
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
        <body><main>\(html)</main></body>
        </html>
        """

        if context.coordinator.lastHTML != document {
            context.coordinator.lastHTML = document
            nsView.loadHTMLString(document, baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastHTML: String?
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

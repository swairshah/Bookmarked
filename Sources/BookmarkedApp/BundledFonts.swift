import AppKit
import CoreText

/// Registers the bundled "Google Sans Code" faces so the app can render code in
/// it without the user installing the font, and exposes them as @font-face CSS
/// for the WKWebView reader (whose web-content process can't see fonts that were
/// only registered in this process).
enum BundledFonts {
    static let codeFamily = "Google Sans Code"

    private struct Face { let file: String; let weight: Int; let italic: Bool }
    private static let codeFaces: [Face] = [
        Face(file: "GoogleSansCode-Regular", weight: 400, italic: false),
        Face(file: "GoogleSansCode-Italic", weight: 400, italic: true),
        Face(file: "GoogleSansCode-Bold", weight: 700, italic: false),
        Face(file: "GoogleSansCode-BoldItalic", weight: 700, italic: true)
    ]

    /// Registered off the main thread so it never delays launch (font cache
    /// warm-up can be slow). The WebView reader uses the embedded @font-face, so
    /// it doesn't depend on this completing first.
    static func register() {
        DispatchQueue.global(qos: .userInitiated).async {
            for face in codeFaces {
                guard let url = Bundle.module.url(forResource: face.file, withExtension: "ttf", subdirectory: "Resources") else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    static let codeFontFaceCSS: String = {
        var css = ""
        for face in codeFaces {
            guard let url = Bundle.module.url(forResource: face.file, withExtension: "ttf", subdirectory: "Resources"),
                  let data = try? Data(contentsOf: url) else { continue }
            let b64 = data.base64EncodedString()
            css += "@font-face{font-family:'\(codeFamily)';font-style:\(face.italic ? "italic" : "normal");font-weight:\(face.weight);font-display:swap;src:url(data:font/ttf;base64,\(b64)) format('truetype');}\n"
        }
        return css
    }()
}

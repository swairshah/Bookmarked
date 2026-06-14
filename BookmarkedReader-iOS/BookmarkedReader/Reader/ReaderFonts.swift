import UIKit
import CoreText

/// Bundled custom typefaces, shared with the macOS app:
/// - "Reader" — the serif used for article body/headings.
/// - "Google Sans Code" — the monospace used for code blocks and the Mono face.
///
/// We register the faces at launch (for the native SwiftUI reader) and also
/// expose them as @font-face CSS (for the WKWebView reader, whose separate
/// web-content process can't see process-registered fonts).
enum ReaderFonts {
    static let codeFamily = "Google Sans Code"
    static let codeRegularName = "GoogleSansCode-Regular"
    static let codeBoldName = "GoogleSansCode-Bold"

#if READER_FONTS
    // Local / personal builds (READER_FONTS defined): the licensed "Reader"
    // serif, bundled and registered as faces. Trial-licensed — never shipped.
    static let serifFamily = "Reader"
    static let regularName = "Reader-Regular"
    static let boldName = "Reader-Bold"

    private static let serifFaces: [Face] = [
        Face("Reader-Light", 300, false), Face("Reader-LightItalic", 300, true),
        Face("Reader-Regular", 400, false), Face("Reader-Italic", 400, true),
        Face("Reader-Medium", 500, false), Face("Reader-MediumItalic", 500, true),
        Face("Reader-Bold", 700, false), Face("Reader-BoldItalic", 700, true)
    ]
#else
    // Shipping builds: the built-in system "Iowan Old Style" serif. No bundled
    // font files, so `serifFaces` is empty (nothing to register or embed).
    static let serifFamily = "Iowan Old Style"
    static let regularName = "IowanOldStyle-Roman"
    static let boldName = "IowanOldStyle-Bold"

    private static let serifFaces: [Face] = []
#endif

    private static let codeFaces: [Face] = [
        Face("GoogleSansCode-Regular", 400, false), Face("GoogleSansCode-Italic", 400, true),
        Face("GoogleSansCode-Bold", 700, false), Face("GoogleSansCode-BoldItalic", 700, true)
    ]

    struct Face { let file: String; let weight: Int; let italic: Bool
        init(_ f: String, _ w: Int, _ i: Bool) { file = f; weight = w; italic = i } }

    /// Register every bundled face so `Font.custom` resolves them. Done off the
    /// main thread so it never delays launch; the WebView reader uses the
    /// embedded @font-face and doesn't depend on this finishing first.
    static func registerBundled() {
        DispatchQueue.global(qos: .userInitiated).async {
            for face in serifFaces + codeFaces {
                guard let url = Bundle.main.url(forResource: face.file, withExtension: "ttf") else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// @font-face for the serif body family (injected when the serif face is used).
    static let fontFaceCSS: String = faceCSS(serifFaces, family: serifFamily)

    /// @font-face for the code family (injected when the article has code, or the
    /// Mono face is selected).
    static let codeFontFaceCSS: String = faceCSS(codeFaces, family: codeFamily)

    private static func faceCSS(_ faces: [Face], family: String) -> String {
        var css = ""
        for face in faces {
            guard let url = Bundle.main.url(forResource: face.file, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url) else { continue }
            let b64 = data.base64EncodedString()
            css += "@font-face{font-family:'\(family)';font-style:\(face.italic ? "italic" : "normal");font-weight:\(face.weight);font-display:swap;src:url(data:font/ttf;base64,\(b64)) format('truetype');}\n"
        }
        return css
    }
}

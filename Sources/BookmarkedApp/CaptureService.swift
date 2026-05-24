import AppKit
import Foundation
import ApplicationServices

struct BrowserContext {
    var url: URL
    var title: String
    var browser: String
}

enum CaptureError: LocalizedError {
    case unsupportedFrontmostApp(String)
    case noURLFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFrontmostApp(let app):
            return "Could not capture a bookmark from \(app). Open a browser page or copy a URL first."
        case .noURLFound:
            return "No bookmarkable URL found in the frontmost app or clipboard."
        }
    }
}

enum CaptureService {
    static func promptForAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func currentContext() throws -> BrowserContext {
        if let browser = browserContextFromFrontmostApp() {
            return browser
        }
        if let pasteboard = NSPasteboard.general.string(forType: .string),
           let url = URL(string: pasteboard.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme != nil {
            return BrowserContext(url: url, title: url.host ?? url.absoluteString, browser: "Clipboard")
        }

        let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "the frontmost app"
        if isLikelyBrowserBundle(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") {
            throw CaptureError.noURLFound
        }
        throw CaptureError.unsupportedFrontmostApp(name)
    }

    private static func browserContextFromFrontmostApp() -> BrowserContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? ""

        if bundleId == "com.apple.Safari" {
            return runAppleScript(
                appName: "Safari",
                script: """
                tell application "Safari"
                    if (count of windows) > 0 then
                        set tabURL to URL of current tab of front window
                        set tabTitle to name of current tab of front window
                        return tabURL & "\n" & tabTitle
                    end if
                end tell
                """
            )
        }

        let chromiumApps: [String: String] = [
            "com.google.Chrome": "Google Chrome",
            "com.brave.Browser": "Brave Browser",
            "com.microsoft.edgemac": "Microsoft Edge",
            "com.vivaldi.Vivaldi": "Vivaldi",
            "com.operasoftware.Opera": "Opera",
            "company.thebrowser.Browser": "Arc"
        ]

        guard let scriptName = chromiumApps[bundleId] ?? (isLikelyBrowserBundle(bundleId) ? appName : nil) else {
            return nil
        }

        return runAppleScript(
            appName: scriptName,
            script: """
            tell application "\(scriptName)"
                if (count of windows) > 0 then
                    set tabURL to URL of active tab of front window
                    set tabTitle to title of active tab of front window
                    return tabURL & "\n" & tabTitle
                end if
            end tell
            """
        )
    }

    private static func runAppleScript(appName: String, script: String) -> BrowserContext? {
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        guard error == nil, let value = result.stringValue else { return nil }
        let parts = value.components(separatedBy: "\n")
        guard let rawURL = parts.first, let url = URL(string: rawURL), url.scheme != nil else { return nil }
        let title = parts.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserContext(url: url, title: title.isEmpty ? (url.host ?? rawURL) : title, browser: appName)
    }

    private static func isLikelyBrowserBundle(_ bundleId: String) -> Bool {
        bundleId.contains("Chrome")
            || bundleId.contains("Safari")
            || bundleId.contains("Browser")
            || bundleId.contains("firefox")
            || bundleId.contains("edgemac")
            || bundleId.contains("Vivaldi")
            || bundleId.contains("Opera")
    }
}

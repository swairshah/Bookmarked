import SwiftUI
import AppKit
import Combine
import Carbon
import BookmarkedClient

@main
struct BookmarkedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = BookmarkStore.shared
    @StateObject private var settings = BookmarkedSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            MenuBarLabel(flashToken: store.flashToken)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    MainWindowController.shared.showSettingsTab()
                }
                .keyboardShortcut(
                    settings.shortcut(for: .openSettings).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .openSettings).modifiers.eventModifiers
                )
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Reader Edits") {
                    saveReaderEditAction?()
                }
                .keyboardShortcut(
                    settings.shortcut(for: .saveReaderEdits).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .saveReaderEdits).modifiers.eventModifiers
                )
                .disabled(saveReaderEditAction == nil)
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    toggleSidebarAction?()
                }
                .keyboardShortcut(
                    settings.shortcut(for: .toggleSidebar).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .toggleSidebar).modifiers.eventModifiers
                )

                Button("Toggle Compact Header") {
                    NotificationCenter.default.post(name: .bookmarkedToggleCompactDetailHeader, object: nil)
                }

                Divider()

                Button("Previous Bookmark") {
                    NotificationCenter.default.post(name: .bookmarkedSelectPreviousItem, object: nil)
                }
                .keyboardShortcut(
                    settings.shortcut(for: .previousBookmark).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .previousBookmark).modifiers.eventModifiers
                )

                Button("Next Bookmark") {
                    NotificationCenter.default.post(name: .bookmarkedSelectNextItem, object: nil)
                }
                .keyboardShortcut(
                    settings.shortcut(for: .nextBookmark).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .nextBookmark).modifiers.eventModifiers
                )

                Divider()

                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .bookmarkedSelectPreviousPreviewTab, object: nil)
                }
                .keyboardShortcut(
                    settings.shortcut(for: .previousPreviewTab).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .previousPreviewTab).modifiers.eventModifiers
                )

                Button("Next Tab") {
                    NotificationCenter.default.post(name: .bookmarkedSelectNextPreviewTab, object: nil)
                }
                .keyboardShortcut(
                    settings.shortcut(for: .nextPreviewTab).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .nextPreviewTab).modifiers.eventModifiers
                )

                Divider()

                Button("Web Back") {
                    NotificationCenter.default.post(name: .bookmarkedNavigateWebBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Web Forward") {
                    NotificationCenter.default.post(name: .bookmarkedNavigateWebForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command])

                Divider()

                Button("Increase Font Size") {
                    NotificationCenter.default.post(name: .bookmarkedAdjustPreviewFontSize, object: nil, userInfo: ["delta": 1.0])
                }
                .keyboardShortcut(
                    settings.shortcut(for: .increaseFontSize).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .increaseFontSize).modifiers.eventModifiers
                )

                Button("Decrease Font Size") {
                    NotificationCenter.default.post(name: .bookmarkedAdjustPreviewFontSize, object: nil, userInfo: ["delta": -1.0])
                }
                .keyboardShortcut(
                    settings.shortcut(for: .decreaseFontSize).keyEquivalentValue,
                    modifiers: settings.shortcut(for: .decreaseFontSize).modifiers.eventModifiers
                )

            }
        }

        Settings {
            GlobalSettingsView(settings: settings)
        }
    }

    @FocusedValue(\.toggleSidebarAction) private var toggleSidebarAction
    @FocusedValue(\.saveReaderEditAction) private var saveReaderEditAction
    @FocusedValue(\.increaseReaderFontAction) private var increaseReaderFontAction
    @FocusedValue(\.decreaseReaderFontAction) private var decreaseReaderFontAction
}

private struct ToggleSidebarActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SaveReaderEditActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct IncreaseReaderFontActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DecreaseReaderFontActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var toggleSidebarAction: (() -> Void)? {
        get { self[ToggleSidebarActionKey.self] }
        set { self[ToggleSidebarActionKey.self] = newValue }
    }

    var saveReaderEditAction: (() -> Void)? {
        get { self[SaveReaderEditActionKey.self] }
        set { self[SaveReaderEditActionKey.self] = newValue }
    }

    var increaseReaderFontAction: (() -> Void)? {
        get { self[IncreaseReaderFontActionKey.self] }
        set { self[IncreaseReaderFontActionKey.self] = newValue }
    }

    var decreaseReaderFontAction: (() -> Void)? {
        get { self[DecreaseReaderFontActionKey.self] }
        set { self[DecreaseReaderFontActionKey.self] = newValue }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyManager: HotKeyManager?
    private var broker: BookmarkedBroker?
    private var peerSync: PeerSync?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStart = Date()
        func mark(_ label: String) {
            NSLog("Bookmarked startup: \(label) at +\(Int(Date().timeIntervalSince(launchStart) * 1000)) ms")
        }

        NSApp.setActivationPolicy(.accessory)
        BundledFonts.register()
        mark("fonts kicked off")
        CaptureService.promptForAccessibilityIfNeeded()
        mark("accessibility checked")
        registerAppURLHandler()

        do {
            broker = try BookmarkedBroker(port: BookmarkedDefaults.brokerPort, store: BookmarkStore.shared)
            broker?.start()
        } catch {
            NSLog("Bookmarked broker: could not start: \(error)")
        }
        mark("store loaded + broker started")

        hotKeyManager = HotKeyManager {
            Task { @MainActor in
                BookmarkStore.shared.captureFrontmostContext(openWindowAfterCapture: false)
            }
        }
        registerCaptureHotKey()
        BookmarkedSettings.shared.$shortcutOverrides
            .sink { [weak self] _ in
                self?.registerCaptureHotKey()
            }
            .store(in: &cancellables)
        mark("hotkeys registered")

        peerSync = PeerSync(store: BookmarkStore.shared)
        peerSync?.start()

        DispatchQueue.main.async {
            MainWindowController.shared.show()
            mark("main window shown")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            urls.forEach(handleAppURL)
        }
    }

    @MainActor
    private func registerCaptureHotKey() {
        let shortcut = BookmarkedSettings.shared.shortcut(for: .captureCurrentPage)
        hotKeyManager?.register(shortcut: shortcut)
    }

    private func registerAppURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: rawURL) else {
            return
        }

        Task { @MainActor in
            handleAppURL(url)
        }
    }

    @MainActor
    private func handleAppURL(_ url: URL) {
        guard let idOrPrefix = BookmarkedDeepLink.idOrPrefix(from: url) else { return }

        guard let item = BookmarkStore.shared.resolveItem(idOrPrefix: idOrPrefix) else {
            BookmarkStore.shared.statusMessage = "Bookmark not found for app link"
            MainWindowController.shared.show()
            return
        }

        MainWindowController.shared.show(select: item.id)
    }
}

struct MenuBarLabel: View {
    let flashToken: Int
    @State private var animationFrame = 0

    var body: some View {
        iconImage
            .id(animationFrame)
        .frame(width: 30, height: 22)
        .accessibilityLabel("Bookmarked")
        .onChange(of: flashToken) { _ in
            playBookmarkAnimation()
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let image = Self.iconFrames[safe: animationFrame] ?? Self.iconFrames.first {
            Image(nsImage: image)
                .renderingMode(.template)
        } else {
            Image(systemName: "bookmark")
                .font(.system(size: 16, weight: .medium))
                .imageScale(.medium)
        }
    }

    private static let iconFrames: [NSImage] = {
        ["menubar", "menubar-frame-1", "menubar-frame-2", "menubar-frame-3", "menubar-frame-4", "menubar-frame-5"].compactMap { name in
            guard let image = loadRetinaImage(
                name: name,
                name2x: "\(name)@2x",
                pointSize: NSSize(width: 22, height: 22)
            ) else {
                return nil
            }
            image.isTemplate = true
            return image
        }
    }()

    private func playBookmarkAnimation() {
        let runFrames = [1, 2, 3, 4, 5, 5, 0]
        for (index, frame) in runFrames.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.18) {
                animationFrame = frame
            }
        }
    }

    private static func loadRetinaImage(name: String, name2x: String, pointSize: NSSize) -> NSImage? {
        guard let url1x = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
              let rep1x = NSBitmapImageRep(data: (try? Data(contentsOf: url1x)) ?? Data()) else {
            return nil
        }
        rep1x.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep1x)
        if let url2x = Bundle.module.url(forResource: name2x, withExtension: "png", subdirectory: "Resources"),
           let rep2x = NSBitmapImageRep(data: (try? Data(contentsOf: url2x)) ?? Data()) {
            rep2x.size = pointSize
            image.addRepresentation(rep2x)
        }
        return image
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

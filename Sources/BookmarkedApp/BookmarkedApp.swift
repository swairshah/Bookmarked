import SwiftUI
import AppKit
import BookmarkedClient

@main
struct BookmarkedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = BookmarkStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            MenuBarLabel(flashToken: store.flashToken)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Reader Edits") {
                    saveReaderEditAction?()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(saveReaderEditAction == nil)
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    toggleSidebarAction?()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Toggle Compact Header") {
                    NotificationCenter.default.post(name: .bookmarkedToggleCompactDetailHeader, object: nil)
                }

                Divider()

                Button("Previous Bookmark") {
                    NotificationCenter.default.post(name: .bookmarkedSelectPreviousItem, object: nil)
                }
                .keyboardShortcut("k", modifiers: .control)

                Button("Next Bookmark") {
                    NotificationCenter.default.post(name: .bookmarkedSelectNextItem, object: nil)
                }
                .keyboardShortcut("j", modifiers: .control)

                Divider()

                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .bookmarkedSelectPreviousPreviewTab, object: nil)
                }
                .keyboardShortcut(",", modifiers: .control)

                Button("Next Tab") {
                    NotificationCenter.default.post(name: .bookmarkedSelectNextPreviewTab, object: nil)
                }
                .keyboardShortcut(".", modifiers: .control)

                Divider()

                Button("Increase Font Size") {
                    increaseReaderFontAction?()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    decreaseReaderFontAction?()
                }
                .keyboardShortcut("-", modifiers: .command)
            }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CaptureService.promptForAccessibilityIfNeeded()

        do {
            broker = try BookmarkedBroker(port: BookmarkedDefaults.brokerPort, store: BookmarkStore.shared)
            broker?.start()
        } catch {
            NSLog("Bookmarked broker: could not start: \(error)")
        }

        hotKeyManager = HotKeyManager {
            Task { @MainActor in
                BookmarkStore.shared.captureFrontmostContext(openWindowAfterCapture: false)
            }
        }
        hotKeyManager?.register()

        DispatchQueue.main.async {
            MainWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }
}

struct MenuBarLabel: View {
    let flashToken: Int
    @State private var flashPhase = false

    var body: some View {
        Group {
            if let image = flashPhase ? Self.flashIcon : Self.icon {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .accessibilityLabel("Bookmarked")
            } else {
                Image(systemName: "bookmark")
                    .font(.system(size: 16, weight: .medium))
                    .imageScale(.medium)
                    .accessibilityLabel("Bookmarked")
            }
        }
        .onChange(of: flashToken) { _ in
            flashPhase = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                flashPhase = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                flashPhase = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                flashPhase = false
            }
        }
    }

    private static let icon: NSImage? = {
        guard let image = loadRetinaImage(
            name: "menubar",
            name2x: "menubar@2x",
            pointSize: NSSize(width: 18, height: 18)
        ) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    private static let flashIcon: NSImage? = {
        guard let image = loadRetinaImage(
            name: "menubar-flash",
            name2x: "menubar-flash@2x",
            pointSize: NSSize(width: 18, height: 18)
        ) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

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

import AppKit
import Carbon
import SwiftUI

@MainActor
final class MainWindowController: ObservableObject {
    static let shared = MainWindowController()

    @Published var selection: UUID?
    @Published var isFullScreen = false
    @Published private(set) var settingsTabRequestID = 0

    private var window: NSWindow?
    private var delegate: WindowDelegate?

    private init() {}

    func show(select id: UUID? = nil) {
        if let id { selection = id }

        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = MainWindowView(store: BookmarkStore.shared, controller: self)
        let window = BookmarkedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Bookmarked"
        window.minSize = NSSize(width: 860, height: 560)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()

        let delegate = WindowDelegate(onClose: { [weak self] in
            self?.window = nil
            self?.delegate = nil
            self?.isFullScreen = false
            NSApp.setActivationPolicy(.accessory)
        }, onFullScreenChange: { [weak self] isFullScreen in
            self?.isFullScreen = isFullScreen
        })
        window.delegate = delegate
        self.delegate = delegate
        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleZoom() {
        guard let window else { return }
        window.zoom(nil)
    }

    func showSettingsTab() {
        show()
        settingsTabRequestID += 1
    }
}

private final class BookmarkedWindow: NSWindow {
    private let titlebarHitHeight: CGFloat = 52

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           handleConfiguredShortcut(event) {
            return
        }

        if event.type == .leftMouseDown,
           event.clickCount == 2,
           isInTitlebarChrome(event.locationInWindow) {
            zoom(nil)
            return
        }

        super.sendEvent(event)
    }

    override func noResponder(for eventSelector: Selector) {
        guard eventSelector != #selector(NSResponder.keyDown(with:)) else { return }
        super.noResponder(for: eventSelector)
    }

    private func handleConfiguredShortcut(_ event: NSEvent) -> Bool {
        guard let action = BookmarkedSettings.shared.action(matching: event) else { return false }

        switch action {
        case .captureCurrentPage:
            BookmarkStore.shared.captureFrontmostContext(openWindowAfterCapture: false)
        case .openSettings:
            MainWindowController.shared.showSettingsTab()
        case .saveReaderEdits:
            NotificationCenter.default.post(name: .bookmarkedSaveReaderEdits, object: nil)
        case .toggleSidebar:
            NotificationCenter.default.post(name: .bookmarkedToggleSidebar, object: nil)
        case .focusSearch:
            NotificationCenter.default.post(name: .bookmarkedToggleSearchFocus, object: nil)
        case .toggleCompactHeader:
            guard !isEditingText(in: firstResponder) else { return false }
            NotificationCenter.default.post(name: .bookmarkedToggleCompactDetailHeader, object: nil)
        case .previousBookmark:
            NotificationCenter.default.post(name: .bookmarkedSelectPreviousItem, object: nil)
        case .nextBookmark:
            NotificationCenter.default.post(name: .bookmarkedSelectNextItem, object: nil)
        case .previousPreviewTab:
            NotificationCenter.default.post(name: .bookmarkedSelectPreviousPreviewTab, object: nil)
        case .nextPreviewTab:
            NotificationCenter.default.post(name: .bookmarkedSelectNextPreviewTab, object: nil)
        case .increaseFontSize:
            NotificationCenter.default.post(name: .bookmarkedAdjustPreviewFontSize, object: nil, userInfo: ["delta": 1.0])
        case .decreaseFontSize:
            NotificationCenter.default.post(name: .bookmarkedAdjustPreviewFontSize, object: nil, userInfo: ["delta": -1.0])
        case .scrollPostUp:
            guard !isEditingText(in: firstResponder) else { return false }
            NotificationCenter.default.post(name: .bookmarkedScrollPostUp, object: nil)
        case .scrollPostDown:
            guard !isEditingText(in: firstResponder) else { return false }
            NotificationCenter.default.post(name: .bookmarkedScrollPostDown, object: nil)
        case .editNotes:
            guard !isEditingText(in: firstResponder) else { return false }
            NotificationCenter.default.post(name: .bookmarkedFocusNoteEditor, object: nil)
        }

        return true
    }

    private func isEditingText(in responder: NSResponder?) -> Bool {
        var current = responder
        while let responder = current {
            if let textView = responder as? NSTextView {
                return textView.isEditable
            }
            if let textField = responder as? NSTextField {
                return textField.isEditable
            }
            current = responder.nextResponder
        }
        return false
    }

    private func isInTitlebarChrome(_ point: NSPoint) -> Bool {
        guard point.y >= frame.height - titlebarHitHeight else { return false }
        return !standardButtonFrames.contains { $0.insetBy(dx: -8, dy: -8).contains(point) }
    }

    private var standardButtonFrames: [NSRect] {
        [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton)
        ]
        .compactMap { button in
            guard let button else { return nil }
            return button.convert(button.bounds, to: nil)
        }
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    let onFullScreenChange: (Bool) -> Void

    init(onClose: @escaping () -> Void, onFullScreenChange: @escaping (Bool) -> Void) {
        self.onClose = onClose
        self.onFullScreenChange = onFullScreenChange
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        onFullScreenChange(true)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        onFullScreenChange(false)
    }
}

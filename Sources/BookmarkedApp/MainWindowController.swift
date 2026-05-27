import AppKit
import Carbon
import SwiftUI

@MainActor
final class MainWindowController: ObservableObject {
    static let shared = MainWindowController()

    @Published var selection: UUID?
    @Published var isFullScreen = false

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
}

private final class BookmarkedWindow: NSWindow {
    private let titlebarHitHeight: CGFloat = 52

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           handleSearchFocusToggleKey(event) || handleCompactHeaderToggleKey(event) || handlePostScrollKey(event) {
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

    private func handleSearchFocusToggleKey(_ event: NSEvent) -> Bool {
        let meaningfulModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard meaningfulModifiers == .control else { return false }
        guard event.keyCode == UInt16(kVK_ANSI_F) else { return false }

        NotificationCenter.default.post(name: .bookmarkedToggleSearchFocus, object: nil)
        return true
    }

    private func handleCompactHeaderToggleKey(_ event: NSEvent) -> Bool {
        let meaningfulModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard meaningfulModifiers == .control else { return false }
        guard event.keyCode == UInt16(kVK_ANSI_M) else { return false }
        guard !isEditingText(in: firstResponder) else { return false }

        NotificationCenter.default.post(name: .bookmarkedToggleCompactDetailHeader, object: nil)
        return true
    }

    private func handlePostScrollKey(_ event: NSEvent) -> Bool {
        let meaningfulModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard meaningfulModifiers.isEmpty else { return false }
        guard !isEditingText(in: firstResponder) else { return false }

        switch event.charactersIgnoringModifiers {
        case "j":
            NotificationCenter.default.post(name: .bookmarkedScrollPostDown, object: nil)
            return true
        case "k":
            NotificationCenter.default.post(name: .bookmarkedScrollPostUp, object: nil)
            return true
        default:
            return false
        }
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

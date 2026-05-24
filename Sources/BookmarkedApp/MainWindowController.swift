import AppKit
import SwiftUI

@MainActor
final class MainWindowController: ObservableObject {
    static let shared = MainWindowController()

    @Published var selection: UUID?

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
            NSApp.setActivationPolicy(.accessory)
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
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           isInTitlebarChrome(event.locationInWindow) {
            zoom(nil)
            return
        }

        super.sendEvent(event)
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

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

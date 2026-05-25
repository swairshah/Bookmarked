import AppKit
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
        if event.type == .keyDown, handlePostScrollKey(event) {
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

    private func handlePostScrollKey(_ event: NSEvent) -> Bool {
        let meaningfulModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard meaningfulModifiers.isEmpty else { return false }
        guard !isEditingText(in: firstResponder) else { return false }

        switch event.charactersIgnoringModifiers {
        case "j":
            NotificationCenter.default.post(name: .bookmarkedScrollPostDown, object: nil)
            scrollDominantContentView(by: 1)
            return true
        case "k":
            NotificationCenter.default.post(name: .bookmarkedScrollPostUp, object: nil)
            scrollDominantContentView(by: -1)
            return true
        default:
            return false
        }
    }

    private func scrollDominantContentView(by direction: CGFloat) {
        guard let contentView else { return }
        let scrollViews = allScrollViews(in: contentView)
            .filter { !$0.isHidden && $0.window === self && $0.documentView != nil }
        guard let scrollView = scrollViews.max(by: { score($0) < score($1) }) else { return }

        let step: CGFloat = 420
        let clipView = scrollView.contentView
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - clipView.bounds.height)
        let nextY = min(max(clipView.bounds.origin.y + (step * direction), 0), maxY)
        clipView.animator().setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func allScrollViews(in view: NSView) -> [NSScrollView] {
        var result = view.subviews.flatMap { allScrollViews(in: $0) }
        if let scrollView = view as? NSScrollView {
            result.append(scrollView)
        }
        return result
    }

    private func score(_ scrollView: NSScrollView) -> CGFloat {
        guard let container = contentView else { return 0 }
        let frame = scrollView.convert(scrollView.bounds, to: container)
        let visibleArea = max(0, frame.width) * max(0, frame.height)
        let detailBias: CGFloat = frame.midX > container.bounds.midX ? 1.8 : 1.0
        return visibleArea * detailBias
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

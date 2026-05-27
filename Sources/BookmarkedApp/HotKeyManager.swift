import Carbon
import Foundation

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registeredShortcut: BookmarkedKeyboardShortcut?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register(shortcut: BookmarkedKeyboardShortcut) {
        unregisterHotKey()
        registeredShortcut = shortcut

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if handlerRef == nil {
            InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.action()
                    return noErr
                },
                1,
                &eventSpec,
                pointer,
                &handlerRef
            )
        }

        let hotKeyId = EventHotKeyID(signature: Self.fourCharCode("BKMK"), id: 1)
        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonModifiers,
            hotKeyId,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        unregisterHotKey()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}

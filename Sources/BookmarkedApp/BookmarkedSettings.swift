import AppKit
import Carbon
import Combine
import SwiftUI

enum BookmarkedPreferenceKeys {
    static let shortcuts = "shortcutOverrides"
    static let cacheReaderImages = "cacheReaderImages"
}

enum BookmarkedShortcutAction: String, CaseIterable, Identifiable {
    case captureCurrentPage
    case openSettings
    case saveReaderEdits
    case toggleSidebar
    case focusSearch
    case toggleCompactHeader
    case previousBookmark
    case nextBookmark
    case previousPreviewTab
    case nextPreviewTab
    case increaseFontSize
    case decreaseFontSize
    case scrollPostUp
    case scrollPostDown
    case editNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureCurrentPage: return "Capture Current Page"
        case .openSettings: return "Open Settings"
        case .saveReaderEdits: return "Save Reader Edits"
        case .toggleSidebar: return "Toggle Sidebar"
        case .focusSearch: return "Focus Search"
        case .toggleCompactHeader: return "Toggle Compact Header"
        case .previousBookmark: return "Previous Bookmark"
        case .nextBookmark: return "Next Bookmark"
        case .previousPreviewTab: return "Previous Tab"
        case .nextPreviewTab: return "Next Tab"
        case .increaseFontSize: return "Increase Font Size"
        case .decreaseFontSize: return "Decrease Font Size"
        case .scrollPostUp: return "Scroll Article Up"
        case .scrollPostDown: return "Scroll Article Down"
        case .editNotes: return "Edit Notes"
        }
    }

    var groupTitle: String {
        switch self {
        case .captureCurrentPage, .openSettings:
            return "Global"
        case .saveReaderEdits, .toggleSidebar, .focusSearch, .toggleCompactHeader:
            return "Window"
        case .previousBookmark, .nextBookmark, .previousPreviewTab, .nextPreviewTab:
            return "Navigation"
        case .increaseFontSize, .decreaseFontSize, .scrollPostUp, .scrollPostDown, .editNotes:
            return "Reader"
        }
    }

    var defaultShortcut: BookmarkedKeyboardShortcut {
        switch self {
        case .captureCurrentPage:
            return .init(keyCode: kVK_ANSI_M, keyEquivalent: "m", displayKey: "M", modifiers: [.command, .shift])
        case .openSettings:
            return .init(keyCode: kVK_ANSI_Comma, keyEquivalent: ",", displayKey: ",", modifiers: [.command])
        case .saveReaderEdits:
            return .init(keyCode: kVK_ANSI_S, keyEquivalent: "s", displayKey: "S", modifiers: [.command])
        case .toggleSidebar:
            return .init(keyCode: kVK_ANSI_B, keyEquivalent: "b", displayKey: "B", modifiers: [.command])
        case .focusSearch:
            return .init(keyCode: kVK_ANSI_F, keyEquivalent: "f", displayKey: "F", modifiers: [.control])
        case .toggleCompactHeader:
            return .init(keyCode: kVK_ANSI_M, keyEquivalent: "m", displayKey: "M", modifiers: [.control])
        case .previousBookmark:
            return .init(keyCode: kVK_ANSI_K, keyEquivalent: "k", displayKey: "K", modifiers: [.control])
        case .nextBookmark:
            return .init(keyCode: kVK_ANSI_J, keyEquivalent: "j", displayKey: "J", modifiers: [.control])
        case .previousPreviewTab:
            return .init(keyCode: kVK_ANSI_Comma, keyEquivalent: ",", displayKey: ",", modifiers: [.control])
        case .nextPreviewTab:
            return .init(keyCode: kVK_ANSI_Period, keyEquivalent: ".", displayKey: ".", modifiers: [.control])
        case .increaseFontSize:
            return .init(keyCode: kVK_ANSI_Equal, keyEquivalent: "+", displayKey: "+", modifiers: [.command])
        case .decreaseFontSize:
            return .init(keyCode: kVK_ANSI_Minus, keyEquivalent: "-", displayKey: "-", modifiers: [.command])
        case .scrollPostUp:
            return .init(keyCode: kVK_ANSI_K, keyEquivalent: "k", displayKey: "K", modifiers: [])
        case .scrollPostDown:
            return .init(keyCode: kVK_ANSI_J, keyEquivalent: "j", displayKey: "J", modifiers: [])
        case .editNotes:
            return .init(keyCode: kVK_Return, keyEquivalent: "return", displayKey: "Return", modifiers: [])
        }
    }
}

struct BookmarkedShortcutModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: Int

    static let command = BookmarkedShortcutModifiers(rawValue: 1 << 0)
    static let option = BookmarkedShortcutModifiers(rawValue: 1 << 1)
    static let control = BookmarkedShortcutModifiers(rawValue: 1 << 2)
    static let shift = BookmarkedShortcutModifiers(rawValue: 1 << 3)

    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if contains(.command) { modifiers.insert(SwiftUI.EventModifiers.command) }
        if contains(.option) { modifiers.insert(SwiftUI.EventModifiers.option) }
        if contains(.control) { modifiers.insert(SwiftUI.EventModifiers.control) }
        if contains(.shift) { modifiers.insert(SwiftUI.EventModifiers.shift) }
        return modifiers
    }

    var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }

    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if contains(.command) { modifiers |= UInt32(cmdKey) }
        if contains(.option) { modifiers |= UInt32(optionKey) }
        if contains(.control) { modifiers |= UInt32(controlKey) }
        if contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    var displayPrefix: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        return value
    }
}

struct BookmarkedKeyboardShortcut: Codable, Equatable, Sendable {
    var keyCode: Int
    var keyEquivalent: String
    var displayKey: String
    var modifiers: BookmarkedShortcutModifiers

    var keyEquivalentValue: KeyEquivalent {
        switch keyEquivalent {
        case "return": return .return
        case "tab": return .tab
        case "escape": return .escape
        case "delete": return .delete
        case "space": return KeyEquivalent(" ")
        default:
            return KeyEquivalent(keyEquivalent.first ?? " ")
        }
    }

    var displayText: String {
        modifiers.displayPrefix + displayKey
    }

    func matches(_ event: NSEvent) -> Bool {
        let meaningfulModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return meaningfulModifiers == modifiers.nsModifierFlags && Int(event.keyCode) == keyCode
    }

    static func from(event: NSEvent) -> BookmarkedKeyboardShortcut? {
        let modifiers = BookmarkedShortcutModifiers(eventFlags: event.modifierFlags)
        guard let key = KeyCapture(event: event) else { return nil }
        return BookmarkedKeyboardShortcut(
            keyCode: Int(event.keyCode),
            keyEquivalent: key.keyEquivalent,
            displayKey: key.displayKey,
            modifiers: modifiers
        )
    }

    private struct KeyCapture {
        var keyEquivalent: String
        var displayKey: String

        init?(event: NSEvent) {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                keyEquivalent = "return"
                displayKey = "Return"
            case kVK_Tab:
                keyEquivalent = "tab"
                displayKey = "Tab"
            case kVK_Escape:
                keyEquivalent = "escape"
                displayKey = "Esc"
            case kVK_Delete:
                keyEquivalent = "delete"
                displayKey = "Delete"
            case kVK_Space:
                keyEquivalent = "space"
                displayKey = "Space"
            default:
                let raw = event.charactersIgnoringModifiers ?? event.characters ?? ""
                guard let character = raw.trimmingCharacters(in: .newlines).first else { return nil }
                let value = String(character).lowercased()
                keyEquivalent = value
                displayKey = value.uppercased()
            }
        }
    }
}

extension BookmarkedShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: BookmarkedShortcutModifiers = []
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}

@MainActor
final class BookmarkedSettings: ObservableObject {
    static let shared = BookmarkedSettings()

    @Published private(set) var shortcutOverrides: [BookmarkedShortcutAction: BookmarkedKeyboardShortcut]
    @Published var cacheReaderImages: Bool {
        didSet {
            UserDefaults.standard.set(cacheReaderImages, forKey: BookmarkedPreferenceKeys.cacheReaderImages)
        }
    }

    private init() {
        shortcutOverrides = Self.loadShortcutOverrides()
        if let value = UserDefaults.standard.object(forKey: BookmarkedPreferenceKeys.cacheReaderImages) as? Bool {
            cacheReaderImages = value
        } else {
            cacheReaderImages = true
        }
    }

    func shortcut(for action: BookmarkedShortcutAction) -> BookmarkedKeyboardShortcut {
        shortcutOverrides[action] ?? action.defaultShortcut
    }

    func setShortcut(_ shortcut: BookmarkedKeyboardShortcut, for action: BookmarkedShortcutAction) {
        if shortcut == action.defaultShortcut {
            shortcutOverrides.removeValue(forKey: action)
        } else {
            shortcutOverrides[action] = shortcut
        }
        saveShortcutOverrides()
    }

    func resetShortcut(for action: BookmarkedShortcutAction) {
        shortcutOverrides.removeValue(forKey: action)
        saveShortcutOverrides()
    }

    func isOverridden(_ action: BookmarkedShortcutAction) -> Bool {
        shortcutOverrides[action] != nil
    }

    func action(matching event: NSEvent) -> BookmarkedShortcutAction? {
        BookmarkedShortcutAction.allCases.first { action in
            shortcut(for: action).matches(event)
        }
    }

    func conflictingActions(for action: BookmarkedShortcutAction) -> [BookmarkedShortcutAction] {
        let currentShortcut = shortcut(for: action)
        return BookmarkedShortcutAction.allCases.filter { other in
            other != action && shortcut(for: other) == currentShortcut
        }
    }

    private func saveShortcutOverrides() {
        let values = Dictionary(uniqueKeysWithValues: shortcutOverrides.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: BookmarkedPreferenceKeys.shortcuts)
        }
        objectWillChange.send()
    }

    private static func loadShortcutOverrides() -> [BookmarkedShortcutAction: BookmarkedKeyboardShortcut] {
        guard let data = UserDefaults.standard.data(forKey: BookmarkedPreferenceKeys.shortcuts),
              let values = try? JSONDecoder().decode([String: BookmarkedKeyboardShortcut].self, from: data) else {
            return [:]
        }

        return values.reduce(into: [:]) { result, pair in
            guard let action = BookmarkedShortcutAction(rawValue: pair.key) else { return }
            result[action] = pair.value
        }
    }
}

enum BookmarkedRuntimePreferences {
    static var cacheReaderImages: Bool {
        if let value = UserDefaults.standard.object(forKey: BookmarkedPreferenceKeys.cacheReaderImages) as? Bool {
            return value
        }
        return true
    }
}

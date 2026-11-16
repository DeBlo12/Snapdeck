import Foundation

/// A keyboard shortcut: a virtual key code plus modifier keys.
/// Modifiers use the Carbon bit values, which is what the hotkey API expects.
public struct KeyCombo: Codable, Equatable, Sendable {
    public static let command = 1 << 8
    public static let shift = 1 << 9
    public static let option = 1 << 11
    public static let control = 1 << 12

    public var keyCode: Int
    public var modifiers: Int
    /// How the key is shown, e.g. "←" or "K".
    public var label: String

    public init(keyCode: Int, modifiers: Int, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    /// Modifier symbols in the order macOS shows them.
    public var modifierSymbols: String {
        var s = ""
        if modifiers & KeyCombo.control != 0 { s += "⌃" }
        if modifiers & KeyCombo.option != 0 { s += "⌥" }
        if modifiers & KeyCombo.shift != 0 { s += "⇧" }
        if modifiers & KeyCombo.command != 0 { s += "⌘" }
        return s
    }

    public var display: String { modifierSymbols + label }

    /// A shortcut needs Control, Option or Command; Shift alone would hijack typing.
    public var hasRequiredModifier: Bool {
        modifiers & (KeyCombo.control | KeyCombo.option | KeyCombo.command) != 0
    }

    private static let namedKeys: [Int: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 76: "⌤", 49: "Space", 48: "⇥", 51: "⌫", 117: "⌦",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// The label for a pressed key: a fixed name for special keys, else its character.
    public static func label(keyCode: Int, characters: String?) -> String {
        if let name = namedKeys[keyCode] { return name }
        let text = (characters ?? "").uppercased()
        return text.isEmpty ? "Key \(keyCode)" : text
    }
}

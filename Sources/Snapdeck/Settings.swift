import AppKit
import Carbon.HIToolbox
import Combine

/// User preferences, stored in UserDefaults.
final class Settings: ObservableObject {
    /// The modifier keys held together with the arrow, digit and letter keys.
    enum Modifiers: String, CaseIterable, Identifiable {
        case controlOption = "⌃⌥"
        case controlOptionCommand = "⌃⌥⌘"
        case controlOptionShift = "⌃⌥⇧"
        case optionCommand = "⌥⌘"
        case controlCommand = "⌃⌘"

        var id: String { rawValue }

        var carbon: Int {
            switch self {
            case .controlOption: return controlKey | optionKey
            case .controlOptionCommand: return controlKey | optionKey | cmdKey
            case .controlOptionShift: return controlKey | optionKey | shiftKey
            case .optionCommand: return optionKey | cmdKey
            case .controlCommand: return controlKey | cmdKey
            }
        }

        var flags: NSEvent.ModifierFlags {
            switch self {
            case .controlOption: return [.control, .option]
            case .controlOptionCommand: return [.control, .option, .command]
            case .controlOptionShift: return [.control, .option, .shift]
            case .optionCommand: return [.option, .command]
            case .controlCommand: return [.control, .command]
            }
        }

        var name: String {
            switch self {
            case .controlOption: return "⌃⌥  Control + Option"
            case .controlOptionCommand: return "⌃⌥⌘  Control + Option + Command"
            case .controlOptionShift: return "⌃⌥⇧  Control + Option + Shift"
            case .optionCommand: return "⌥⌘  Option + Command"
            case .controlCommand: return "⌃⌘  Control + Command"
            }
        }
    }

    /// Every shortcut: what it does and the key pressed with the modifiers.
    static let shortcuts: [(action: String, key: String)] = [
        ("Left half, or move left", "←"),
        ("Right half, or move right", "→"),
        ("Top quarter, or maximise", "↑"),
        ("Bottom quarter, or restore", "↓"),
        ("Maximise", "↩"),
        ("Centre", "C"),
        ("Move window to layout zone 1–9", "1 … 9"),
        ("Arrange windows in active layout", "A"),
    ]

    private let defaults = UserDefaults.standard

    @Published var dragSnapEnabled: Bool {
        didSet { defaults.set(dragSnapEnabled, forKey: "dragSnapEnabled") }
    }

    /// Space between snapped windows, in points.
    @Published var gap: Double {
        didSet { defaults.set(gap, forKey: "gap") }
    }

    @Published var modifiers: Modifiers {
        didSet {
            defaults.set(modifiers.rawValue, forKey: "modifiers")
            onShortcutsChanged?()
        }
    }

    /// Shortcuts another app already owns.
    @Published var failedHotkeys: [String] = []

    var onShortcutsChanged: (() -> Void)?

    init() {
        dragSnapEnabled = defaults.object(forKey: "dragSnapEnabled") as? Bool ?? true
        gap = defaults.double(forKey: "gap")
        modifiers = defaults.string(forKey: "modifiers").flatMap(Modifiers.init(rawValue:)) ?? .controlOption
    }
}

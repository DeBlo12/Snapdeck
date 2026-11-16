import AppKit
import Carbon.HIToolbox
import Combine
import SnapdeckCore

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

    /// The actions whose shortcut can be changed individually.
    enum ShortcutAction: String, CaseIterable, Identifiable {
        case left, right, up, down, maximise, centre, arrange
        case displayLeft, displayRight, displayUp, displayDown

        /// The display actions add one more modifier key to the default ones.
        var movesToDisplay: Bool {
            switch self {
            case .displayLeft, .displayRight, .displayUp, .displayDown: return true
            default: return false
            }
        }

        var id: String { rawValue }

        var title: String {
            switch self {
            case .left: return "Left half, or move left"
            case .right: return "Right half, or move right"
            case .up: return "Top quarter, or maximise"
            case .down: return "Bottom quarter, or restore"
            case .maximise: return "Maximise"
            case .centre: return "Centre"
            case .arrange: return "Arrange windows in active layout"
            case .displayLeft: return "Move to the display on the left"
            case .displayRight: return "Move to the display on the right"
            case .displayUp: return "Move to the display above"
            case .displayDown: return "Move to the display below"
            }
        }

        var defaultKey: (code: Int, label: String) {
            switch self {
            case .left, .displayLeft: return (kVK_LeftArrow, "←")
            case .right, .displayRight: return (kVK_RightArrow, "→")
            case .up, .displayUp: return (kVK_UpArrow, "↑")
            case .down, .displayDown: return (kVK_DownArrow, "↓")
            case .maximise: return (kVK_Return, "↩")
            case .centre: return (kVK_ANSI_C, "C")
            case .arrange: return (kVK_ANSI_A, "A")
            }
        }
    }

    private let defaults = UserDefaults.standard

    @Published var dragSnapEnabled: Bool {
        didSet { defaults.set(dragSnapEnabled, forKey: "dragSnapEnabled") }
    }

    /// Holding Shift while dragging a window shows the active layout's zones to drop into.
    @Published var dragLayoutEnabled: Bool {
        didSet { defaults.set(dragLayoutEnabled, forKey: "dragLayoutEnabled") }
    }

    /// Bring the other snapped windows forward when one of them comes to the front.
    @Published var snapGroupsEnabled: Bool {
        didSet { defaults.set(snapGroupsEnabled, forKey: "snapGroupsEnabled") }
    }

    /// Record the arrangement per display configuration and restore it when displays change.
    @Published var displayProfilesEnabled: Bool {
        didSet { defaults.set(displayProfilesEnabled, forKey: "displayProfilesEnabled") }
    }

    /// Bundle identifiers of apps whose windows Snapdeck never moves.
    @Published var ignoredApps: [String] {
        didSet { defaults.set(ignoredApps, forKey: "ignoredApps") }
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

    /// Shortcuts the user changed, by action. Others use the default key and modifiers.
    @Published var customShortcuts: [String: KeyCombo] {
        didSet {
            defaults.set(try? JSONEncoder().encode(customShortcuts), forKey: "customShortcuts")
            onShortcutsChanged?()
        }
    }

    /// While a new shortcut is being recorded the global shortcuts are switched off,
    /// so that pressing an existing one records it instead of triggering it.
    @Published var isRecordingShortcut = false {
        didSet { onShortcutsChanged?() }
    }

    func combo(for action: ShortcutAction) -> KeyCombo {
        if let custom = customShortcuts[action.rawValue] { return custom }
        var mods = modifiers.carbon
        if action.movesToDisplay {
            // Command on top of the default modifiers, or Shift if Command is already one of them.
            mods |= mods & KeyCombo.command == 0 ? KeyCombo.command : KeyCombo.shift
        }
        return KeyCombo(keyCode: action.defaultKey.code, modifiers: mods, label: action.defaultKey.label)
    }

    /// Shortcuts another app already owns.
    @Published var failedHotkeys: [String] = []

    var onShortcutsChanged: (() -> Void)?

    init() {
        dragSnapEnabled = defaults.object(forKey: "dragSnapEnabled") as? Bool ?? true
        dragLayoutEnabled = defaults.object(forKey: "dragLayoutEnabled") as? Bool ?? true
        snapGroupsEnabled = defaults.object(forKey: "snapGroupsEnabled") as? Bool ?? true
        displayProfilesEnabled = defaults.bool(forKey: "displayProfilesEnabled")
        ignoredApps = defaults.stringArray(forKey: "ignoredApps") ?? []
        gap = defaults.double(forKey: "gap")
        customShortcuts = defaults.data(forKey: "customShortcuts")
            .flatMap { try? JSONDecoder().decode([String: KeyCombo].self, from: $0) } ?? [:]
        modifiers = defaults.string(forKey: "modifiers").flatMap(Modifiers.init(rawValue:)) ?? .controlOption
    }
}

extension KeyCombo {
    var flags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & KeyCombo.control != 0 { flags.insert(.control) }
        if modifiers & KeyCombo.option != 0 { flags.insert(.option) }
        if modifiers & KeyCombo.shift != 0 { flags.insert(.shift) }
        if modifiers & KeyCombo.command != 0 { flags.insert(.command) }
        return flags
    }

    /// Key equivalent for showing the shortcut in a menu; empty when it has none.
    var menuKey: String {
        switch keyCode {
        case kVK_LeftArrow: return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case kVK_RightArrow: return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case kVK_UpArrow: return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case kVK_DownArrow: return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case kVK_Return: return "\r"
        case kVK_Space: return " "
        default: return label.count == 1 ? label.lowercased() : ""
        }
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers = 0
        if flags.contains(.control) { modifiers |= KeyCombo.control }
        if flags.contains(.option) { modifiers |= KeyCombo.option }
        if flags.contains(.shift) { modifiers |= KeyCombo.shift }
        if flags.contains(.command) { modifiers |= KeyCombo.command }
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers,
                  label: KeyCombo.label(keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers))
    }
}

import AppKit
import Carbon.HIToolbox
import SnapdeckCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store()
    private let settings = Settings()
    private lazy var windowManager = WindowManager(store: store, settings: settings)
    private lazy var dragSnap = DragSnapController(windowManager: windowManager, settings: settings, store: store)
    private lazy var displayProfiles = DisplayProfileController(store: store, settings: settings,
                                                                windowManager: windowManager)
    /// Previews shown while hovering over menu items.
    private let menuOverlay = OverlayController()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1",
                                           accessibilityDescription: "Snapdeck")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        installMainMenu()
        if !Accessibility.isTrusted { Accessibility.requestTrust() }
        settings.onShortcutsChanged = { [weak self] in self?.registerHotkeys() }
        registerHotkeys()
        dragSnap.start()
        displayProfiles.start()

        // Snap groups: when the user switches to another app, bring the rest of the
        // arrangement forward with the window that now has focus.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.windowManager.raiseGroupOfFocusedWindow()
            }
        }

        if CommandLine.arguments.contains("--settings") { showSettings() }
        windowManager.confirmLaunch = { names in
            let alert = NSAlert()
            alert.messageText = "Open \(names.count == 1 ? "this app" : "these apps")?"
            alert.informativeText = "The setup includes apps that are not running:\n" + names.joined(separator: "\n")
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Skip")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn
        }

        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--trace"),
           CommandLine.arguments.indices.contains(index + 1) {
            runTrace(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        #endif
    }

    /// Opening the app again while it is running (Finder, Spotlight) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: Diagnostics (debug builds only)

    #if DEBUG
    /// `--trace <file>`: snaps the focused window left, up, right, down, writes what
    /// happened to the file, then puts the window back. For debugging on real windows.
    private func runTrace(to url: URL) {
        var lines: [String] = []
        func log(_ line: String) {
            lines.append(line)
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        let wm = windowManager
        wm.trace = log
        log("trusted=\(Accessibility.isTrusted) screens=\(Accessibility.screens())")

        var original: (AXUIElement, CGRect)?
        let steps: [Direction] = [.left, .up, .right, .down, .down]
        for (index, direction) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index) * 0.7) {
                if index == 0, let window = Accessibility.focusedWindow(), let frame = window.frame {
                    original = (window, frame)
                    log("app=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") start=\(frame)")
                }
                wm.snap(direction)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    log("  after \(direction): \(String(describing: original?.0.frame))")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(steps.count) * 0.7 + 0.5) {
            if let (window, frame) = original { window.setFrame(frame) }
            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            for entry in info where (entry[kCGWindowLayer as String] as? Int) == 0 {
                let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
                log("z: \(entry[kCGWindowOwnerName as String] ?? "?") \(String(describing: bounds))")
            }
            log("done")
            wm.trace = nil
        }
    }
    #endif

    // MARK: Hotkeys

    private func registerHotkeys() {
        let wm = windowManager
        var failed: [String] = []
        HotkeyManager.shared.unregisterAll()
        guard !settings.isRecordingShortcut else { return }

        let handlers: [Settings.ShortcutAction: () -> Void] = [
            .left: { wm.snap(.left) },
            .right: { wm.snap(.right) },
            .up: { wm.snap(.up) },
            .down: { wm.snap(.down) },
            .maximise: { wm.snapFocused(to: .full) },
            .centre: { wm.centerFocused() },
            .arrange: { wm.arrangeActiveLayout() },
            .displayLeft: { wm.moveFocusedToDisplay(.left) },
            .displayRight: { wm.moveFocusedToDisplay(.right) },
            .displayUp: { wm.moveFocusedToDisplay(.up) },
            .displayDown: { wm.moveFocusedToDisplay(.down) },
        ]
        for action in Settings.ShortcutAction.allCases {
            guard let handler = handlers[action] else { continue }
            let combo = settings.combo(for: action)
            if !HotkeyManager.shared.register(keyCode: combo.keyCode, modifiers: combo.modifiers, handler: handler) {
                failed.append(combo.display)
            }
        }

        // Digits 1...9 move the focused window into that zone of the active layout.
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let modifiers = settings.modifiers
        for (index, key) in digits.enumerated()
        where !HotkeyManager.shared.register(keyCode: key, modifiers: modifiers.carbon,
                                             handler: { wm.moveFocused(toLayoutZone: index) }) {
            failed.append("\(modifiers.rawValue)\(index + 1)")
        }
        settings.failedHotkeys = failed
    }

    // MARK: Settings window

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, store: store, windowManager: windowManager)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Snapdeck Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// A menu bar app shows no main menu, but its key equivalents still work while
    /// one of our windows is in front: ⌘, ⌘W ⌘Q and the text editing shortcuts.
    private func installMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(ActionItem("Settings…", key: ",", mods: .command) { [weak self] in self?.showSettings() })
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem(title: "Quit Snapdeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Submenus share this delegate for hover previews but are built with their parent.
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()
        let wm = windowManager
        let mods = settings.modifiers.flags

        if !Accessibility.isTrusted {
            menu.addItem(ActionItem("Grant Accessibility Access…") { Accessibility.openSystemSettings() })
            menu.addItem(.separator())
        }
        if let error = store.loadError {
            menu.addItem(disabled("⚠︎ \(error)"))
        }
        if !settings.failedHotkeys.isEmpty {
            menu.addItem(disabled("⚠︎ Shortcuts in use elsewhere: \(settings.failedHotkeys.joined(separator: " "))"))
        }

        // Snap
        func key(_ action: Settings.ShortcutAction) -> String { settings.combo(for: action).menuKey }
        func flags(_ action: Settings.ShortcutAction) -> NSEvent.ModifierFlags { settings.combo(for: action).flags }
        menu.addItem(ActionItem("Left", key: key(.left), mods: flags(.left),
                                preview: { wm.previewSnap(.left) }) { wm.snap(.left) })
        menu.addItem(ActionItem("Right", key: key(.right), mods: flags(.right),
                                preview: { wm.previewSnap(.right) }) { wm.snap(.right) })
        menu.addItem(ActionItem("Up / Maximise", key: key(.up), mods: flags(.up),
                                preview: { wm.previewSnap(.up) }) { wm.snap(.up) })
        menu.addItem(ActionItem("Down / Restore", key: key(.down), mods: flags(.down),
                                preview: { wm.previewSnap(.down) }) { wm.snap(.down) })
        menu.addItem(ActionItem("Maximise", key: key(.maximise), mods: flags(.maximise),
                                preview: { wm.previewSnapFocused(to: .full) }) { wm.snapFocused(to: .full) })
        menu.addItem(ActionItem("Centre", key: key(.centre), mods: flags(.centre),
                                preview: { wm.previewCenter() }) { wm.centerFocused() })
        if NSScreen.screens.count > 1 {
            let displayMenu = NSMenu()
            displayMenu.delegate = self
            let entries: [(String, Settings.ShortcutAction, Direction)] = [
                ("Left", .displayLeft, .left), ("Right", .displayRight, .right),
                ("Above", .displayUp, .up), ("Below", .displayDown, .down),
            ]
            for (title, action, direction) in entries {
                displayMenu.addItem(ActionItem(title, key: key(action), mods: flags(action),
                                               preview: { wm.previewMoveToDisplay(direction) }) {
                    wm.moveFocusedToDisplay(direction)
                })
            }
            let displayItem = ActionItem("Move to Display") {}
            displayItem.submenu = displayMenu
            menu.addItem(displayItem)
        }
        menu.addItem(.separator())

        // Layouts
        let active = store.activeLayout
        let layoutMenu = NSMenu()
        layoutMenu.delegate = self
        for layout in store.layouts {
            let item = ActionItem("\(layout.name)  (\(layout.zones.count) zones)",
                                  preview: { wm.previewLayout(layout) }) { [store] in
                store.setActiveLayout(layout)
            }
            item.state = layout.name == active?.name ? .on : .off
            layoutMenu.addItem(item)
        }
        let layoutItem = ActionItem("Layout: \(active?.name ?? "none")",
                                    preview: { active.map { wm.previewLayout($0) } ?? [] }) {}
        layoutItem.submenu = layoutMenu
        menu.addItem(layoutItem)

        if let active {
            let zoneMenu = NSMenu()
            zoneMenu.delegate = self
            for (index, zone) in active.zones.enumerated() {
                zoneMenu.addItem(ActionItem("Zone \(index + 1)", key: index < 9 ? "\(index + 1)" : "", mods: mods,
                                            preview: { wm.previewSnapFocused(to: zone) }) {
                    wm.snapFocused(to: zone)
                })
            }
            let zoneItem = ActionItem("Move Window to Zone", preview: { wm.previewLayout(active) }) {}
            zoneItem.submenu = zoneMenu
            menu.addItem(zoneItem)
        }
        menu.addItem(ActionItem("Arrange Windows in Layout", key: key(.arrange), mods: flags(.arrange),
                                preview: { wm.previewArrange() }) { wm.arrangeActiveLayout() })
        menu.addItem(.separator())

        // Setups
        menu.addItem(disabled("Saved Setups"))
        for setup in store.setups {
            menu.addItem(ActionItem("Restore “\(setup.name)”", preview: { wm.previewSetup(setup) }) {
                wm.restore(setup)
            })
        }
        menu.addItem(ActionItem("Save Current Setup…") { [weak self] in self?.saveSetup() })
        menu.addItem(.separator())

        // App
        menu.addItem(ActionItem("Settings…", key: ",", mods: .command) { [weak self] in self?.showSettings() })
        menu.addItem(ActionItem("Quit Snapdeck", key: "q", mods: .command) { NSApp.terminate(nil) })
    }

    /// Hovering over an item shows where its action would put things.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        let specs = (item as? ActionItem)?.preview?() ?? []
        if specs.isEmpty {
            // Moving within a submenu must not wipe the parent item's preview logic:
            // an item without a preview simply shows nothing.
            menuOverlay.hide()
        } else {
            menuOverlay.show(specs)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusItem.menu { menuOverlay.hide() }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func saveSetup() {
        // Capture first: showing the dialog changes which app is in front.
        let captured = windowManager.captureSetup(named: "")

        let alert = NSAlert()
        alert.messageText = "Save Current Setup"
        alert.informativeText = "\(captured.windows.count) windows will be remembered. "
            + "Saving under an existing name replaces that setup."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Name, e.g. Coding"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.save(WindowSetup(name: name, windows: captured.windows))
    }
}

/// A menu item that runs a closure and can describe what it would do.
final class ActionItem: NSMenuItem {
    /// Rectangles to show on screen while the item is highlighted.
    let preview: (() -> [OverlaySpec])?
    private let handler: () -> Void

    init(_ title: String, key: String = "", mods: NSEvent.ModifierFlags = [],
         preview: (() -> [OverlaySpec])? = nil, handler: @escaping () -> Void) {
        self.preview = preview
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = mods
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}

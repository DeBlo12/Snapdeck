import Combine
import Foundation
import SnapdeckCore

/// Loads and saves layouts and setups as JSON in ~/Library/Application Support/Snapdeck.
final class Store: ObservableObject {
    let directory: URL
    @Published private(set) var layouts: [Layout] = Layout.builtIn
    @Published private(set) var setups: [WindowSetup] = []
    /// Set when a config file could not be read; shown in the menu and settings.
    @Published private(set) var loadError: String?

    /// Automatically recorded arrangement per display configuration (see DisplayProfileController).
    @Published private(set) var displaySetups: [String: WindowSetup] = [:]
    private var displaySetupsURL: URL { directory.appendingPathComponent("display-setups.json") }

    var layoutsURL: URL { directory.appendingPathComponent("layouts.json") }
    private var setupsURL: URL { directory.appendingPathComponent("setups.json") }
    private let activeLayoutKey = "activeLayout"

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Snapdeck", isDirectory: true)
    }

    var activeLayout: Layout? {
        let name = UserDefaults.standard.string(forKey: activeLayoutKey)
        return layouts.first { $0.name == name } ?? layouts.first
    }

    func setActiveLayout(_ layout: Layout) {
        objectWillChange.send()
        UserDefaults.standard.set(layout.name, forKey: activeLayoutKey)
    }

    func load() {
        loadError = nil
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Only the user may read the config: setups list which apps are in use.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        // layouts.json is meant to be edited by hand; seed it with the built-ins.
        if !FileManager.default.fileExists(atPath: layoutsURL.path) {
            write(Layout.builtIn, to: layoutsURL)
        }
        for url in [layoutsURL, setupsURL, displaySetupsURL] where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        do {
            let loaded = try JSONDecoder().decode([Layout].self, from: Data(contentsOf: layoutsURL))
            let usable = loaded.compactMap { layout -> Layout? in
                let zones = layout.zones.filter(\.isValid)
                return zones.isEmpty ? nil : Layout(name: layout.name, zones: zones)
            }
            layouts = usable.isEmpty ? Layout.builtIn : usable
        } catch {
            layouts = Layout.builtIn
            loadError = "layouts.json could not be read"
        }

        if FileManager.default.fileExists(atPath: setupsURL.path) {
            do {
                let loaded = try JSONDecoder().decode([WindowSetup].self, from: Data(contentsOf: setupsURL))
                setups = loaded.map { WindowSetup(name: $0.name, windows: $0.windows.filter(\.isSane)) }
                // Rewrite so that files from early versions lose their plain window titles.
                write(setups, to: setupsURL)
            } catch {
                setups = []
                loadError = "setups.json could not be read"
            }
        }

        if let data = try? Data(contentsOf: displaySetupsURL),
           let loaded = try? JSONDecoder().decode([String: WindowSetup].self, from: data) {
            displaySetups = loaded.mapValues { WindowSetup(name: $0.name, windows: $0.windows.filter(\.isSane)) }
        }
    }

    func saveDisplaySetup(_ setup: WindowSetup, for key: String) {
        guard displaySetups[key] != setup else { return }
        displaySetups[key] = setup
        write(displaySetups, to: displaySetupsURL)
    }

    func clearDisplaySetups() {
        displaySetups = [:]
        try? FileManager.default.removeItem(at: displaySetupsURL)
    }

    /// Saves an edited layout. `originalName` is the layout it replaces, nil for a new one.
    /// A different layout that already has the new name is replaced too.
    func saveLayout(_ layout: Layout, replacing originalName: String?) {
        let wasActive = originalName != nil && activeLayout?.name == originalName
        var updated = layouts.filter { $0.name != layout.name || $0.name == originalName }
        if let index = updated.firstIndex(where: { $0.name == originalName }) {
            updated[index] = layout
        } else {
            updated.append(layout)
        }
        layouts = updated
        write(layouts, to: layoutsURL)
        if wasActive { setActiveLayout(layout) }
    }

    /// Deletes a layout. The last layout cannot be deleted.
    func deleteLayout(named name: String) {
        guard layouts.count > 1 else { return }
        layouts.removeAll { $0.name == name }
        write(layouts, to: layoutsURL)
        objectWillChange.send()
    }

    /// Adds a setup, replacing any existing one with the same name.
    func save(_ setup: WindowSetup) {
        setups.removeAll { $0.name == setup.name }
        setups.append(setup)
        write(setups, to: setupsURL)
    }

    func deleteSetup(named name: String) {
        setups.removeAll { $0.name == name }
        write(setups, to: setupsURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

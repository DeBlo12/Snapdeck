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

        // layouts.json is meant to be edited by hand; seed it with the built-ins.
        if !FileManager.default.fileExists(atPath: layoutsURL.path) {
            write(Layout.builtIn, to: layoutsURL)
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
                setups = try JSONDecoder().decode([WindowSetup].self, from: Data(contentsOf: setupsURL))
            } catch {
                setups = []
                loadError = "setups.json could not be read"
            }
        }
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
    }
}

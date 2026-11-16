import AppKit
import ServiceManagement
import SnapdeckCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: Store
    let windowManager: WindowManager

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(settings: settings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            LayoutsTab(store: store)
                .tabItem { Label("Layouts", systemImage: "rectangle.split.3x1") }
            SetupsTab(store: store, windowManager: windowManager)
                .tabItem { Label("Setups", systemImage: "macwindow.on.rectangle") }
        }
        .padding()
        .frame(width: 540, height: 440)
    }
}

// MARK: General

private struct GeneralTab: View {
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = Accessibility.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enable in
                        let service = SMAppService.mainApp
                        if enable { try? service.register() } else { try? service.unregister() }
                        launchAtLogin = service.status == .enabled
                    }
                ))
            }
            Section("Snapping") {
                Toggle("Snap windows dragged to a screen edge", isOn: $settings.dragSnapEnabled)
                HStack {
                    Text("Gap between windows")
                    Slider(value: $settings.gap, in: 0...24, step: 2)
                    Text("\(Int(settings.gap)) pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Section("Permission") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(trusted ? .green : .orange)
                    Text(trusted ? "Accessibility access granted" : "Accessibility access is needed to move windows")
                    Spacer()
                    if !trusted {
                        Button("Open System Settings") { Accessibility.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = Accessibility.isTrusted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = Accessibility.isTrusted
        }
    }
}

// MARK: Shortcuts

private struct ShortcutsTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Picker("Modifier keys", selection: $settings.modifiers) {
                    ForEach(Settings.Modifiers.allCases) { choice in
                        Text(choice.name).tag(choice)
                    }
                }
                if !settings.failedHotkeys.isEmpty {
                    Label("Already used by another app: \(settings.failedHotkeys.joined(separator: "  "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }
            Section("Shortcuts") {
                ForEach(Settings.shortcuts, id: \.action) { shortcut in
                    HStack {
                        Text(shortcut.action)
                        Spacer()
                        Text("\(settings.modifiers.rawValue) \(shortcut.key)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Layouts

private struct LayoutsTab: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The active layout is used by the zone shortcuts and by Arrange Windows.")
                .foregroundColor(.secondary)
            List(store.layouts, id: \.name) { layout in
                let isActive = layout.name == store.activeLayout?.name
                HStack(spacing: 12) {
                    LayoutThumbnail(layout: layout)
                    VStack(alignment: .leading) {
                        Text(layout.name)
                        Text("\(layout.zones.count) zones").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { store.setActiveLayout(layout) }
            }
            if let error = store.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
            }
            HStack {
                Text("Layouts are defined in layouts.json.").foregroundColor(.secondary)
                Spacer()
                Button("Edit layouts.json") { NSWorkspace.shared.open(store.layoutsURL) }
                Button("Reload") { store.load() }
            }
        }
        .padding()
    }
}

/// A miniature drawing of a layout's zones.
private struct LayoutThumbnail: View {
    let layout: SnapdeckCore.Layout

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(layout.zones.enumerated()), id: \.offset) { _, zone in
                let rect = zone.frame(in: CGRect(origin: .zero, size: geometry.size)).insetBy(dx: 1, dy: 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.65))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: 64, height: 40)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
    }
}

// MARK: Setups

private struct SetupsTab: View {
    @ObservedObject var store: Store
    let windowManager: WindowManager
    @State private var name = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A setup remembers where every open window is, so you can put them back later.")
                .foregroundColor(.secondary)
            HStack {
                TextField("Name, e.g. Coding", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save Current Setup", action: save)
                    .disabled(trimmedName.isEmpty)
            }
            List(store.setups, id: \.name) { setup in
                HStack {
                    VStack(alignment: .leading) {
                        Text(setup.name)
                        Text("\(setup.windows.count) windows").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Restore") { windowManager.restore(setup) }
                    Button("Delete", role: .destructive) { store.deleteSetup(named: setup.name) }
                }
            }
            Text("Saving under an existing name replaces that setup.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.save(windowManager.captureSetup(named: trimmedName))
        name = ""
    }
}

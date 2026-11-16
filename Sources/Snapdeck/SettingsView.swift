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
            SetupsTab(store: store, settings: settings, windowManager: windowManager)
                .tabItem { Label("Setups", systemImage: "macwindow.on.rectangle") }
        }
        .padding()
        .frame(width: 540, height: 500)
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
                Toggle("Hold Shift while dragging to drop into a layout zone", isOn: $settings.dragLayoutEnabled)
                Toggle("Bring snapped windows forward together", isOn: $settings.snapGroupsEnabled)
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

/// A layout being created or changed in the editor.
private struct LayoutDraft: Identifiable {
    let id = UUID()
    /// Name of the layout being replaced; nil for a new layout.
    let originalName: String?
    let layout: SnapdeckCore.Layout
}

private struct LayoutsTab: View {
    @ObservedObject var store: Store
    @State private var draft: LayoutDraft?

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
                    Button("Edit") { draft = LayoutDraft(originalName: layout.name, layout: layout) }
                    Button("Delete", role: .destructive) { store.deleteLayout(named: layout.name) }
                        .disabled(store.layouts.count <= 1)
                }
                .contentShape(Rectangle())
                .onTapGesture { store.setActiveLayout(layout) }
            }
            if let error = store.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
            }
            HStack {
                Button("New Layout…") {
                    draft = LayoutDraft(originalName: nil, layout: .init(name: "", zones: [.leftHalf, .rightHalf]))
                }
                Spacer()
                Button("Edit layouts.json") { NSWorkspace.shared.open(store.layoutsURL) }
                Button("Reload") { store.load() }
            }
        }
        .padding()
        .sheet(item: $draft) { draft in
            LayoutEditor(layout: draft.layout,
                         onSave: { edited in
                             store.saveLayout(edited, replacing: draft.originalName)
                             self.draft = nil
                         },
                         onCancel: { self.draft = nil })
        }
    }
}

/// Visual editor: select a zone, split it, drag its edges.
private struct LayoutEditor: View {
    @State var layout: SnapdeckCore.Layout
    let onSave: (SnapdeckCore.Layout) -> Void
    let onCancel: () -> Void
    @State private var selected: Int? = 0

    private var trimmedName: String { layout.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Layout name", text: $layout.name)
                .textFieldStyle(.roundedBorder)

            canvas
                .frame(width: 480, height: 300)

            HStack {
                Button("Split Side by Side") { split(sideBySide: true) }
                Button("Split Stacked") { split(sideBySide: false) }
                Button("Remove Zone", role: .destructive) {
                    if let index = selected, layout.removeZone(at: index) {
                        selected = min(index, layout.zones.count - 1)
                    }
                }
                .disabled(layout.zones.count <= 1)
                Spacer()
                if let index = selected, layout.zones.indices.contains(index) {
                    let zone = layout.zones[index]
                    Text("Zone \(index + 1): \(Int((zone.width * 100).rounded()))% × \(Int((zone.height * 100).rounded()))%")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .disabled(selected == nil)

            Text("Click a zone to select it, then drag its handles or split it. Zone numbers match the shortcuts.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var result = layout
                    result.name = trimmedName
                    onSave(result)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
    }

    private func split(sideBySide: Bool) {
        guard let index = selected else { return }
        layout.splitZone(at: index, sideBySide: sideBySide)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                ForEach(Array(layout.zones.enumerated()), id: \.offset) { index, zone in
                    let rect = zone.frame(in: bounds).insetBy(dx: 2, dy: 2)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(selected == index ? 0.55 : 0.22))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: selected == index ? 2 : 1))
                        .overlay(Text("\(index + 1)").font(.title2.weight(.semibold)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .onTapGesture { selected = index }
                }
                if let index = selected, layout.zones.indices.contains(index) {
                    let rect = layout.zones[index].frame(in: bounds)
                    ForEach(Array(ZoneEdge.allCases.enumerated()), id: \.offset) { _, edge in
                        handle(edge, zone: index, rect: rect, size: geometry.size)
                    }
                }
            }
        }
        .coordinateSpace(name: "canvas")
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
    }

    /// A draggable bar on one edge of the selected zone.
    private func handle(_ edge: ZoneEdge, zone index: Int, rect: CGRect, size: CGSize) -> some View {
        let vertical = edge == .left || edge == .right
        let center: CGPoint
        switch edge {
        case .left: center = CGPoint(x: rect.minX + 5, y: rect.midY)
        case .right: center = CGPoint(x: rect.maxX - 5, y: rect.midY)
        case .top: center = CGPoint(x: rect.midX, y: rect.minY + 5)
        case .bottom: center = CGPoint(x: rect.midX, y: rect.maxY - 5)
        }
        return Capsule()
            .fill(Color.white)
            .shadow(radius: 1.5)
            .frame(width: vertical ? 7 : max(rect.width * 0.35, 24), height: vertical ? max(rect.height * 0.35, 24) : 7)
            .contentShape(Rectangle().inset(by: -6))
            .position(center)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas")).onChanged { value in
                let position = vertical ? value.location.x / size.width : value.location.y / size.height
                layout.moveEdge(edge, ofZone: index, to: Double(position))
            })
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
    @ObservedObject var settings: Settings
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
            Divider()
            Toggle("Remember the arrangement for each display configuration", isOn: $settings.displayProfilesEnabled)
            HStack {
                Text("When you connect or disconnect a display, windows return to where they were "
                     + "the last time that combination of displays was in use. "
                     + "Remembered: \(store.displaySetups.count).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Forget") { store.clearDisplaySetups() }
                    .disabled(store.displaySetups.isEmpty)
            }
        }
        .padding()
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.save(windowManager.captureSetup(named: trimmedName))
        name = ""
    }
}

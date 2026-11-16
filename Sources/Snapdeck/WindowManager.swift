import AppKit
import ApplicationServices
import SnapdeckCore

/// Applies snapping, layouts and saved setups to real windows.
/// Every action has a matching `preview…` that returns what it would do without doing it.
final class WindowManager {
    private let store: Store
    private let settings: Settings
    /// Frames windows had before they were first snapped, for "restore".
    private var restoreFrames: [AXUIElement: CGRect] = [:]
    /// The zone each window was last put into and the frame it actually took.
    /// Windows with a minimum or fixed size do not fill their zone, so the zone
    /// cannot always be worked out from the frame alone.
    private var placed: [AXUIElement: (zone: Zone, screen: ScreenInfo, frame: CGRect)] = [:]

    /// Set to trace snap decisions (debug builds only, see `--trace` in AppDelegate).
    var trace: ((String) -> Void)?
    /// Asked before a restore launches apps: receives their names, returns whether to go ahead.
    /// Setups are plain files, so the user confirms what a restore is about to open.
    var confirmLaunch: (([String]) -> Bool)?

    /// A resolved action on one window.
    private enum Move {
        case place(AXUIElement, Zone, ScreenInfo)
        case restore(AXUIElement, CGRect)
        case setFrame(AXUIElement, CGRect)
    }

    init(store: Store, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    // MARK: Screens

    func screen(for frame: CGRect) -> ScreenInfo? {
        let screens = Accessibility.screens()
        let best = screens.max { a, b in
            area(a.frame.intersection(frame)) < area(b.frame.intersection(frame))
        }
        return best ?? screens.first
    }

    func screen(containing point: CGPoint) -> ScreenInfo? {
        Accessibility.screens().first { $0.frame.contains(point) }
    }

    /// The screen of the focused window, else the one under the mouse.
    private func currentScreen() -> ScreenInfo? {
        Accessibility.focusedWindow()?.frame.flatMap { screen(for: $0) }
            ?? screen(containing: Accessibility.mouseLocation)
            ?? Accessibility.screens().first
    }

    private func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    private func adjacentScreen(to screen: ScreenInfo, direction: Direction) -> ScreenInfo? {
        let screens = Accessibility.screens()
        guard let index = screens.firstIndex(of: screen) else { return nil }
        let target = direction == .left ? index - 1 : index + 1
        return screens.indices.contains(target) ? screens[target] : nil
    }

    /// Where `zone` ends up on `screen`, including the configured gap.
    func frame(of zone: Zone, on screen: ScreenInfo) -> CGRect {
        zone.frame(in: screen.visible, gap: CGFloat(settings.gap))
    }

    // MARK: Placing

    func place(_ window: AXUIElement, in zone: Zone, on screen: ScreenInfo) {
        if restoreFrames[window] == nil, let frame = window.frame {
            if restoreFrames.count > 200 { restoreFrames.removeAll() }
            restoreFrames[window] = frame
        }
        window.setFrame(frame(of: zone, on: screen))
        if placed.count > 200 { placed.removeAll() }
        placed[window] = window.frame.map { (zone, screen, $0) }
    }

    /// The zone a window is in: the one we put it into if it has not moved since,
    /// otherwise whatever its frame corresponds to.
    private func currentZone(of window: AXUIElement, frame: CGRect, screen: ScreenInfo) -> Zone {
        if let last = placed[window], last.screen == screen,
           abs(last.frame.minX - frame.minX) < 3, abs(last.frame.minY - frame.minY) < 3,
           abs(last.frame.width - frame.width) < 3, abs(last.frame.height - frame.height) < 3 {
            return last.zone
        }
        return Zone(frame: frame, in: screen.visible, gap: CGFloat(settings.gap))
    }

    private func perform(_ move: Move?) {
        switch move {
        case .place(let window, let zone, let screen):
            place(window, in: zone, on: screen)
        case .restore(let window, let frame):
            restoreFrames[window] = nil
            placed[window] = nil
            window.setFrame(frame)
        case .setFrame(let window, let frame):
            window.setFrame(frame)
        case nil:
            break
        }
    }

    private func preview(_ move: Move?) -> [OverlaySpec] {
        switch move {
        case .place(_, let zone, let screen): return [OverlaySpec(rect: frame(of: zone, on: screen))]
        case .restore(_, let frame), .setFrame(_, let frame): return [OverlaySpec(rect: frame)]
        case nil: return []
        }
    }

    // MARK: Resolving actions on the focused window

    private func focused() -> (window: AXUIElement, frame: CGRect, screen: ScreenInfo)? {
        guard let window = Accessibility.focusedWindow(), let frame = window.frame,
              let screen = screen(for: frame) else { return nil }
        return (window, frame, screen)
    }

    private func move(for direction: Direction) -> Move? {
        guard let (window, frame, screen) = focused() else { return nil }
        let current = currentZone(of: window, frame: frame, screen: screen)
        trace?("\(direction): frame=\(frame) visible=\(screen.visible) current=\(current) -> \(nextZone(direction: direction, current: current))")

        switch nextZone(direction: direction, current: current) {
        case .restore:
            return restoreFrames[window].map { .restore(window, $0) }
        case .zone(let zone):
            // Already at this edge: carry on to the neighbouring display.
            if zone.approxEquals(current), direction == .left || direction == .right,
               let other = adjacentScreen(to: screen, direction: direction) {
                return .place(window, direction == .left ? .rightHalf : .leftHalf, other)
            }
            return .place(window, zone, screen)
        }
    }

    private func move(to zone: Zone) -> Move? {
        focused().map { .place($0.window, zone, $0.screen) }
    }

    private func centerMove() -> Move? {
        guard let (window, frame, screen) = focused() else { return nil }
        let v = screen.visible
        return .setFrame(window, CGRect(x: (v.midX - frame.width / 2).rounded(),
                                        y: (v.midY - frame.height / 2).rounded(),
                                        width: frame.width, height: frame.height))
    }

    // MARK: Actions and their previews

    func snap(_ direction: Direction) { perform(move(for: direction)) }
    func previewSnap(_ direction: Direction) -> [OverlaySpec] { preview(move(for: direction)) }

    func snapFocused(to zone: Zone) { perform(move(to: zone)) }
    func previewSnapFocused(to zone: Zone) -> [OverlaySpec] { preview(move(to: zone)) }

    func centerFocused() { perform(centerMove()) }
    func previewCenter() -> [OverlaySpec] { preview(centerMove()) }

    /// Moves the focused window into zone `index` of the active layout.
    func moveFocused(toLayoutZone index: Int) {
        guard let layout = store.activeLayout, layout.zones.indices.contains(index) else { return }
        snapFocused(to: layout.zones[index])
    }

    /// All zones of a layout on the current screen, numbered like their shortcuts.
    func previewLayout(_ layout: Layout) -> [OverlaySpec] {
        guard let screen = currentScreen() else { return [] }
        return layout.zones.enumerated().map { index, zone in
            OverlaySpec(rect: frame(of: zone, on: screen), label: "\(index + 1)")
        }
    }

    /// Fills the active layout's zones with the front-most windows of the current screen.
    func arrangeActiveLayout() {
        for (window, zone, screen) in arrangement() {
            place(window, in: zone, on: screen)
        }
    }

    func previewArrange() -> [OverlaySpec] {
        arrangement().map { window, zone, screen in
            OverlaySpec(rect: frame(of: zone, on: screen), label: appName(of: window))
        }
    }

    private func arrangement() -> [(AXUIElement, Zone, ScreenInfo)] {
        guard let layout = store.activeLayout, let screen = currentScreen() else { return [] }
        let onScreen = windowsFrontToBack().filter { window in
            window.frame.flatMap { self.screen(for: $0) } == screen
        }
        return zip(onScreen, layout.zones).map { ($0, $1, screen) }
    }

    private func appName(of window: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
    }

    /// Standard windows of all apps, front-most first.
    private func windowsFrontToBack() -> [AXUIElement] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var cache: [pid_t: [AXUIElement]] = [:]
        var used = Set<AXUIElement>()
        var result: [AXUIElement] = []

        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            if cache[pid] == nil { cache[pid] = Accessibility.windows(pid: pid) }
            let match = cache[pid]?.first { candidate in
                guard !used.contains(candidate), let f = candidate.frame else { return false }
                return abs(f.minX - bounds.minX) < 2 && abs(f.minY - bounds.minY) < 2
                    && abs(f.width - bounds.width) < 2 && abs(f.height - bounds.height) < 2
            }
            if let match {
                used.insert(match)
                result.append(match)
            }
        }
        return result
    }

    // MARK: Saved setups

    /// Records where every standard window of every regular app currently sits.
    func captureSetup(named name: String) -> WindowSetup {
        let screens = Accessibility.screens()
        var entries: [WindowSetup.Entry] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            for window in Accessibility.windows(pid: app.processIdentifier) {
                guard let frame = window.frame, let screen = screen(for: frame),
                      let index = screens.firstIndex(of: screen) else { continue }
                entries.append(.init(bundleID: bundleID, title: window.title, screen: index,
                                     zone: Zone(frame: frame, in: screen.visible)))
            }
        }
        return WindowSetup(name: name, windows: entries)
    }

    /// Where a setup's windows go, labelled with their app names.
    func previewSetup(_ setup: WindowSetup) -> [OverlaySpec] {
        let screens = Accessibility.screens()
        guard !screens.isEmpty else { return [] }
        return setup.windows.map { entry in
            let screen = screens[max(0, min(entry.screen, screens.count - 1))]
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleID).first
            let name = running?.localizedName
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)?
                    .deletingPathExtension().lastPathComponent
                ?? entry.bundleID
            return OverlaySpec(rect: entry.zone.frame(in: screen.visible), label: name)
        }
    }

    /// Puts windows back where the setup recorded them. Apps that are not running
    /// are launched and placed a moment later, once their windows exist.
    func restore(_ setup: WindowSetup, launchMissing: Bool = true) {
        let screens = Accessibility.screens()
        guard !screens.isEmpty else { return }
        var launched = false
        var launchMissing = launchMissing

        if launchMissing {
            let missing = Set(setup.windows.map(\.bundleID))
                .filter { NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
                .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted()
            if !missing.isEmpty { launchMissing = confirmLaunch?(missing) ?? false }
        }

        for (bundleID, entries) in Dictionary(grouping: setup.windows, by: \.bundleID) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            guard let app = running.first else {
                if launchMissing, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    launched = true
                }
                continue
            }
            let live = Accessibility.windows(pid: app.processIdentifier)
            let pairs = matchWindows(savedTitles: entries.map(\.titleHash),
                                     liveTitles: live.map { WindowSetup.hash($0.title) })
            for (entry, liveIndex) in zip(entries, pairs) {
                guard let liveIndex else { continue }
                let screen = screens[max(0, min(entry.screen, screens.count - 1))]
                live[liveIndex].setFrame(entry.zone.frame(in: screen.visible))
            }
        }

        if launched {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.restore(setup, launchMissing: false)
            }
        }
    }
}

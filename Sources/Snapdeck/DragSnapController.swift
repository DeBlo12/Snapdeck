import AppKit
import ApplicationServices
import SnapdeckCore

/// Watches window drags and snaps the window when it is dropped at a screen edge.
final class DragSnapController {
    private let windowManager: WindowManager
    private let settings: Settings
    private let store: Store
    private let overlay = OverlayController()

    private var window: AXUIElement?
    private var startFrame: CGRect?
    private var isDragging = false
    private var lastCheck: TimeInterval = 0
    private var target: (zone: Zone, screen: ScreenInfo)?

    init(windowManager: WindowManager, settings: Settings, store: Store) {
        self.windowManager = windowManager
        self.settings = settings
        self.store = store
    }

    func start() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: mouseDown()
        case .leftMouseDragged: mouseDragged(event)
        case .leftMouseUp: mouseUp()
        default: break
        }
    }

    private func mouseDown() {
        reset()
        guard settings.dragSnapEnabled || settings.dragLayoutEnabled, Accessibility.isTrusted,
              let hit = Accessibility.window(at: Accessibility.mouseLocation),
              hit.isStandardWindow else { return }
        window = hit
        startFrame = hit.frame
    }

    private func mouseDragged(_ event: NSEvent) {
        guard let window, let startFrame else { return }

        if !isDragging {
            // Ask the window where it is at most 20 times a second until we know
            // whether this is a move (origin changes) or a resize (size changes).
            guard event.timestamp - lastCheck > 0.05 else { return }
            lastCheck = event.timestamp
            guard let now = window.frame else { return }
            if abs(now.width - startFrame.width) > 1 || abs(now.height - startFrame.height) > 1 {
                reset()
                return
            }
            guard abs(now.minX - startFrame.minX) > 3 || abs(now.minY - startFrame.minY) > 3 else { return }
            isDragging = true
        }

        let point = Accessibility.mouseLocation

        // Shift held: show every zone of the active layout and target the one under the cursor.
        if settings.dragLayoutEnabled, NSEvent.modifierFlags.contains(.shift),
           let layout = store.activeLayout, let screen = windowManager.screen(containing: point) {
            let hit = zoneIndex(at: point, zones: layout.zones, in: screen.visible)
            target = hit.map { (layout.zones[$0], screen) }
            overlay.show(layout.zones.enumerated().map { index, zone in
                OverlaySpec(rect: windowManager.frame(of: zone, on: screen), label: "\(index + 1)", dimmed: index != hit)
            })
            return
        }

        guard settings.dragSnapEnabled, let screen = windowManager.screen(containing: point),
              let zone = edgeZone(point: point, screen: screen.frame) else {
            target = nil
            overlay.hide()
            return
        }
        target = (zone, screen)
        overlay.show([OverlaySpec(rect: windowManager.frame(of: zone, on: screen))])
    }

    private func mouseUp() {
        if isDragging, let window, let target {
            // Give the dragged app a moment to finish its own drag handling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [windowManager] in
                windowManager.place(window, in: target.zone, on: target.screen)
            }
        }
        reset()
    }

    private func reset() {
        window = nil
        startFrame = nil
        isDragging = false
        lastCheck = 0
        target = nil
        overlay.hide()
    }
}

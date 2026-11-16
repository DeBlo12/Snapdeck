import AppKit
import SnapdeckCore

/// Remembers the window arrangement for each display configuration (for example
/// "laptop only" and "laptop plus external monitor") and puts it back when that
/// configuration returns.
///
/// The arrangement has to be recorded while the displays are still connected,
/// because macOS has already moved the windows by the time a display is gone.
/// So the current arrangement is snapshotted on a timer.
final class DisplayProfileController {
    private let store: Store
    private let settings: Settings
    private let windowManager: WindowManager
    private var currentKey = ""
    /// No snapshots while macOS is still shuffling windows after a change.
    private var pausedUntil = Date.distantPast

    init(store: Store, settings: Settings, windowManager: WindowManager) {
        self.store = store
        self.settings = settings
        self.windowManager = windowManager
    }

    func start() {
        currentKey = key()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.snapshot() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }
    }

    private func key() -> String {
        displayKey(frames: Accessibility.screens().map(\.frame))
    }

    private func snapshot() {
        guard settings.displayProfilesEnabled, Accessibility.isTrusted, Date() > pausedUntil,
              key() == currentKey else { return }
        let setup = windowManager.captureSetup(named: currentKey)
        guard !setup.windows.isEmpty else { return }
        store.saveDisplaySetup(setup, for: currentKey)
    }

    private func screensChanged() {
        pausedUntil = Date().addingTimeInterval(8)
        // Wait for macOS to finish rearranging before restoring ours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            let newKey = self.key()
            // The notification also fires for Dock and menu bar changes.
            guard newKey != self.currentKey else { return }
            self.currentKey = newKey
            if self.settings.displayProfilesEnabled, let setup = self.store.displaySetups[newKey] {
                self.windowManager.restore(setup, launchMissing: false)
            }
        }
    }
}

import AppKit

/// One translucent rectangle to draw on screen, in Accessibility (top-left origin) coordinates.
struct OverlaySpec: Equatable {
    var rect: CGRect
    var label: String = ""
    /// Dimmed rectangles show the alternatives next to the one that is targeted.
    var dimmed: Bool = false
}

/// Shows translucent previews of where windows will land.
final class OverlayController {
    private var windows: [NSWindow] = []
    private var shown: [OverlaySpec] = []

    func show(_ specs: [OverlaySpec]) {
        guard specs != shown else { return }
        shown = specs
        while windows.count < specs.count { windows.append(makeWindow()) }

        for (window, spec) in zip(windows, specs) {
            window.setFrame(Accessibility.flip(spec.rect).insetBy(dx: 5, dy: 5), display: true)
            if let label = window.contentView?.subviews.first as? NSTextField {
                label.stringValue = spec.label
                label.alphaValue = spec.dimmed ? 0.6 : 1
            }
            let accent = NSColor.controlAccentColor
            window.contentView?.layer?.borderColor = accent.withAlphaComponent(spec.dimmed ? 0.45 : 0.9).cgColor
            window.contentView?.layer?.backgroundColor = accent.withAlphaComponent(spec.dimmed ? 0.07 : 0.28).cgColor
            window.orderFrontRegardless()
        }
        windows.dropFirst(specs.count).forEach { $0.orderOut(nil) }
    }

    func hide() {
        shown = []
        windows.forEach { $0.orderOut(nil) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        label.textColor = .white
        label.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 4
            return shadow
        }()
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -16),
        ])

        window.contentView = view
        return window
    }
}

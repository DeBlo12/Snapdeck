import AppKit
import ApplicationServices

/// A display, in Accessibility coordinates (origin top-left of the primary screen, y down).
struct ScreenInfo: Equatable {
    /// The whole display.
    let frame: CGRect
    /// The display minus menu bar and Dock.
    let visible: CGRect
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSystemSettings() {
        requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Height of the primary screen, used to flip between AppKit and AX coordinates.
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Converts a rectangle between AppKit (bottom-left) and AX (top-left) coordinates.
    /// The conversion is its own inverse.
    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static var mouseLocation: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// All screens sorted left to right.
    static func screens() -> [ScreenInfo] {
        NSScreen.screens
            .map { ScreenInfo(frame: flip($0.frame), visible: flip($0.visibleFrame)) }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return element.element(kAXFocusedWindowAttribute)
    }

    /// Standard, non-minimised windows of a process.
    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let all = app.value(kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return all.filter { $0.isStandardWindow && !$0.isMinimized }
    }

    /// The window under a point on screen, if any.
    static func window(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let element = hit else { return nil }
        if (element.value(kAXRoleAttribute) as? String) == kAXWindowRole { return element }
        return element.element(kAXWindowAttribute)
    }
}

extension AXUIElement {
    func value(_ attribute: String) -> AnyObject? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let v = value(attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    var title: String { (value(kAXTitleAttribute) as? String) ?? "" }
    var isMinimized: Bool { (value(kAXMinimizedAttribute) as? Bool) ?? false }
    var isStandardWindow: Bool { (value(kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole }

    var frame: CGRect? {
        guard let p = value(kAXPositionAttribute), let s = value(kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func setFrame(_ rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        guard let p = AXValueCreate(.cgPoint, &origin), let s = AXValueCreate(.cgSize, &size) else { return }
        // Size, position, size: the first resize can be clamped by the old screen,
        // the second one applies once the window has arrived on the target screen.
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, p)
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, s)
    }
}

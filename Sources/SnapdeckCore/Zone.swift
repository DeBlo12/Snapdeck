import CoreGraphics
import Foundation

/// A rectangle expressed as fractions (0...1) of a screen's usable area.
/// The origin is the top-left corner, y grows downwards.
public struct Zone: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = Zone(x: 0, y: 0, width: 1, height: 1)
    public static let leftHalf = Zone(x: 0, y: 0, width: 0.5, height: 1)
    public static let rightHalf = Zone(x: 0.5, y: 0, width: 0.5, height: 1)
    public static let topHalf = Zone(x: 0, y: 0, width: 1, height: 0.5)
    public static let bottomHalf = Zone(x: 0, y: 0.5, width: 1, height: 0.5)
    public static let topLeft = Zone(x: 0, y: 0, width: 0.5, height: 0.5)
    public static let topRight = Zone(x: 0.5, y: 0, width: 0.5, height: 0.5)
    public static let bottomLeft = Zone(x: 0, y: 0.5, width: 0.5, height: 0.5)
    public static let bottomRight = Zone(x: 0.5, y: 0.5, width: 0.5, height: 0.5)

    /// The zone a window frame occupies within `area`. Inverse of `frame(in:gap:)`.
    public init(frame: CGRect, in area: CGRect, gap: CGFloat = 0) {
        let area = area.insetBy(dx: gap / 2, dy: gap / 2)
        let frame = frame.insetBy(dx: -gap / 2, dy: -gap / 2)
        let w = max(area.width, 1), h = max(area.height, 1)
        self.init(
            x: Double((frame.minX - area.minX) / w),
            y: Double((frame.minY - area.minY) / h),
            width: Double(frame.width / w),
            height: Double(frame.height / h)
        )
    }

    /// The concrete frame of this zone inside `area` (top-left origin coordinates).
    /// `gap` is the space left between neighbouring windows and to the screen edges.
    public func frame(in area: CGRect, gap: CGFloat = 0) -> CGRect {
        let area = area.insetBy(dx: gap / 2, dy: gap / 2)
        let left = (area.minX + CGFloat(x) * area.width).rounded()
        let top = (area.minY + CGFloat(y) * area.height).rounded()
        let right = (area.minX + CGFloat(x + width) * area.width).rounded()
        let bottom = (area.minY + CGFloat(y + height) * area.height).rounded()
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .insetBy(dx: gap / 2, dy: gap / 2)
    }

    /// Tolerant comparison: apps such as terminals round their size to a grid.
    public func approxEquals(_ other: Zone, tolerance: Double = 0.03) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// True when the zone lies inside the unit square and has a usable size.
    public var isValid: Bool {
        x >= 0 && y >= 0 && width > 0.05 && height > 0.05 && x + width <= 1.0001 && y + height <= 1.0001
    }
}

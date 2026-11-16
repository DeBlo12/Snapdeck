import CoreGraphics
import Foundation

public enum Direction: Sendable {
    case left, right, up, down
}

public enum SnapResult: Equatable, Sendable {
    case zone(Zone)
    /// Put the window back to the frame it had before it was snapped.
    case restore
}

/// Windows-style arrow-key snapping: what a window in `current` should do
/// when the user presses the shortcut for `direction`.
public func nextZone(direction: Direction, current: Zone) -> SnapResult {
    func at(_ zone: Zone) -> Bool { current.approxEquals(zone) }

    switch direction {
    case .left:
        if at(.topRight) { return .zone(.topLeft) }
        if at(.bottomRight) { return .zone(.bottomLeft) }
        if at(.topLeft) || at(.bottomLeft) { return .zone(current) }
        return .zone(.leftHalf)
    case .right:
        if at(.topLeft) { return .zone(.topRight) }
        if at(.bottomLeft) { return .zone(.bottomRight) }
        if at(.topRight) || at(.bottomRight) { return .zone(current) }
        return .zone(.rightHalf)
    case .up:
        if at(.leftHalf) { return .zone(.topLeft) }
        if at(.rightHalf) { return .zone(.topRight) }
        if at(.bottomLeft) { return .zone(.leftHalf) }
        if at(.bottomRight) { return .zone(.rightHalf) }
        return .zone(.full)
    case .down:
        if at(.topLeft) { return .zone(.leftHalf) }
        if at(.topRight) { return .zone(.rightHalf) }
        if at(.leftHalf) { return .zone(.bottomLeft) }
        if at(.rightHalf) { return .zone(.bottomRight) }
        return .restore
    }
}

/// The zone under `point` when zones are laid out in `area`. Where zones overlap,
/// the smallest one wins so that it stays reachable.
public func zoneIndex(at point: CGPoint, zones: [Zone], in area: CGRect) -> Int? {
    zones.indices
        .filter { zones[$0].frame(in: area).contains(point) }
        .min { zones[$0].width * zones[$0].height < zones[$1].width * zones[$1].height }
}

/// Drag-to-edge snapping: the zone to offer while the cursor is at `point`
/// on a screen with frame `screen` (both in top-left origin coordinates).
/// The bottom edge is left alone because the Dock usually lives there.
public func edgeZone(point: CGPoint, screen: CGRect, edge: CGFloat = 4, corner: CGFloat = 100) -> Zone? {
    let nearLeft = point.x <= screen.minX + edge
    let nearRight = point.x >= screen.maxX - edge - 1
    let nearTop = point.y <= screen.minY + edge
    let inTopBand = point.y <= screen.minY + corner
    let inBottomBand = point.y >= screen.maxY - corner

    if nearLeft {
        return inTopBand ? .topLeft : (inBottomBand ? .bottomLeft : .leftHalf)
    }
    if nearRight {
        return inTopBand ? .topRight : (inBottomBand ? .bottomRight : .rightHalf)
    }
    if nearTop {
        if point.x <= screen.minX + corner { return .topLeft }
        if point.x >= screen.maxX - corner { return .topRight }
        return .full
    }
    return nil
}

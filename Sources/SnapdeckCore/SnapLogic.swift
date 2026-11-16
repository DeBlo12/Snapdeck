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

/// The screen next to `frames[index]` in `direction` (top-left origin coordinates).
/// Screens that sit side by side (or one above the other) with the current one are
/// preferred, nearest first. A diagonal neighbour only counts when it lies mainly
/// in the requested direction.
public func adjacentScreen(from index: Int, direction: Direction, frames: [CGRect]) -> Int? {
    guard frames.indices.contains(index) else { return nil }
    let current = frames[index]
    let horizontal = direction == .left || direction == .right

    // Ranked by: shares an edge range with the current screen, then the gap between
    // the two screens, then how much of the edge they share.
    var best: (index: Int, overlap: CGFloat, gap: CGFloat)?
    for (i, other) in frames.enumerated() where i != index {
        let dx = other.midX - current.midX
        let dy = other.midY - current.midY
        let along = horizontal ? dx : dy
        let across = horizontal ? dy : dx
        guard direction == .left || direction == .up ? along < 0 : along > 0 else { continue }

        let overlap = max(0, horizontal
            ? min(current.maxY, other.maxY) - max(current.minY, other.minY)
            : min(current.maxX, other.maxX) - max(current.minX, other.minX))
        guard overlap > 0 || abs(along) >= abs(across) else { continue }

        let gap: CGFloat
        switch direction {
        case .left: gap = max(0, current.minX - other.maxX)
        case .right: gap = max(0, other.minX - current.maxX)
        case .up: gap = max(0, current.minY - other.maxY)
        case .down: gap = max(0, other.minY - current.maxY)
        }

        if let b = best {
            let better = (overlap > 0) != (b.overlap > 0) ? overlap > 0
                : gap != b.gap ? gap < b.gap
                : overlap > b.overlap
            if !better { continue }
        }
        best = (i, overlap, gap)
    }
    return best?.index
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

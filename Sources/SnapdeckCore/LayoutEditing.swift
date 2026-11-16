import Foundation

/// One side of a zone.
public enum ZoneEdge: CaseIterable, Sendable {
    case left, right, top, bottom

    var isVertical: Bool { self == .left || self == .right }
}

/// Editing operations used by the visual layout editor.
extension Layout {
    /// Smallest width or height a zone may have, as a fraction of the screen.
    public static let minimumZoneSize = 0.1
    private static let epsilon = 1e-6

    /// Splits a zone into two equal halves, side by side or stacked.
    /// Returns false when the halves would be too small.
    @discardableResult
    public mutating func splitZone(at index: Int, sideBySide: Bool) -> Bool {
        guard zones.indices.contains(index) else { return false }
        let zone = zones[index]
        let half = (sideBySide ? zone.width : zone.height) / 2
        guard half >= Layout.minimumZoneSize - Layout.epsilon else { return false }

        var first = zone, second = zone
        if sideBySide {
            first.width = half
            second.x = zone.x + half
            second.width = half
        } else {
            first.height = half
            second.y = zone.y + half
            second.height = half
        }
        zones[index] = first
        zones.insert(second, at: index + 1)
        return true
    }

    /// Removes a zone. The last remaining zone cannot be removed.
    @discardableResult
    public mutating func removeZone(at index: Int) -> Bool {
        guard zones.indices.contains(index), zones.count > 1 else { return false }
        zones.remove(at: index)
        return true
    }

    /// Moves one edge of a zone to `position` (0...1 along that axis).
    /// Every zone that shares the dividing line moves with it, so neighbours stay
    /// flush. An edge on the screen border only moves the zone itself.
    /// The position snaps to `step` and is limited so that no zone gets too small.
    public mutating func moveEdge(_ edge: ZoneEdge, ofZone index: Int, to position: Double,
                                  step: Double = 1.0 / 60) {
        guard zones.indices.contains(index) else { return }
        let vertical = edge.isVertical
        func low(_ z: Zone) -> Double { vertical ? z.x : z.y }
        func high(_ z: Zone) -> Double { vertical ? z.x + z.width : z.y + z.height }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < Layout.epsilon }

        let line = (edge == .left || edge == .top) ? low(zones[index]) : high(zones[index])
        let onBorder = near(line, 0) || near(line, 1)

        // Which zones start at the line, and which end at it.
        var starting: [Int] = [], ending: [Int] = []
        if onBorder {
            if edge == .left || edge == .top { starting = [index] } else { ending = [index] }
        } else {
            starting = zones.indices.filter { near(low(zones[$0]), line) }
            ending = zones.indices.filter { near(high(zones[$0]), line) }
        }

        let lowerBound = ending.map { low(zones[$0]) + Layout.minimumZoneSize }.max() ?? 0
        let upperBound = starting.map { high(zones[$0]) - Layout.minimumZoneSize }.min() ?? 1
        guard lowerBound <= upperBound + Layout.epsilon else { return }

        let snapped = step > 0 ? (position / step).rounded() * step : position
        let target = min(max(snapped, lowerBound, 0), upperBound, 1)

        for i in starting {
            let end = high(zones[i])
            if vertical {
                zones[i].x = target
                zones[i].width = end - target
            } else {
                zones[i].y = target
                zones[i].height = end - target
            }
        }
        for i in ending {
            if vertical { zones[i].width = target - zones[i].x } else { zones[i].height = target - zones[i].y }
        }
    }
}

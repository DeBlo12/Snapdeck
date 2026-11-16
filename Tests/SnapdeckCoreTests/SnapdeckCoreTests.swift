import CoreGraphics
import XCTest
@testable import SnapdeckCore

final class ZoneTests: XCTestCase {
    // A screen whose usable area starts below a 25pt menu bar.
    let area = CGRect(x: 0, y: 25, width: 1440, height: 875)

    func testHalvesTileWithoutGapOrOverlap() {
        let left = Zone.leftHalf.frame(in: area)
        let right = Zone.rightHalf.frame(in: area)
        XCTAssertEqual(left, CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(right.maxX, area.maxX)
    }

    func testThirdsTileOnOddWidth() {
        let odd = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let frames = Layout.builtIn.first { $0.name == "Thirds" }!.zones.map { $0.frame(in: odd) }
        XCTAssertEqual(frames[0].maxX, frames[1].minX)
        XCTAssertEqual(frames[1].maxX, frames[2].minX)
        XCTAssertEqual(frames[2].maxX, 1000)
    }

    func testFrameOnSecondaryScreenWithOffset() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(Zone.bottomRight.frame(in: second), CGRect(x: 2400, y: 340, width: 960, height: 540))
    }

    func testRoundTripFromFrame() {
        let frame = Zone.topRight.frame(in: area)
        XCTAssertTrue(Zone(frame: frame, in: area).approxEquals(.topRight))
    }

    func testGapIsEqualBetweenWindowsAndAtEdges() {
        let left = Zone.leftHalf.frame(in: area, gap: 10)
        let right = Zone.rightHalf.frame(in: area, gap: 10)
        XCTAssertEqual(left, CGRect(x: 10, y: 35, width: 705, height: 855))
        XCTAssertEqual(right.minX - left.maxX, 10)
        XCTAssertEqual(area.maxX - right.maxX, 10)
        XCTAssertEqual(area.maxY - left.maxY, 10)
    }

    func testRoundTripWithGap() {
        let frame = Zone.bottomLeft.frame(in: area, gap: 16)
        XCTAssertTrue(Zone(frame: frame, in: area, gap: 16).approxEquals(.bottomLeft, tolerance: 0.002))
    }

    func testBuiltInLayoutsAreValid() {
        for layout in Layout.builtIn {
            XCTAssertFalse(layout.zones.isEmpty, layout.name)
            XCTAssertTrue(layout.zones.allSatisfy(\.isValid), layout.name)
        }
    }

    func testInvalidZones() {
        XCTAssertFalse(Zone(x: 0.8, y: 0, width: 0.5, height: 1).isValid)
        XCTAssertFalse(Zone(x: 0, y: 0, width: 0, height: 1).isValid)
        XCTAssertFalse(Zone(x: -0.1, y: 0, width: 0.5, height: 1).isValid)
    }
}

final class SnapLogicTests: XCTestCase {
    let floating = Zone(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

    func testFloatingWindow() {
        XCTAssertEqual(nextZone(direction: .left, current: floating), .zone(.leftHalf))
        XCTAssertEqual(nextZone(direction: .right, current: floating), .zone(.rightHalf))
        XCTAssertEqual(nextZone(direction: .up, current: floating), .zone(.full))
        XCTAssertEqual(nextZone(direction: .down, current: floating), .restore)
    }

    func testHalfToQuarterAndBack() {
        XCTAssertEqual(nextZone(direction: .up, current: .leftHalf), .zone(.topLeft))
        XCTAssertEqual(nextZone(direction: .down, current: .leftHalf), .zone(.bottomLeft))
        XCTAssertEqual(nextZone(direction: .down, current: .topRight), .zone(.rightHalf))
        XCTAssertEqual(nextZone(direction: .up, current: .bottomRight), .zone(.rightHalf))
    }

    func testQuartersMoveSideways() {
        XCTAssertEqual(nextZone(direction: .right, current: .topLeft), .zone(.topRight))
        XCTAssertEqual(nextZone(direction: .left, current: .bottomRight), .zone(.bottomLeft))
    }

    func testMaximisedDownRestores() {
        XCTAssertEqual(nextZone(direction: .down, current: .full), .restore)
    }

    func testRepeatedPressStaysPut() {
        // The app layer uses "result equals current" to hop to the next display.
        XCTAssertEqual(nextZone(direction: .left, current: .leftHalf), .zone(.leftHalf))
        XCTAssertEqual(nextZone(direction: .right, current: .rightHalf), .zone(.rightHalf))
    }

    func testToleratesSlightlyOffSizes() {
        let nearlyLeft = Zone(x: 0, y: 0, width: 0.51, height: 0.99)
        XCTAssertEqual(nextZone(direction: .up, current: nearlyLeft), .zone(.topLeft))
    }
}

final class EdgeZoneTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testEdges() {
        XCTAssertEqual(edgeZone(point: CGPoint(x: 0, y: 450), screen: screen), .leftHalf)
        XCTAssertEqual(edgeZone(point: CGPoint(x: 1439, y: 450), screen: screen), .rightHalf)
        XCTAssertEqual(edgeZone(point: CGPoint(x: 700, y: 0), screen: screen), .full)
    }

    func testCorners() {
        XCTAssertEqual(edgeZone(point: CGPoint(x: 0, y: 10), screen: screen), .topLeft)
        XCTAssertEqual(edgeZone(point: CGPoint(x: 1439, y: 890), screen: screen), .bottomRight)
        XCTAssertEqual(edgeZone(point: CGPoint(x: 1400, y: 0), screen: screen), .topRight)
        XCTAssertEqual(edgeZone(point: CGPoint(x: 0, y: 880), screen: screen), .bottomLeft)
    }

    func testMiddleAndBottomDoNothing() {
        XCTAssertNil(edgeZone(point: CGPoint(x: 700, y: 450), screen: screen))
        XCTAssertNil(edgeZone(point: CGPoint(x: 700, y: 899), screen: screen))
    }

    func testOffsetScreen() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(edgeZone(point: CGPoint(x: 1441, y: 500), screen: second), .leftHalf)
        XCTAssertNil(edgeZone(point: CGPoint(x: 1500, y: 500), screen: second))
    }
}

final class AdjacentScreenTests: XCTestCase {
    // Laptop in the middle, one display on each side and one above.
    let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let right = CGRect(x: 1728, y: -100, width: 1920, height: 1080)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: -100, y: -1440, width: 2560, height: 1440)

    func testAllFourDirections() {
        let frames = [laptop, right, left, above]
        XCTAssertEqual(adjacentScreen(from: 0, direction: .right, frames: frames), 1)
        XCTAssertEqual(adjacentScreen(from: 0, direction: .left, frames: frames), 2)
        XCTAssertEqual(adjacentScreen(from: 0, direction: .up, frames: frames), 3)
        XCTAssertNil(adjacentScreen(from: 0, direction: .down, frames: frames))
        XCTAssertEqual(adjacentScreen(from: 3, direction: .down, frames: frames), 0)
    }

    func testNearestScreenWins() {
        let farRight = CGRect(x: 3648, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(adjacentScreen(from: 0, direction: .right, frames: [laptop, farRight, right]), 2)
        XCTAssertEqual(adjacentScreen(from: 1, direction: .left, frames: [laptop, farRight, right]), 2)
    }

    func testSingleScreenHasNoNeighbour() {
        for direction in [Direction.left, .right, .up, .down] {
            XCTAssertNil(adjacentScreen(from: 0, direction: direction, frames: [laptop]))
        }
    }

    func testDiagonalNeighbourCountsOnlyInItsMainDirection() {
        // Entirely above and to the right, no shared edge range; further up than across.
        let diagonal = CGRect(x: 1728, y: -2000, width: 1000, height: 800)
        XCTAssertEqual(adjacentScreen(from: 0, direction: .up, frames: [laptop, diagonal]), 1)
        XCTAssertNil(adjacentScreen(from: 0, direction: .right, frames: [laptop, diagonal]))
    }
}

final class ZoneHitTests: XCTestCase {
    let area = CGRect(x: 0, y: 25, width: 1000, height: 800)

    func testFindsZoneUnderPoint() {
        let grid: [Zone] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        XCTAssertEqual(zoneIndex(at: CGPoint(x: 100, y: 100), zones: grid, in: area), 0)
        XCTAssertEqual(zoneIndex(at: CGPoint(x: 900, y: 700), zones: grid, in: area), 3)
    }

    func testOutsideAllZones() {
        XCTAssertNil(zoneIndex(at: CGPoint(x: 900, y: 100), zones: [.leftHalf], in: area))
        XCTAssertNil(zoneIndex(at: CGPoint(x: 100, y: 10), zones: [.full], in: area))
    }

    func testSmallestOverlappingZoneWins() {
        let centre = Zone(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        XCTAssertEqual(zoneIndex(at: CGPoint(x: 500, y: 425), zones: [.full, centre], in: area), 1)
        XCTAssertEqual(zoneIndex(at: CGPoint(x: 50, y: 50), zones: [.full, centre], in: area), 0)
    }
}

final class LayoutEditingTests: XCTestCase {
    func layout(_ name: String) -> Layout { Layout.builtIn.first { $0.name == name }! }

    func testSplitSideBySide() {
        var l = Layout(name: "t", zones: [.full])
        XCTAssertTrue(l.splitZone(at: 0, sideBySide: true))
        XCTAssertEqual(l.zones, [.leftHalf, .rightHalf])
        XCTAssertTrue(l.splitZone(at: 1, sideBySide: false))
        XCTAssertEqual(l.zones, [.leftHalf, .topRight, .bottomRight])
    }

    func testSplitRefusesTinyZones() {
        var l = Layout(name: "t", zones: [Zone(x: 0, y: 0, width: 0.15, height: 1)])
        XCTAssertFalse(l.splitZone(at: 0, sideBySide: true))
        XCTAssertEqual(l.zones.count, 1)
    }

    func testRemoveKeepsLastZone() {
        var l = Layout(name: "t", zones: [.leftHalf, .rightHalf])
        XCTAssertTrue(l.removeZone(at: 0))
        XCTAssertFalse(l.removeZone(at: 0))
        XCTAssertEqual(l.zones, [.rightHalf])
    }

    func testMovingSharedDividerMovesAllNeighbours() {
        var l = layout("Main + Stack")
        l.moveEdge(.right, ofZone: 0, to: 0.7)
        XCTAssertEqual(l.zones[0].width, 0.7, accuracy: 1e-9)
        for i in [1, 2] {
            XCTAssertEqual(l.zones[i].x, 0.7, accuracy: 1e-9)
            XCTAssertEqual(l.zones[i].width, 0.3, accuracy: 1e-9)
        }
    }

    func testMovingStackDividerLeavesMainZoneAlone() {
        var l = layout("Main + Stack")
        l.moveEdge(.bottom, ofZone: 1, to: 0.25)
        XCTAssertEqual(l.zones[0], Zone(x: 0, y: 0, width: 0.6, height: 1))
        XCTAssertEqual(l.zones[1].height, 0.25, accuracy: 1e-9)
        XCTAssertEqual(l.zones[2].y, 0.25, accuracy: 1e-9)
        XCTAssertEqual(l.zones[2].height, 0.75, accuracy: 1e-9)
    }

    func testEdgeIsClampedToMinimumSize() {
        var l = Layout(name: "t", zones: [.leftHalf, .rightHalf])
        l.moveEdge(.right, ofZone: 0, to: 0.99)
        XCTAssertEqual(l.zones[1].width, Layout.minimumZoneSize, accuracy: 1e-9)
        l.moveEdge(.right, ofZone: 0, to: -1)
        XCTAssertEqual(l.zones[0].width, Layout.minimumZoneSize, accuracy: 1e-9)
        XCTAssertTrue(l.zones.allSatisfy(\.isValid))
    }

    func testBorderEdgeMovesOnlyThatZone() {
        var l = Layout(name: "t", zones: [.topLeft, .bottomLeft, .rightHalf])
        l.moveEdge(.left, ofZone: 0, to: 0.2)
        XCTAssertEqual(l.zones[0].x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(l.zones[0].width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(l.zones[1], .bottomLeft)
        XCTAssertEqual(l.zones[2], .rightHalf)
    }

    func testPositionSnapsToStep() {
        var l = Layout(name: "t", zones: [.leftHalf, .rightHalf])
        l.moveEdge(.right, ofZone: 0, to: 0.3301)
        XCTAssertEqual(l.zones[0].width, 1.0 / 3, accuracy: 1e-9)
    }
}

final class WindowSetupTests: XCTestCase {
    func testTitleIsStoredOnlyAsHash() throws {
        let entry = WindowSetup.Entry(bundleID: "com.example.app", title: "Secret plan.txt", screen: 0, zone: .leftHalf)
        let json = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        XCTAssertFalse(json.contains("Secret"))
        XCTAssertEqual(entry.titleHash, WindowSetup.hash("Secret plan.txt"))
        XCTAssertEqual(entry.titleHash.count, 64)
        XCTAssertEqual(WindowSetup.hash(""), "")
    }

    func testOldFilesWithPlainTitlesAreMigrated() throws {
        let old = #"{"bundleID":"com.example.app","title":"Inbox","screen":0,"zone":{"x":0,"y":0,"width":0.5,"height":1}}"#
        let entry = try JSONDecoder().decode(WindowSetup.Entry.self, from: Data(old.utf8))
        XCTAssertEqual(entry.titleHash, WindowSetup.hash("Inbox"))
    }

    func testInsaneEntriesAreDetected() {
        XCTAssertTrue(WindowSetup.Entry(bundleID: "a.b", title: "", screen: 1, zone: .full).isSane)
        XCTAssertFalse(WindowSetup.Entry(bundleID: "a.b", title: "", screen: -1, zone: .full).isSane)
        XCTAssertFalse(WindowSetup.Entry(bundleID: "a.b", title: "", screen: 0,
                                         zone: Zone(x: 0, y: 0, width: .infinity, height: 1)).isSane)
        XCTAssertFalse(WindowSetup.Entry(bundleID: "", title: "", screen: 0, zone: .full).isSane)
    }
}

final class KeyComboTests: XCTestCase {
    func testDisplayOrdersModifiersLikeMacOS() {
        let all = KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control
        XCTAssertEqual(KeyCombo(keyCode: 123, modifiers: all, label: "←").display, "⌃⌥⇧⌘←")
        XCTAssertEqual(KeyCombo(keyCode: 8, modifiers: KeyCombo.control | KeyCombo.option, label: "C").display, "⌃⌥C")
    }

    func testRequiresARealModifier() {
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: 0, label: "A").hasRequiredModifier)
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: KeyCombo.shift, label: "A").hasRequiredModifier)
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: KeyCombo.command, label: "A").hasRequiredModifier)
    }

    func testLabels() {
        XCTAssertEqual(KeyCombo.label(keyCode: 126, characters: "\u{F700}"), "↑")
        XCTAssertEqual(KeyCombo.label(keyCode: 40, characters: "k"), "K")
        XCTAssertEqual(KeyCombo.label(keyCode: 96, characters: nil), "F5")
        XCTAssertEqual(KeyCombo.label(keyCode: 200, characters: ""), "Key 200")
    }

    func testCodableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 40, modifiers: KeyCombo.option | KeyCombo.command, label: "K")
        let data = try JSONEncoder().encode(["left": combo])
        XCTAssertEqual(try JSONDecoder().decode([String: KeyCombo].self, from: data), ["left": combo])
    }
}

final class DisplayKeyTests: XCTestCase {
    let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let external = CGRect(x: 1728, y: -200, width: 2560, height: 1440)

    func testKeyDoesNotDependOnOrder() {
        XCTAssertEqual(displayKey(frames: [laptop, external]), displayKey(frames: [external, laptop]))
        XCTAssertEqual(displayKey(frames: [laptop, external]), "1728x1117@0,0|2560x1440@1728,-200")
    }

    func testDifferentConfigurationsDiffer() {
        XCTAssertNotEqual(displayKey(frames: [laptop]), displayKey(frames: [laptop, external]))
        let moved = external.offsetBy(dx: 0, dy: 200)
        XCTAssertNotEqual(displayKey(frames: [laptop, external]), displayKey(frames: [laptop, moved]))
    }
}

final class MatchWindowsTests: XCTestCase {
    func testExactTitlesWinOverOrder() {
        XCTAssertEqual(matchWindows(savedTitles: ["Inbox", "Notes"], liveTitles: ["Notes", "Inbox"]), [1, 0])
    }

    func testFallsBackToOrder() {
        XCTAssertEqual(matchWindows(savedTitles: ["old.txt", "Notes"], liveTitles: ["Notes", "new.txt"]), [1, 0])
    }

    func testMoreSavedThanLive() {
        XCTAssertEqual(matchWindows(savedTitles: ["a", "b", "c"], liveTitles: ["b"]), [nil, 0, nil])
    }

    func testEmptyTitlesPairInOrder() {
        XCTAssertEqual(matchWindows(savedTitles: ["", ""], liveTitles: ["x", "y"]), [0, 1])
    }

    func testNoLiveWindows() {
        XCTAssertEqual(matchWindows(savedTitles: ["a"], liveTitles: []), [nil])
    }
}

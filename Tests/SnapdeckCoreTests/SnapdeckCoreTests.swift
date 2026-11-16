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

import CryptoKit
import Foundation

/// A named combination of zones, e.g. "one large window plus two stacked".
public struct Layout: Codable, Equatable, Sendable {
    public var name: String
    public var zones: [Zone]

    public init(name: String, zones: [Zone]) {
        self.name = name
        self.zones = zones
    }

    public static let builtIn: [Layout] = [
        Layout(name: "Halves", zones: [.leftHalf, .rightHalf]),
        Layout(name: "Wide Left", zones: [
            Zone(x: 0, y: 0, width: 0.6, height: 1),
            Zone(x: 0.6, y: 0, width: 0.4, height: 1),
        ]),
        Layout(name: "Main + Stack", zones: [
            Zone(x: 0, y: 0, width: 0.6, height: 1),
            Zone(x: 0.6, y: 0, width: 0.4, height: 0.5),
            Zone(x: 0.6, y: 0.5, width: 0.4, height: 0.5),
        ]),
        Layout(name: "Thirds", zones: [
            Zone(x: 0, y: 0, width: 1.0 / 3, height: 1),
            Zone(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            Zone(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        ]),
        Layout(name: "Centre Focus", zones: [
            Zone(x: 0.25, y: 0, width: 0.5, height: 1),
            Zone(x: 0, y: 0, width: 0.25, height: 1),
            Zone(x: 0.75, y: 0, width: 0.25, height: 1),
        ]),
        Layout(name: "Grid", zones: [.topLeft, .topRight, .bottomLeft, .bottomRight]),
    ]
}

/// A remembered arrangement of application windows.
public struct WindowSetup: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var bundleID: String
        /// SHA-256 of the window title, used to recognise the window again.
        /// The title itself is never stored: it often names documents or web pages.
        public var titleHash: String
        /// Index into the screens sorted left to right.
        public var screen: Int
        public var zone: Zone

        public init(bundleID: String, title: String, screen: Int, zone: Zone) {
            self.bundleID = bundleID
            self.titleHash = WindowSetup.hash(title)
            self.screen = screen
            self.zone = zone
        }

        private enum CodingKeys: String, CodingKey {
            case bundleID, titleHash, title, screen, zone
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bundleID = try c.decode(String.self, forKey: .bundleID)
            screen = try c.decode(Int.self, forKey: .screen)
            zone = try c.decode(Zone.self, forKey: .zone)
            // Files written by early versions stored the plain title.
            titleHash = try c.decodeIfPresent(String.self, forKey: .titleHash)
                ?? WindowSetup.hash(try c.decodeIfPresent(String.self, forKey: .title) ?? "")
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(bundleID, forKey: .bundleID)
            try c.encode(titleHash, forKey: .titleHash)
            try c.encode(screen, forKey: .screen)
            try c.encode(zone, forKey: .zone)
        }

        /// False for entries a damaged or tampered file could contain.
        public var isSane: Bool {
            let values = [zone.x, zone.y, zone.width, zone.height]
            return screen >= 0 && !bundleID.isEmpty && values.allSatisfy { $0.isFinite && abs($0) <= 4 }
                && zone.width > 0 && zone.height > 0
        }
    }

    /// Hex SHA-256 of a window title; empty for an empty title.
    public static func hash(_ title: String) -> String {
        guard !title.isEmpty else { return "" }
        return SHA256.hash(data: Data(title.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var name: String
    public var windows: [Entry]

    public init(name: String, windows: [Entry]) {
        self.name = name
        self.windows = windows
    }
}

/// Pairs the saved windows of one app with its live windows.
/// Exact title matches win; the rest are paired in order.
/// Returns, for each saved title, the index of the live window to use (or nil).
public func matchWindows(savedTitles: [String], liveTitles: [String]) -> [Int?] {
    var result = [Int?](repeating: nil, count: savedTitles.count)
    var free = Array(liveTitles.indices)

    for (i, title) in savedTitles.enumerated() where !title.isEmpty {
        if let pos = free.firstIndex(where: { liveTitles[$0] == title }) {
            result[i] = free.remove(at: pos)
        }
    }
    for i in savedTitles.indices where result[i] == nil && !free.isEmpty {
        result[i] = free.removeFirst()
    }
    return result
}

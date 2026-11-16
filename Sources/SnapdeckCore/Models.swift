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
        public var title: String
        /// Index into the screens sorted left to right.
        public var screen: Int
        public var zone: Zone

        public init(bundleID: String, title: String, screen: Int, zone: Zone) {
            self.bundleID = bundleID
            self.title = title
            self.screen = screen
            self.zone = zone
        }
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

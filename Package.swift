// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snapdeck",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure geometry and models: no AppKit, fully unit-testable.
        .target(name: "SnapdeckCore"),
        // The menu bar app: Accessibility, hotkeys, UI.
        .executableTarget(name: "Snapdeck", dependencies: ["SnapdeckCore"]),
        .testTarget(name: "SnapdeckCoreTests", dependencies: ["SnapdeckCore"]),
    ]
)

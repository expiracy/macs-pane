// swift-tools-version: 5.10
import PackageDescription

// MacsPane, drag a window to the notch and drop it into a layout; apply presets from the menu bar.
//   • MacsPaneCore, pure logic (layouts, presets, snap zones, config) + its tests. No AppKit.
//   • MacsPaneKit , the AppKit/SwiftUI app: the drag tracker, the notch picker, the menu-bar
//                    dropdown, Settings and setup.
//   • macspane    , the executable that boots it: `swift run macspane`.
// The signed .app is built by Xcode from project.yml and reuses MacsPaneKit.
let package = Package(
    name: "MacsPane",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacsPaneCore", targets: ["MacsPaneCore"]),
        .library(name: "MacsPaneKit", targets: ["MacsPaneKit"]),
        .executable(name: "macspane", targets: ["MacsPane"]),
    ],
    targets: [
        .target(name: "MacsPaneCore"),
        .target(name: "MacsPaneKit", dependencies: ["MacsPaneCore"]),
        .executableTarget(name: "MacsPane", dependencies: ["MacsPaneKit"]),
        .testTarget(name: "MacsPaneCoreTests", dependencies: ["MacsPaneCore"]),
    ]
)

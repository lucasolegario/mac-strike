// swift-tools-version: 6.0
import PackageDescription

// MacStrike — a clean-room Wine bottle runtime for running Windows games on macOS.
//
// MacStrike wires together open-source building blocks to run Windows games on
// macOS — a Wine engine plus a D3D->Metal translation layer, driven by its own
// orchestration code:
//   - Wine            (WineHQ / Apple Game Porting Toolkit)
//   - D3DMetal        (Apple Game Porting Toolkit)
//   - DXVK / DXMT     (open source D3D -> Vulkan/Metal)
//
// `BottleEngine` is the reusable, testable core. `macstrike` is a thin CLI over
// it. The SwiftUI GUI lives in the MacStrikeGUI target.
let package = Package(
    name: "MacStrike",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BottleEngine", targets: ["BottleEngine"]),
        .executable(name: "macstrike", targets: ["macstrike"]),
        .executable(name: "macstrike-gui", targets: ["MacStrikeGUI"]),
    ],
    targets: [
        .target(name: "BottleEngine"),
        .executableTarget(
            name: "macstrike",
            dependencies: ["BottleEngine"]
        ),
        // Dependency-free self-tests (CommandLineTools has no XCTest/Testing
        // runtime). Run with: `swift run selftest`.
        .executableTarget(
            name: "selftest",
            dependencies: ["BottleEngine"]
        ),
        // SwiftUI GUI. Run from CLI with `swift run macstrike-gui`, or open
        // Package.swift in Xcode and run the "macstrike-gui" scheme.
        .executableTarget(
            name: "MacStrikeGUI",
            dependencies: ["BottleEngine"]
        ),
    ]
)

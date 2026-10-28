// swift-tools-version:5.9
import PackageDescription

// This package builds only the platform-independent puzzle rules (`PencilHive/Core`) so they can be
// tested with `swift test` on a Mac without Xcode. The iPhone app itself is `PencilHive.xcodeproj`,
// which compiles the same Core files together with the SpriteKit and SwiftUI layers.
let package = Package(
    name: "PencilHiveCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    targets: [
        .target(name: "PencilHiveCore", path: "PencilHive/Core"),
        .testTarget(
            name: "PencilHiveCoreTests",
            dependencies: ["PencilHiveCore"],
            path: "PencilHiveTests"
        ),
    ]
)

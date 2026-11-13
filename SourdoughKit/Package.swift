// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SourdoughKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BakeMath", targets: ["BakeMath"]),
        .library(name: "BakeCore", targets: ["BakeCore"]),
        .library(name: "BakeStore", targets: ["BakeStore"]),
    ],
    targets: [
        // The Build scaling engine (SPEC §3). Pure Swift.
        .target(name: "BakeMath"),
        // Value types and rules: plans, step logs, versions, timers, units (SPEC §2, §4, §5). Pure Swift.
        .target(name: "BakeCore", dependencies: ["BakeMath"]),
        // SwiftData models and operations. Apple platforms only; compiles to nothing elsewhere.
        .target(
            name: "BakeStore",
            dependencies: ["BakeMath", "BakeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "BakeMathTests", dependencies: ["BakeMath"]),
        .testTarget(name: "BakeCoreTests", dependencies: ["BakeCore", "BakeMath"]),
        .testTarget(
            name: "BakeStoreTests",
            dependencies: ["BakeStore", "BakeCore", "BakeMath"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BakeMath",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BakeMath", targets: ["BakeMath"])
    ],
    targets: [
        .target(name: "BakeMath"),
        .testTarget(name: "BakeMathTests", dependencies: ["BakeMath"])
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexAuthCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexAuthCore", targets: ["CodexAuthCore"]),
    ],
    targets: [
        .target(name: "CodexAuthCore"),
        .testTarget(name: "CodexAuthCoreTests", dependencies: ["CodexAuthCore"]),
    ]
)

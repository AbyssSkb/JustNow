// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JustNow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JustNow", targets: ["JustNow"]),
        .library(name: "JustNowCore", targets: ["JustNowCore"])
    ],
    targets: [
        .target(name: "JustNowCore"),
        .executableTarget(name: "JustNow", dependencies: ["JustNowCore"]),
        .testTarget(name: "JustNowCoreTests", dependencies: ["JustNowCore"])
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JustNow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JustNow", targets: ["JustNow"]),
        .library(name: "JustNowCore", targets: ["JustNowCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "JustNowCore"),
        .executableTarget(name: "JustNow", dependencies: ["JustNowCore", .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.copy("Resources/BrandMark.png")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "JustNowCoreTests", dependencies: ["JustNowCore"]),
        .testTarget(name: "JustNowAppTests", dependencies: ["JustNow"])
    ]
)

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GameDay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GameDayCore", targets: ["GameDayCore"]),
        .executable(name: "gameday-record", targets: ["gameday-record"]),
    ],
    targets: [
        .target(name: "GameDayCore"),
        .executableTarget(name: "gameday-record", dependencies: ["GameDayCore"]),
        .testTarget(name: "GameDayCoreTests", dependencies: ["GameDayCore"]),
    ]
)

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GameAnnouncer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GameAnnouncerCore", targets: ["GameAnnouncerCore"]),
        .executable(name: "gameannouncer-record", targets: ["gameannouncer-record"]),
        .executable(name: "gameannouncer-replay", targets: ["gameannouncer-replay"]),
        .executable(name: "GameAnnouncer", targets: ["GameAnnouncer"]),
    ],
    targets: [
        .target(name: "GameAnnouncerCore"),
        .executableTarget(name: "gameannouncer-record", dependencies: ["GameAnnouncerCore"]),
        .executableTarget(name: "gameannouncer-replay", dependencies: ["GameAnnouncerCore"]),
        .executableTarget(name: "GameAnnouncer", dependencies: ["GameAnnouncerCore"]),
        .testTarget(name: "GameAnnouncerCoreTests", dependencies: ["GameAnnouncerCore"]),
    ]
)

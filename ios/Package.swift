// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BrainPhartVoice",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "BrainPhartVoice",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ],
            path: "Sources/BrainPhartVoice"
        )
    ]
)

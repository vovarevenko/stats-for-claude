// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StatsForClaudeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StatsForClaudeKit", targets: ["StatsForClaudeKit"]),
    ],
    targets: [
        .target(
            name: "StatsForClaudeKit",
            path: "Sources/StatsForClaudeKit"
        ),
        .testTarget(
            name: "StatsForClaudeKitTests",
            dependencies: ["StatsForClaudeKit"],
            path: "Tests/StatsForClaudeKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)

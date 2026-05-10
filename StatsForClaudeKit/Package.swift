// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatsForClaudeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StatsForClaudeKit", targets: ["StatsForClaudeKit"]),
        .library(name: "StatsForClaudeAppKit", targets: ["StatsForClaudeAppKit"]),
    ],
    targets: [
        .target(
            name: "StatsForClaudeKit",
            path: "Sources/StatsForClaudeKit"
        ),
        .target(
            name: "StatsForClaudeAppKit",
            dependencies: ["StatsForClaudeKit"],
            path: "Sources/StatsForClaudeAppKit"
        ),
        .testTarget(
            name: "StatsForClaudeKitTests",
            dependencies: ["StatsForClaudeKit"],
            path: "Tests/StatsForClaudeKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)

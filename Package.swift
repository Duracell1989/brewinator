// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "brewinator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "brewinator", targets: ["Brewinator"]),
        .executable(name: "BrewinatorNotify", targets: ["BrewinatorNotify"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(name: "NotifierIPC"),
        .executableTarget(
            name: "Brewinator",
            dependencies: [
                "NotifierIPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        // Resident notification agent - not `brewinator` itself, packaged into
        // BrewinatorNotify.app by Scripts/build-notifier-app.sh. Kept in the
        // same package rather than a second repo: it shares NotifierIPC, the
        // icon assets, and the release/tag cadence with the CLI. See Phase 8
        // in the plan doc.
        .executableTarget(
            name: "BrewinatorNotify",
            dependencies: ["NotifierIPC"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "BrewinatorTests",
            dependencies: ["Brewinator"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

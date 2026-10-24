// swift-tools-version: 6.0
// UzTranslitCore: the Swift port of spec/SPEC.md (pure Swift, no Foundation; runs on iOS, macOS and Linux) and
// UzTranslitKit: the platform-independent logic the apps and extensions share (settings, counts, text files).
// Test data is copied in by ../scripts/sync-fixtures.sh (spec/fixtures.json, build/differential.json).
import PackageDescription

let package = Package(
    name: "UzTranslitCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "UzTranslitCore", targets: ["UzTranslitCore"]),
        .library(name: "UzTranslitKit", targets: ["UzTranslitKit"])
    ],
    targets: [
        .target(name: "UzTranslitCore"),
        .target(name: "UzTranslitKit", dependencies: ["UzTranslitCore"]),
        .testTarget(
            name: "UzTranslitCoreTests",
            dependencies: ["UzTranslitCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "UzTranslitKitTests", dependencies: ["UzTranslitKit"])
    ]
)

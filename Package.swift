// swift-tools-version: 6.2
// Grateful Day iOS — Phase 0 foundations (no UI).
import PackageDescription

let package = Package(
    name: "GratefulDayKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NostrCore", targets: ["NostrCore"]),
        .library(name: "GratefulDayCore", targets: ["GratefulDayCore"]),
    ],
    dependencies: [
        // Exact pin: THIRD_PARTY_NOTICES.md §2–4 are taken from this version.
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.23.0"),
    ],
    targets: [
        .target(
            name: "NostrCore",
            dependencies: [.product(name: "P256K", package: "swift-secp256k1")]
        ),
        .target(
            name: "GratefulDayCore",
            dependencies: ["NostrCore"],
            resources: [.process("Resources/wisdom.json")]
        ),
        .testTarget(
            name: "NostrCoreTests",
            dependencies: ["NostrCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GratefulDayCoreTests",
            dependencies: ["GratefulDayCore", "NostrCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

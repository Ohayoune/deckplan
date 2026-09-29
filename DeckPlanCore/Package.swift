// swift-tools-version: 6.0
//
// DeckPlanCore — the Swift port of the Python reference core (`tools/core/`).
//
// "Python first": M1–M3 built and proved the Core in Python; this
// package must produce byte-identical JSON for every fixture in `examples/`
// (canonical JSON and hash: docs/CANONICAL_JSON.md). No UI imports — Foundation
// and CryptoKit only (docs/BUILD_PLAN.md M4).

import PackageDescription

let package = Package(
    name: "DeckPlanCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DeckPlanCore", targets: ["DeckPlanCore"]),
    ],
    targets: [
        .target(
            name: "DeckPlanCore",
            path: "Sources/DeckPlanCore"
        ),
        .testTarget(
            name: "DeckPlanCoreTests",
            dependencies: ["DeckPlanCore"],
            path: "Tests/DeckPlanCoreTests"
        ),
    ]
)

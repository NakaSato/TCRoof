// swift-tools-version:6.2
import PackageDescription

// Growatt's server OpenAPI v1, read calls only, Foundation only (docs/specs/growatt-api.md). A package of its own so the
// app, TCRoofKit and anything else can depend on it; it builds and tests on Linux too.
let package = Package(
    name: "GrowattAPI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GrowattAPI", targets: ["GrowattAPI"]),
    ],
    targets: [
        .target(name: "GrowattAPI"),
        .testTarget(name: "GrowattAPITests", dependencies: ["GrowattAPI"]),
    ],
    swiftLanguageModes: [.v5]
)

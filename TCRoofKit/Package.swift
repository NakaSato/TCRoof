// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TCRoofKit",
    defaultLocalization: "th",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TCRoofCore", targets: ["TCRoofCore"]),
        .library(name: "ExcelExport", targets: ["ExcelExport"]),
        .library(name: "PDFReport", targets: ["PDFReport"]),
        .library(name: "DriveSync", targets: ["DriveSync"]),
        .library(name: "TCRoofUI", targets: ["TCRoofUI"]),
        .library(name: "TCRoofMCP", targets: ["TCRoofMCP"]),
        .library(name: "PVYield", targets: ["PVYield"]),
    ],
    dependencies: [
        // Model Context Protocol (https://github.com/modelcontextprotocol/swift-sdk), only for TCRoofMCP
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    ],
    targets: [
        // raw deflate / inflate / crc32 from the system zlib (iOS SDK and Linux both ship it)
        .target(name: "CZlib", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "TCRoofCore", resources: [.process("Resources/equipment-catalog.json"), .copy("Resources/pv-modules"), .copy("Resources/PermitForms")]),
        .target(name: "ExcelExport", dependencies: ["TCRoofCore", "CZlib"], resources: [.process("Resources")]),
        .target(name: "PDFReport", dependencies: ["TCRoofCore"], resources: [.process("Resources")]),
        .target(name: "DriveSync", dependencies: ["TCRoofCore"]),
        .target(name: "TCRoofUI", dependencies: ["TCRoofCore", "ExcelExport", "PDFReport", "DriveSync"], resources: [.process("Resources")]),
        // MCP kept apart from the survey modules: only this target depends on the SDK
        .target(name: "TCRoofMCP", dependencies: ["TCRoofCore", .product(name: "MCP", package: "swift-sdk")]),
        // PV module / inverter specs, PVsyst one-diode model, string sizing (docs/specs/energy-yield)
        .target(name: "PVYield"),
        .testTarget(name: "PVYieldTests", dependencies: ["PVYield"], resources: [.copy("Fixtures")]),
        .testTarget(name: "TCRoofCoreTests", dependencies: ["TCRoofCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PDFReportTests", dependencies: ["PDFReport", "TCRoofCore"]),
        .testTarget(name: "DriveSyncTests", dependencies: ["DriveSync", "TCRoofCore"]),
        .testTarget(name: "ExcelExportTests", dependencies: ["ExcelExport", "TCRoofCore"], resources: [.copy("Fixtures")]),
    ]
)

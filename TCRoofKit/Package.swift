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
        .library(name: "SurveyUI", targets: ["SurveyUI"]),
    ],
    targets: [
        // raw deflate / inflate / crc32 from the system zlib (iOS SDK and Linux both ship it)
        .target(name: "CZlib", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "TCRoofCore"),
        .target(name: "ExcelExport", dependencies: ["TCRoofCore", "CZlib"], resources: [.process("Resources")]),
        .target(name: "PDFReport", dependencies: ["TCRoofCore"], resources: [.process("Resources")]),
        .target(name: "DriveSync", dependencies: ["TCRoofCore"]),
        .target(name: "SurveyUI", dependencies: ["TCRoofCore", "ExcelExport", "PDFReport", "DriveSync"]),
        .testTarget(name: "TCRoofCoreTests", dependencies: ["TCRoofCore"]),
        .testTarget(name: "PDFReportTests", dependencies: ["PDFReport", "TCRoofCore"]),
        .testTarget(name: "DriveSyncTests", dependencies: ["DriveSync", "TCRoofCore"]),
        .testTarget(name: "ExcelExportTests", dependencies: ["ExcelExport", "TCRoofCore"], resources: [.copy("Fixtures")]),
    ]
)

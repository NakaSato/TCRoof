// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SolarSurveyKit",
    defaultLocalization: "th",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SurveyCore", targets: ["SurveyCore"]),
        .library(name: "ExcelExport", targets: ["ExcelExport"]),
        .library(name: "PDFReport", targets: ["PDFReport"]),
        .library(name: "DriveSync", targets: ["DriveSync"]),
        .library(name: "SurveyUI", targets: ["SurveyUI"]),
    ],
    targets: [
        // raw deflate / inflate / crc32 from the system zlib (iOS SDK and Linux both ship it)
        .target(name: "CZlib", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "SurveyCore"),
        .target(name: "ExcelExport", dependencies: ["SurveyCore", "CZlib"], resources: [.process("Resources")]),
        .target(name: "PDFReport", dependencies: ["SurveyCore"], resources: [.process("Resources")]),
        .target(name: "DriveSync", dependencies: ["SurveyCore"]),
        .target(name: "SurveyUI", dependencies: ["SurveyCore", "ExcelExport", "PDFReport", "DriveSync"]),
        .testTarget(name: "SurveyCoreTests", dependencies: ["SurveyCore"]),
        .testTarget(name: "PDFReportTests", dependencies: ["PDFReport", "SurveyCore"]),
        .testTarget(name: "DriveSyncTests", dependencies: ["DriveSync", "SurveyCore"]),
        .testTarget(name: "ExcelExportTests", dependencies: ["ExcelExport", "SurveyCore"], resources: [.copy("Fixtures")]),
    ]
)

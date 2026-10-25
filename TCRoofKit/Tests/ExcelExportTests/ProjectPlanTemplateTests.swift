import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The 20 import files of `Project_Plan_TCRoof/แผนโครงการ นำเข้า TCRoof` (the app's master plans, one per case):
/// each must import whole, with every formula worked out as Excel did, and export back unchanged.
/// A regenerated template (`make_template.py`) has to pass these before it's handed out.
final class ProjectPlanTemplateTests: XCTestCase {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../Project_Plan_TCRoof/แผนโครงการ นำเข้า TCRoof").standardized

    func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xlsx" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testEveryCaseIsThere() throws {
        let codes = try files().map { String($0.lastPathComponent.prefix(6)) }
        XCTAssertEqual(codes, (1...20).map { String(format: "P9-%03d", $0) })
    }

    func testEveryCaseImportsWhole() throws {
        for url in try files() {
            let name = url.lastPathComponent
            let r = try MPWorkbook.read(Data(contentsOf: url))
            XCTAssertEqual(Set(r.tasks), Set(MasterSchedule.Task.allCases), name)
            let plan = MasterSchedule.plan(r.input)
            XCTAssertEqual(plan.reduce(0) { $0 + $1.weight }, 100, accuracy: 1e-9, name)
            XCTAssertTrue(r.formulas.isComplete, "\(name): unknown \(r.formulas.unknown.prefix(3)), differs \(r.formulas.differs.prefix(3))")
            XCTAssertGreaterThan(r.formulas.count, 0, name)
            XCTAssertNotNil(MPWorkbook.station(project: r.project, fileName: name).kWp, name)

            // the case in the title: พค.2 carries weight only from 200 kVA
            let over200 = r.project?.contains("≥ 200 kVA") == true
            XCTAssertEqual(r.input.over200kVA, over200, name)
            XCTAssertEqual(r.input.weight(.pk2) > 0, over200, name)
            for t in MasterSchedule.Task.allCases where r.input.weight(t) > 0 {
                XCTAssertNotNil(r.input.fixed?[t.rawValue]?.start, "\(name): \(t.code) has weight but no start")
                XCTAssertNotNil(r.input.fixed?[t.rawValue]?.end, "\(name): \(t.code) has weight but no end")
            }
        }
    }

    func testEveryCaseExportsBackUnchanged() throws {
        for url in try files() {
            let data = try Data(contentsOf: url)
            let r = try MPWorkbook.read(data)
            let out = try MPWorkbook.export(data, input: r.input, actual: r.actual)
            XCTAssertEqual(out.changedCells, 0, url.lastPathComponent)
            XCTAssertEqual(out.data, data, url.lastPathComponent)
        }
    }
}

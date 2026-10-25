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

    func testTheAppCarriesEveryCase() throws {
        let cases = MPTemplates.cases()
        XCTAssertEqual(cases.map(\.id), (1...20).map { String(format: "P9-%03d", $0) })
        XCTAssertEqual(Set(cases.map(\.site)), ["หลังคาลอนคู่", "หลังคาเมทัลชีท", "ถังน้ำใส", "ถังดินกลบ", "Carport"])
        // per site type: HV < 200, HV ≥ 200, LV < 200, LV ≥ 200
        XCTAssertEqual(cases.prefix(4).map(\.title), ["HV", "HV", "LV", "LV"].enumerated().map {
            "หลังคาลอนคู่ | กันย้อน \($0.element) | Inverter \($0.offset % 2 == 1 ? "≥" : "<") 200 kVA"
        })
        XCTAssertEqual(cases.first?.kWp, 150.48)
        // the bundled files are the template's own
        for c in cases {
            XCTAssertEqual(try Data(contentsOf: c.url), try Data(contentsOf: Self.folder.appendingPathComponent(c.url.lastPathComponent)), c.id)
        }
    }

    func testTheTitleNamesTheCase() {
        let t = MPTemplates.parse("โครงการ … ภายใน แม่แบบ ถังน้ำใส · กันย้อน LV · Inverter ≥ 200 kVA การประปา …")
        XCTAssertEqual(t?.site, "ถังน้ำใส")
        XCTAssertEqual(t?.backfeed, "LV")
        XCTAssertEqual(t?.over200kVA, true)
        XCTAssertNil(MPTemplates.parse("Master Plan Weekly PWA สถานีผลิตน้ำประปาบางไทร"))
    }

    /// A station's plan from a case: every date moves to the kickoff picked, in the file the station keeps too.
    func testACaseMovesToTheStationsKickoff() throws {
        let cal = MasterSchedule.calendar
        let c = try XCTUnwrap(MPTemplates.cases().first { $0.id == "P9-002" })
        let template = try MPWorkbook.read(Data(contentsOf: c.url))
        let kickoff = cal.date(from: DateComponents(year: 2027, month: 1, day: 11))!
        let days = cal.dateComponents([.day], from: template.input.kickoff, to: kickoff).day!
        let (data, r) = try MPTemplates.plan(c, kickoff: kickoff)

        XCTAssertEqual(r.input.kickoff, kickoff)
        XCTAssertTrue(r.input.over200kVA)
        for t in MasterSchedule.Task.allCases {
            let was = template.input.fixed?[t.rawValue], now = r.input.fixed?[t.rawValue]
            XCTAssertEqual(now?.weight, was?.weight, t.code)
            XCTAssertEqual(now?.start, was?.start.map { cal.date(byAdding: .day, value: days, to: $0)! }, t.code)
            XCTAssertEqual(now?.end, was?.end.map { cal.date(byAdding: .day, value: days, to: $0)! }, t.code)
        }
        XCTAssertEqual(r.input.installStart, cal.date(byAdding: .day, value: days, to: template.input.installStart))
        XCTAssertTrue(r.actual.points.isEmpty)
        XCTAssertTrue(r.formulas.isComplete, "unknown \(r.formulas.unknown.prefix(3)), differs \(r.formulas.differs.prefix(3))")
        // the station's file exports back unchanged, so its next export writes only progress
        XCTAssertEqual(try MPWorkbook.export(data, input: r.input, actual: r.actual).changedCells, 0)
        // the kickoff the template already has gives the file as it is
        XCTAssertEqual(try MPTemplates.plan(c, kickoff: template.input.kickoff).data, try Data(contentsOf: c.url))
    }

    func testListingIsQuick() {
        measure { XCTAssertEqual(MPTemplates.cases().count, 20) }
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

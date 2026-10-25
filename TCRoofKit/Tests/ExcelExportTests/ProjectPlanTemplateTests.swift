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

    /// The `แผนโครงการ` sheet's work breakdown: every row, each MP task's sub-tasks adding up to its weight.
    func testEveryCaseReadsItsWBS() throws {
        for url in try files() {
            let name = url.lastPathComponent
            let r = try MPWorkbook.read(Data(contentsOf: url))
            // 4 parts, 34 task lines, 86 sub-tasks; the tables under them are other lists
            XCTAssertEqual(r.wbs.count, 124, name)
            XCTAssertEqual(r.wbs.filter { $0.level == 0 }.map(\.code), ["0", "1", "2", "3"], name)
            XCTAssertEqual(Set(r.wbs.map(\.code)).count, r.wbs.count, "\(name): codes repeat")
            for t in MasterSchedule.Task.allCases {
                let items = r.wbs.items(for: t)
                XCTAssertFalse(items.isEmpty, "\(name): \(t.code) has no sub-tasks")
                XCTAssertEqual(items.reduce(0) { $0 + $1.weight }, r.input.weight(t), accuracy: 1e-9, "\(name): \(t.code)")
            }
            // a part carries its tasks' weight (permit 5, installation 90, tests 5); part 0 (preparation) and 2.10
            // Tie-in carry none and belong to no MP task
            let parts = Dictionary(uniqueKeysWithValues: r.wbs.filter { $0.level == 0 }.map { ($0.code, $0.weight) })
            XCTAssertEqual(parts, ["0": 0, "1": 5, "2": 90, "3": 5], name)
            for item in r.wbs where item.task == nil && item.level > 0 {
                XCTAssertTrue(item.code.hasPrefix("0.") || item.code.hasPrefix("2.10"), "\(name): \(item.code)")
                XCTAssertEqual(item.weight, 0, "\(name): \(item.code)")
            }
            // the MP task's line keeps the plan's dates
            let structure = try XCTUnwrap(r.wbs.first { $0.code == "2.1" }, name)
            XCTAssertEqual(structure.baselineStart, r.input.fixed?["structure"]?.start, name)
            XCTAssertEqual(structure.baselineEnd, r.input.fixed?["structure"]?.end, name)
        }
    }

    func testTheWBSRowsAsTheSheetHasThem() throws {
        let hv = try MPWorkbook.read(Data(contentsOf: files()[0])).wbs        // P9-001 HV < 200
        let lv = try MPWorkbook.read(Data(contentsOf: files()[2])).wbs        // P9-003 LV < 200
        let survey = try XCTUnwrap(hv.first { $0.code == "1.1.3" })
        XCTAssertEqual(survey.title, "แบบสำรวจหน้างาน A1–E1 (REV 00)")
        XCTAssertEqual(survey.evidence, "แบบสำรวจ A1–E1 ลงนาม 2 ฝ่าย ออก REV 00")
        XCTAssertEqual(survey.responsible, "วศ.")
        XCTAssertEqual(survey.weight, 0.2, accuracy: 1e-9)
        XCTAssertEqual(survey.level, 2)
        XCTAssertEqual(survey.task, .kickoff)
        XCTAssertEqual(survey.evidenceKinds, ["site_map"])
        XCTAssertEqual(hv.first { $0.code == "1.7.1" }?.task, .gridConnection)
        XCTAssertEqual(hv.first { $0.code == "1.7.6" }?.isMilestone, true)
        // กันย้อน on the pole is HV's, the LV relay LV's: the other case's rows are marked and weigh nothing
        XCTAssertEqual(hv.first { $0.code == "2.8.6" }?.notForThisStation, true)
        XCTAssertEqual(hv.first { $0.code == "2.8.2" }?.notForThisStation, false)
        XCTAssertEqual(lv.first { $0.code == "2.8.2" }?.notForThisStation, true)
        XCTAssertEqual(lv.first { $0.code == "2.8.2" }?.weight, 0)
        // พค.2 under 200 kVA
        XCTAssertEqual(hv.items(for: .pk2).allSatisfy { $0.weight == 0 }, true)
    }

    func testAPlanWithoutTheSheetHasNoWBS() throws {
        let bangsai = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mp-weekly-bangsai.xlsx")
        XCTAssertEqual(try MPWorkbook.read(Data(contentsOf: bangsai)).wbs, [])
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

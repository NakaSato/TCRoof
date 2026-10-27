import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The 20 install cases (`Project_Plan_TCRoof/3_แม่แบบ 20 กรณี`, bundled as `CaseTemplates`): 5 site types × กันย้อน
/// HV / LV × Inverter < / ≥ 200 kVA. Each must import whole and export back unchanged; they differ in the permits and,
/// through `applySite`, in 2.1's steps; their example figures never reach a station.
final class CaseTemplateTests: XCTestCase {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../Project_Plan_TCRoof/3_แม่แบบ 20 กรณี/แผนโครงการ นำเข้า TCRoof").standardized
    static let sites = ["หลังคาลอนคู่", "หลังคาเมทัลชีท", "ถังน้ำใส", "ถังดินกลบ", "Carport"]

    func cases() -> [MPTemplates.Case] { MPTemplates.installCases(in: Self.folder) }

    func testTheTwentyCasesAreEveryCombination() throws {
        let cases = cases()
        XCTAssertEqual(cases.map(\.id), (1...20).map { String(format: "P9-%03d", $0) })
        var seen = Set<String>()
        for c in cases {
            XCTAssertTrue(Self.sites.contains(c.site), c.id)
            XCTAssertTrue(["HV", "LV"].contains(c.backfeed), c.id)
            seen.insert("\(c.site)|\(c.backfeed)|\(c.over200kVA)")
        }
        XCTAssertEqual(seen.count, 20, "one file per combination")
        // the order of the files: site by site, HV before LV, < 200 before ≥ 200
        XCTAssertEqual(cases[0].title, "หลังคาลอนคู่ | กันย้อน HV | Inverter < 200 kVA")
        XCTAssertEqual(cases[1].title, "หลังคาลอนคู่ | กันย้อน HV | Inverter ≥ 200 kVA")
        XCTAssertEqual(cases[19].title, "Carport | กันย้อน LV | Inverter ≥ 200 kVA")
        // the app bundles the same files
        XCTAssertEqual(MPTemplates.installCases().map(\.id), cases.map(\.id))
        // the station list doesn't take the cases for stations
        XCTAssertNil(MPTemplates.best(for: "แม่แบบ หลังคาลอนคู่", code: "", in: cases))
    }

    func testEveryCaseImportsWholeAndExportsBackUnchanged() throws {
        for c in cases() {
            let original = try Data(contentsOf: c.url)
            let r = try MPWorkbook.read(original)
            XCTAssertEqual(Set(r.tasks), Set(MasterSchedule.Task.allCases), c.id)
            XCTAssertTrue(r.formulas.differs.isEmpty && r.formulas.unknown.isEmpty, "\(c.id) formulas")
            XCTAssertEqual(r.input.over200kVA, c.over200kVA, c.id)
            XCTAssertFalse(r.wbs.isEmpty, c.id)
            XCTAssertEqual(try MPWorkbook.export(original, input: r.input, actual: r.actual).data, original, c.id)
            // an example station: nothing of it is a station's
            XCTAssertTrue(r.setup.isTemplate, c.id)
            XCTAssertNil(r.setup.stationName, c.id)
            XCTAssertNil(r.setup.branch, c.id)
            XCTAssertNil(r.setup.kWp, c.id)
            XCTAssertTrue(r.setup.points.isEmpty, c.id)
            XCTAssertEqual(r.setup.changes(for: .init()), [], c.id)
        }
    }

    /// The permit schedule: ≥ 200 kVA weighs พค.2 (1.5) and takes it from 1.4 and 1.7; LV marks the 22 kV rows.
    func testThePermitsFollowTheCase() throws {
        func read(_ id: String) throws -> MPWorkbook.Imported {
            try MPWorkbook.read(Data(contentsOf: XCTUnwrap(cases().first { $0.id == id }).url))
        }
        let small = try read("P9-001"), big = try read("P9-002"), lv = try read("P9-003")
        XCTAssertEqual(small.input.weight(.pk2), 0)
        XCTAssertEqual(big.input.weight(.pk2), 1)
        XCTAssertEqual(small.input.weight(.buildingPermit), 1.5)
        XCTAssertEqual(big.input.weight(.buildingPermit), 1)
        XCTAssertEqual(MasterSchedule.Task.allCases.map(small.input.weight).reduce(0, +), 100, accuracy: 1e-9)
        XCTAssertEqual(MasterSchedule.Task.allCases.map(big.input.weight).reduce(0, +), 100, accuracy: 1e-9)
        // พค.2's own steps are for the ≥ 200 kVA case only
        XCTAssertTrue(small.wbs.first { $0.code == "1.5.1" }?.notForThisStation == true)
        XCTAssertFalse(big.wbs.first { $0.code == "1.5.1" }?.notForThisStation ?? true)
        // the 22 kV rows are HV's
        for code in ["0.2.7", "2.8.1"] {
            XCTAssertFalse(small.wbs.first { $0.code == code }?.notForThisStation ?? true, code)
            XCTAssertTrue(lv.wbs.first { $0.code == code }?.notForThisStation == true, code)
        }
    }

    /// The construction: 2.1's steps are the case's site type's (`site-steps.json`, from the master's จุดติดตั้ง).
    func testTwoOneTakesTheSiteTypesSteps() throws {
        for c in cases() where !c.over200kVA && c.backfeed == "HV" {
            let r = try MPWorkbook.read(Data(contentsOf: c.url))
            let steps = try XCTUnwrap(MPTemplates.siteSteps[c.site], c.site)
            let line = try XCTUnwrap(r.wbs.first { $0.code == "2.1" })
            for s in steps {
                let item = try XCTUnwrap(r.wbs.first { $0.code == "2.1.\(s.step)" }, "\(c.site) 2.1.\(s.step)")
                XCTAssertEqual(item.title, s.title, "\(c.site) 2.1.\(s.step)")
                XCTAssertEqual(item.weight, line.weight * s.percent / 100, accuracy: 1e-9)
            }
        }
        // the tank's steps are not the roof's
        XCTAssertNotEqual(MPTemplates.siteSteps["ถังดินกลบ"]?.first?.title, MPTemplates.siteSteps["หลังคาลอนคู่"]?.first?.title)
    }

    func testAStationGetsItsCase() throws {
        let cases = cases()
        func pick(_ site: String?, _ backfeed: String?, _ big: Bool) -> String? {
            MPTemplates.suggest(site: site, backfeed: backfeed, over200kVA: big, among: cases)?.id
        }
        XCTAssertEqual(pick("ถังน้ำใส", "LV", true), "P9-012")
        XCTAssertEqual(pick("Carport", "HV", false), "P9-017")
        // a site type no case has gives way first, then the zero export
        XCTAssertEqual(pick("หลังคา", "LV", false), "P9-003")
        XCTAssertEqual(pick(nil, nil, true), "P9-002")
        // the main site type: the most kWp, else the most locations
        let types = Self.sites
        XCTAssertEqual(MPTemplates.mainSite(points: [.init(type: "หลังคาลอนคู่", count: 3, modules: 140, kWp: 79.8),
                                                     .init(type: "ถังน้ำใส", count: 1, modules: 146, kWp: 83.22)],
                                            locations: [], among: types), "ถังน้ำใส")
        XCTAssertEqual(MPTemplates.mainSite(points: [], locations: ["หลังคาลอนคู่ 1", "หลังคาลอนคู่ 2", "Carport 1"], among: types),
                       "หลังคาลอนคู่")
        XCTAssertNil(MPTemplates.mainSite(points: [], locations: ["ห้องอินเวอร์เตอร์"], among: types))
    }

    /// A station's plan begun from a case comes out naming the station: title, set-up line and PROJECT.
    func testACaseExportedForAStationNamesIt() throws {
        let c = try XCTUnwrap(cases().first { $0.id == "P9-009" })
        let moved = try MPTemplates.plan(c, kickoff: MasterSchedule.calendar.date(from: DateComponents(year: 2027, month: 3, day: 1)))
        XCTAssertEqual(moved.imported.wbsDone, [])
        var t = ProjectSetup.Target(stationName: "สถานีผลิตน้ำทดสอบ", kWp: 120.5, customerName: "กปภ.สาขาทดสอบ", inverterKW: 100)
        t.station.zeroExport = "HV"
        let out = try MPWorkbook.export(moved.data, input: moved.imported.input, actual: moved.imported.actual, setup: ProjectSetup(t))
        let back = try MPWorkbook.read(out.data)
        XCTAssertFalse(back.setup.isTemplate)
        XCTAssertEqual(back.setup.stationName, "สถานีผลิตน้ำทดสอบ")
        XCTAssertEqual(back.setup.kWp, 120.5)
        XCTAssertEqual(back.setup.branch, "กปภ.สาขาทดสอบ")
        XCTAssertEqual(back.setup.inverterKW, 100)
        XCTAssertNil(back.setup.code, "the case's code isn't the station's")
        // the case's roles (วศ.09, Admin, ผรม. 09) are no one's
        XCTAssertNil(back.setup.engineer)
        XCTAssertNil(back.setup.admin)
        XCTAssertNil(back.setup.contractor)
        let project = try XCTUnwrap(back.project)
        XCTAssertTrue(project.contains("สถานีผลิตน้ำทดสอบ") && project.contains("สาขาทดสอบ") && project.contains("120.5 kWp"), project)
        XCTAssertFalse(project.contains("แม่แบบ") || project.contains("ตัวอย่าง"), project)
        // a job with no name leaves a case's title as it is
        XCTAssertEqual(ProjectSetup().rewrite(title: "แผนโครงการ P9-009 – แม่แบบ ถังน้ำใส, กันย้อน HV, Inverter < 200 kVA 150.48 kWp"),
                       "แผนโครงการ P9-009 – แม่แบบ ถังน้ำใส, กันย้อน HV, Inverter < 200 kVA 150.48 kWp")
    }

    func testPlaceholdersAreNotFacts() {
        let s = ProjectSetup.parse(title: nil, line: "กปภ.สาขา (ตัวอย่าง), ตัวอย่าง, กฟภ. เขต ตย.01, Inverter 125 kW (ไม่ต้อง พค.2), Zero export HV, คำขอ -")
        XCTAssertNil(s.branch)
        XCTAssertNil(s.area)
        XCTAssertNil(s.peaZone)
        XCTAssertNil(s.ppimRequest)
        XCTAssertEqual(s.inverterKW, 125)
        XCTAssertEqual(s.zeroExport, "HV")
        let roles = ProjectSetup.parse(title: nil, line: "Zero export LV, วิศวกร วศ.01, Admin Admin, ผรม. 01")
        XCTAssertNil(roles.engineer)
        XCTAssertNil(roles.admin)
        XCTAssertNil(roles.contractor)
        let people = ProjectSetup.parse(title: nil, line: "Zero export LV, วิศวกร เปรม, Admin บีม, ผรม. B")
        XCTAssertEqual([people.engineer, people.admin, people.contractor], ["เปรม", "บีม", "B"])
    }
}

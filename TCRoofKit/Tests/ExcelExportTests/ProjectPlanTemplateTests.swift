import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The 102 import files of `Project_Plan_TCRoof/2_แผนนำเข้า TCRoof (102 สถานี)` (one plan per PWA station, phases 3–4):
/// each must import whole, with every formula worked out as Excel did, and export back unchanged.
/// A regenerated set has to pass these before it's handed out.
final class ProjectPlanTemplateTests: XCTestCase {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../Project_Plan_TCRoof/2_แผนนำเข้า TCRoof (102 สถานี)").standardized

    func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xlsx" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static let codes = (1...45).map { String(format: "P3-%03d", $0) } + (1...57).map { String(format: "P4-%03d", $0) }

    func testEveryCaseIsThere() throws {
        let codes = try files().map { String($0.lastPathComponent.prefix(6)) }
        XCTAssertEqual(codes, Self.codes)
    }

    func testEveryCaseImportsWhole() throws {
        let cases = Dictionary(uniqueKeysWithValues: MPTemplates.cases(in: Self.folder).map { ($0.url.lastPathComponent, $0) })
        for url in try files() {
            let name = url.lastPathComponent
            let r = try MPWorkbook.read(Data(contentsOf: url))
            XCTAssertEqual(Set(r.tasks), Set(MasterSchedule.Task.allCases), name)
            let plan = MasterSchedule.plan(r.input)
            XCTAssertEqual(plan.reduce(0) { $0 + $1.weight }, 100, accuracy: 1e-9, name)
            XCTAssertTrue(r.formulas.isComplete, "\(name): unknown \(r.formulas.unknown.prefix(3)), differs \(r.formulas.differs.prefix(3))")
            XCTAssertGreaterThan(r.formulas.count, 0, name)
            XCTAssertNotNil(MPWorkbook.station(project: r.project, fileName: name).kWp, name)

            // the station's line: พค.2 carries weight only from 200 kVA (`ต้องยื่น พค.2`)
            let over200 = try XCTUnwrap(cases[name], name).over200kVA
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
            // 4 parts, 34 task lines, 86 sub-tasks, and the Inverter station's 6 steps under 2.5.1; the installation
            // points are left out
            XCTAssertEqual(r.wbs.count, 130, name)
            XCTAssertEqual(r.wbs.filter { $0.level == 0 }.map(\.code), ["0", "1", "2", "3"], name)
            XCTAssertEqual(Set(r.wbs.map(\.code)).count, r.wbs.count, "\(name): codes repeat")
            for t in MasterSchedule.Task.allCases {
                let items = r.wbs.items(for: t)
                XCTAssertFalse(items.isEmpty, "\(name): \(t.code) has no sub-tasks")
                // a row with steps under it is their sum: count the steps, not it
                let parents = r.wbs.parentCodes
                XCTAssertEqual(items.filter { !parents.contains($0.code) }.reduce(0) { $0 + $1.weight }, r.input.weight(t),
                               accuracy: 1e-9, "\(name): \(t.code)")
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
        let hv = try MPWorkbook.read(Data(contentsOf: files()[0])).wbs        // P3-001 HV < 200
        let lv = try MPWorkbook.read(Data(contentsOf: files()[2])).wbs        // P3-003 LV < 200
        let survey = try XCTUnwrap(hv.first { $0.code == "1.1.3" })
        XCTAssertEqual(survey.title, "แบบสำรวจหน้างาน A1–E1 (REV 00)")
        XCTAssertEqual(survey.evidence, "แบบสำรวจ A1–E1 ลงนาม 2 ฝ่าย ออก REV 00")
        XCTAssertEqual(survey.responsible, "วศ.")
        XCTAssertEqual(survey.weight, 0.2, accuracy: 1e-9)
        XCTAssertEqual(survey.level, 2)
        XCTAssertEqual(survey.task, .kickoff)
        // the station files carry no `หลักฐาน:` notes (the example set did); nothing reads them yet
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

    /// The Inverter station table under the list: its six steps follow 2.5.1, each its share of 2.5.1's weight, and
    /// 2.5.1's note names the station's type.
    func testTheInverterStationStepsFollowTheirRow() throws {
        let wbs = try MPWorkbook.read(Data(contentsOf: files()[0])).wbs        // P3-001: 80+80 kW
        let i = try XCTUnwrap(wbs.firstIndex { $0.code == "2.5.1" })
        let station = wbs[i]
        XCTAssertEqual(wbs[(i + 1)...(i + 6)].map(\.code), (1...6).map { "2.5.1.\($0)" })
        let steps = Array(wbs[(i + 1)...(i + 6)])
        XCTAssertEqual(steps.reduce(0) { $0 + $1.weight }, station.weight, accuracy: 1e-9)
        XCTAssertEqual(steps[2].weight, station.weight * 0.3, accuracy: 1e-9)
        XCTAssertEqual(steps[2].note, "30% ของ 2.5.1")
        XCTAssertEqual(steps.map(\.level), Array(repeating: station.level + 1, count: 6))
        XCTAssertEqual(steps.map(\.task), Array(repeating: .inverter, count: 6))
        // the note names the station's own inverters and house
        XCTAssertTrue(station.note?.contains("80+80 kW") == true, station.note ?? "")
        XCTAssertTrue(station.note?.contains("E09") == true, station.note ?? "")
        XCTAssertTrue(wbs.parentCodes.contains("2.5.1"))
        XCTAssertFalse(wbs.contains { $0.title.hasPrefix("หลังคาลอนคู่") }, "the installation points stay out")
    }

    /// 2.1's sub-tasks for a site type (the full workbook's `จุดติดตั้ง` table): a clear water tank's topping footings,
    /// a buried tank's digging, each weighing its share of 2.1. The station files don't name their site type, so their
    /// 2.1 stays generic; `applySite` gives a station's rows its type's steps.
    func testTheStructureSubTasksFollowTheSiteType() throws {
        XCTAssertEqual(Set(MPTemplates.siteSteps.keys), ["หลังคาลอนคู่", "หลังคาเมทัลชีท", "หลังคา", "ถังน้ำใส", "ถังดินกลบ", "Carport"])
        for (site, steps) in MPTemplates.siteSteps {
            XCTAssertEqual(steps.map(\.step), Array(1...7), site)
            XCTAssertEqual(steps.reduce(0) { $0 + $1.percent }, 100, accuracy: 1e-9, site)
        }
        let wbs = try MPWorkbook.read(Data(contentsOf: files()[0])).wbs
        let line = try XCTUnwrap(wbs.first { $0.code == "2.1" })
        var titles: [String: [String]] = [:]
        for (site, steps) in MPTemplates.siteSteps {
            let subs = MPTemplates.applySite(site, to: wbs).items(for: .structure)
            XCTAssertEqual(subs.map(\.title), steps.map(\.title), site)
            XCTAssertEqual(subs.reduce(0) { $0 + $1.weight }, line.weight, accuracy: 1e-9, site)
            XCTAssertNotNil(subs[2].evidence, "\(site): the generic row's evidence stays")
            titles[site] = subs.map(\.title)
        }
        XCTAssertEqual(Set(titles.values.map { $0 }).count, titles.count, "every site type has its own list")
        XCTAssertTrue(titles["ถังน้ำใส"]?[2].hasPrefix("ฐาน Concrete topping") == true)
    }

    func testAPlanWithoutTheSheetHasNoWBS() throws {
        let bangsai = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mp-weekly-bangsai.xlsx")
        XCTAssertEqual(try MPWorkbook.read(Data(contentsOf: bangsai)).wbs, [])
    }

    func testTheAppCarriesEveryCase() throws {
        let cases = MPTemplates.cases()
        XCTAssertEqual(cases.map(\.id), Self.codes)
        let first = try XCTUnwrap(cases.first)
        XCTAssertEqual(first.name, "สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล")
        XCTAssertEqual(first.kWp, 163.02)
        XCTAssertEqual(first.branch, "กปภ.สาขาชัยบาดาล")
        XCTAssertEqual(first.backfeed, "HV")
        XCTAssertFalse(first.over200kVA)
        XCTAssertEqual(first.site, "")
        XCTAssertEqual(first.title, first.name)
        XCTAssertEqual(cases.filter(\.over200kVA).count, 42)
        XCTAssertEqual(cases.filter { $0.backfeed == "LV" }.count, 47)
        // the bundled files are the set's own
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

    /// A station file's two lines: the code, station and kWp, then สาขา … Inverter … Zero export.
    func testTheStationLines() {
        let xml = "<sst><si><t>แผนโครงการ P4-023 – สถานีผลิตน้ำหนองปลาไหล 2 940.50 kWp</t></si>"
            + "<si><t>กปภ.สาขาพัทยา, ภาคเหนือ-กลาง, กฟภ. เขต ก.2, Inverter 830 kW (ต้องยื่น พค.2), Zero export HV, ผรม. C</t></si></sst>"
        let s = MPTemplates.station(in: xml)
        XCTAssertEqual(s?.name, "สถานีผลิตน้ำหนองปลาไหล 2")
        XCTAssertEqual(s?.kWp, 940.5)
        XCTAssertEqual(s?.backfeed, "HV")
        XCTAssertEqual(s?.over200kVA, true)
        XCTAssertNil(MPTemplates.station(in: "<sst><si><t>Master Plan Weekly</t></si></sst>"))
    }

    /// A station opens on its own file: by its code, else by its name.
    func testAStationFindsItsOwnFile() {
        let cases = MPTemplates.cases()
        XCTAssertEqual(MPTemplates.best(for: "อะไรก็ได้", code: "P4-049", in: cases)?.id, "P4-049")
        XCTAssertEqual(MPTemplates.best(for: "สถานีจ่ายน้ำแพรกหนามแดง", code: "MP 190", in: cases)?.id, "P4-049")
        XCTAssertEqual(MPTemplates.best(for: "สถานีผลิตน้ำประปาบางไทร", code: "MP 189", in: cases)?.id, nil)
        XCTAssertTrue(cases.first { $0.id == "P4-049" }?.matches("แพรก") == true)
        XCTAssertTrue(cases.first { $0.id == "P4-049" }?.matches("สมุทรสงคราม") == true)
    }

    /// A station's plan from a case: every date moves to the kickoff picked, in the file the station keeps too.
    func testACaseMovesToTheStationsKickoff() throws {
        let cal = MasterSchedule.calendar
        let c = try XCTUnwrap(MPTemplates.cases().first { $0.id == "P3-006" })     // HV ≥ 200 kVA
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
        // the WBS rows move with the plan
        let wbs21 = try XCTUnwrap(r.wbs.first { $0.code == "2.1" }), was21 = try XCTUnwrap(template.wbs.first { $0.code == "2.1" })
        XCTAssertEqual(wbs21.baselineStart, was21.baselineStart.map { cal.date(byAdding: .day, value: days, to: $0)! })
        XCTAssertEqual(wbs21.baselineStart, r.input.fixed?["structure"]?.start)
        XCTAssertTrue(r.formulas.isComplete, "unknown \(r.formulas.unknown.prefix(3)), differs \(r.formulas.differs.prefix(3))")
        // the station's file exports back unchanged, so its next export writes only progress
        XCTAssertEqual(try MPWorkbook.export(data, input: r.input, actual: r.actual).changedCells, 0)
        // the kickoff the template already has gives the file as it is
        XCTAssertEqual(try MPTemplates.plan(c, kickoff: template.input.kickoff).data, try Data(contentsOf: c.url))
    }

    func testListingIsQuick() {
        measure { XCTAssertEqual(MPTemplates.cases().count, 102) }
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

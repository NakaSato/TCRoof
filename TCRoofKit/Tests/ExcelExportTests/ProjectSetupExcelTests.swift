import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The project facts `MPWorkbook.read` takes from a station's plan file (`ProjectSetup`): the 102 station files'
/// title and set-up lines, installation points and Inverter station, and the older Master Plan Weekly's lines.
final class ProjectSetupExcelTests: XCTestCase {
    func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: ProjectPlanTemplateTests.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xlsx" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func file(_ code: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(files().first { $0.lastPathComponent.hasPrefix(code) }))
    }

    func testP3001() throws {
        let s = try MPWorkbook.read(file("P3-001")).setup
        XCTAssertEqual(s.code, "P3-001")
        XCTAssertEqual(s.stationName, "สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล")
        XCTAssertEqual(s.kWp, 163.02)
        XCTAssertEqual(s.branch, "กปภ.สาขาชัยบาดาล")
        XCTAssertEqual(s.area, "ภาคเหนือ-กลาง")
        XCTAssertEqual(s.peaZone, "กฟภ. เขต น.3")
        XCTAssertEqual(s.inverterKW, 160)
        XCTAssertEqual(s.needsPK2, false)
        XCTAssertEqual(s.zeroExport, "HV")
        XCTAssertEqual(s.ppimRequest, "PPIM1A5072BC")
        XCTAssertEqual(s.engineer, "เปรม")
        XCTAssertEqual(s.admin, "บีม")
        XCTAssertEqual(s.contractor, "B")
        XCTAssertEqual(s.owner, "การประปาส่วนภูมิภาค")
        XCTAssertEqual(s.points, [.init(type: "หลังคาลอนคู่", count: 3, modules: 140, kWp: 79.8),
                                  .init(type: "ถังน้ำใส", count: 1, modules: 146, kWp: 83.22)])
        XCTAssertEqual(s.inverterStation, "สร้างใหม่ (E09)")
        XCTAssertTrue(s.inverterStationDetail?.hasPrefix("80+80 kW") == true)
    }

    /// Every station file gives every part of its set-up line, and the part agrees with what the template list reads.
    func testEveryStationFileGivesItsWholeSetUp() throws {
        let cases = Dictionary(uniqueKeysWithValues: MPTemplates.cases(in: ProjectPlanTemplateTests.folder).map { ($0.id, $0) })
        var pk2 = 0
        for url in try files() {
            let code = String(url.lastPathComponent.prefix(6))
            let s = try MPWorkbook.read(Data(contentsOf: url)).setup
            XCTAssertEqual(s.code, code)
            for (name, value) in [("name", s.stationName), ("branch", s.branch), ("area", s.area), ("pea", s.peaZone),
                                  ("zero", s.zeroExport), ("ppim", s.ppimRequest), ("engineer", s.engineer),
                                  ("admin", s.admin), ("contractor", s.contractor), ("owner", s.owner)] {
                XCTAssertFalse(value?.isEmpty ?? true, "\(code) \(name)")
            }
            let c = try XCTUnwrap(cases[code])
            XCTAssertEqual(s.stationName, c.name, code)
            XCTAssertEqual(s.kWp, c.kWp, code)
            XCTAssertEqual(s.zeroExport, c.backfeed, code)
            XCTAssertEqual(s.needsPK2, c.over200kVA, code)
            // the file's word on พค.2 is the inverter size's
            XCTAssertEqual(s.needsPK2, (s.inverterKW ?? 0) >= 200, code)
            if s.needsPK2 == true { pk2 += 1 }
            XCTAssertTrue(["HV", "LV"].contains(s.zeroExport ?? ""), code)
            XCTAssertTrue(s.area?.hasPrefix("ภาค") == true, code)
            XCTAssertTrue(s.peaZone?.hasPrefix("กฟภ. เขต") == true, code)
        }
        XCTAssertEqual(pk2, 42)
    }

    /// A Master Plan Weekly without the `แผนโครงการ` sheet gives what its `PROJECT` and `OWNER` lines say.
    func testAnOlderPlanFileGivesItsProjectLine() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/mp-weekly-bangsai", withExtension: "xlsx"))
        let s = try MPWorkbook.read(Data(contentsOf: url)).setup
        XCTAssertTrue(s.stationName?.contains("บางไทร") == true)
        XCTAssertEqual(s.owner, "การประปาส่วนภูมิภาคสาขาพระนครศรีอยุธยา")
        XCTAssertNil(s.code)
        XCTAssertNil(s.inverterKW)
        XCTAssertTrue(s.points.isEmpty)
    }

    /// The job's facts as the file's own: export gives back the very same file.
    func testAStationThatTookItsFileExportsItUnchanged() throws {
        let original = try file("P3-001")
        let r = try MPWorkbook.read(original)
        var t = ProjectSetup.Target()
        r.setup.apply(Set(ProjectSetup.Field.allCases), to: &t)
        let out = try MPWorkbook.export(original, input: r.input, actual: r.actual, setup: ProjectSetup(t))
        XCTAssertEqual(out.changedCells, 0)
        XCTAssertEqual(out.data, original)
    }

    /// A plan begun from another station's file (moved to its kickoff) comes out naming the station it was exported for.
    func testATemplateFromAnotherStationNamesTheJobsStation() throws {
        let c = try XCTUnwrap(MPTemplates.cases(in: ProjectPlanTemplateTests.folder).first { $0.id == "P3-028" })
        let moved = try MPTemplates.plan(c, kickoff: MasterSchedule.calendar.date(from: DateComponents(year: 2027, month: 1, day: 4)))
        var t = ProjectSetup.Target(stationName: "สถานีทดสอบใหม่", kWp: 99.75, customerName: "กปภ.สาขาทดสอบ", inverterKW: 250)
        t.station.code = "P9-001"
        t.station.ppimRequest = "PPIMTEST"
        t.routine.subcontractor = "S"
        t.routine.siteEngineer = "ทดสอบ"
        let job = ProjectSetup(t)
        let p3028Branch = try XCTUnwrap(MPWorkbook.read(moved.data).setup.branch)
        let out = try MPWorkbook.export(moved.data, input: moved.imported.input, actual: moved.imported.actual, setup: job)
        XCTAssertGreaterThan(out.changedCells, 0)
        let back = try MPWorkbook.read(out.data)
        XCTAssertEqual(back.setup.code, "P9-001")
        XCTAssertEqual(back.setup.stationName, "สถานีทดสอบใหม่")
        XCTAssertEqual(back.setup.kWp, 99.75)
        XCTAssertEqual(back.setup.branch, "กปภ.สาขาทดสอบ")
        XCTAssertEqual(back.setup.inverterKW, 250)
        XCTAssertEqual(back.setup.needsPK2, true)
        XCTAssertEqual(back.setup.ppimRequest, "PPIMTEST")
        XCTAssertEqual(back.setup.contractor, "S")
        XCTAssertEqual(back.setup.engineer, "ทดสอบ")
        // what the job has nothing for stays as the file had it
        let p3028 = try MPWorkbook.read(moved.data).setup
        XCTAssertEqual(back.setup.area, p3028.area)
        XCTAssertEqual(back.setup.peaZone, p3028.peaZone)
        // the plan sheet's lines too: the import's station check reads PROJECT
        XCTAssertTrue(back.project?.contains("สถานีทดสอบใหม่") == true, back.project ?? "")
        XCTAssertTrue(back.project?.contains("99.75 kWp") == true, back.project ?? "")
        XCTAssertTrue(back.project?.contains("สาขาทดสอบ") == true, back.project ?? "")
        XCTAssertFalse(back.project?.contains(ProjectSetup.branchName(p3028Branch)) == true, back.project ?? "")
        let station = MPWorkbook.station(project: back.project, fileName: "x.xlsx")
        XCTAssertNotNil(MPWorkbook.match(station, among: [.init(id: "j", name: "สถานีทดสอบใหม่", mpNumber: nil, kWp: 99.75)]).pick)
        // the plan itself is the moved plan, with none of P3-028's ticks: its export clears their Y, the station's 6 steps too
        XCTAssertEqual(back.input.installStart, moved.imported.input.installStart)
        XCTAssertEqual(moved.imported.wbsDone, [])
        XCTAssertFalse(try MPWorkbook.read(moved.data).wbsDone.isEmpty, "the moved file still has P3-028's Y")
        let ticked = try MPWorkbook.export(moved.data, input: moved.imported.input, actual: moved.imported.actual, ticks: [:])
        XCTAssertEqual(try MPWorkbook.read(ticked.data).wbsDone, [])
    }
}

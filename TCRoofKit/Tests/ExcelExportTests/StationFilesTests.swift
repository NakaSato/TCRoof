import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// `เพิ่มสถานีจากไฟล์แผน`: which of the 102 station files the app doesn't have yet (`MPTemplates.missing`), and what a
/// station made from its own file holds.
final class StationFilesTests: XCTestCase {
    func cases() -> [MPTemplates.Case] { MPTemplates.cases(in: ProjectPlanTemplateTests.folder) }

    func testAnEmptyAppMissesEveryStation() {
        let all = cases()
        XCTAssertEqual(all.count, 102)
        XCTAssertEqual(MPTemplates.missing([], among: all).map(\.id), all.map(\.id))
        // the bundled files are the same 102
        XCTAssertEqual(MPTemplates.cases().map(\.id), all.map(\.id))
    }

    func testAStationIsFoundByCodeOrByNameAndKWp() {
        let all = cases()
        let existing: [MPTemplates.Existing] = [
            // by its code, whatever its name
            .init(name: "งานทดสอบ", codes: "TCR2569-48213 P3-005", kWp: nil),
            // by name, the file's own words and its kWp
            .init(name: "สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล", codes: "TCR2569-51234", kWp: 163.02),
            // a name two files share is told apart by kWp: P4-031 (400.14), not P4-001 (136.8)
            .init(name: "สถานีผลิตน้ำศูนย์ราชการ", codes: "", kWp: 400.14),
            // a unique name without kWp is enough
            .init(name: "สถานีผลิตน้ำนายาง", codes: "", kWp: 0),
            // a shared name without kWp is no one's
            .init(name: "สถานีผลิตน้ำศูนย์ราชการ", codes: "", kWp: nil),
            // the app's test jobs (the team's Firebase has these) are none of them
            .init(name: "สถานีผลิตน้ำพระบาทสระ 1", codes: "TCR2569-71422", kWp: 254.22),
            .init(name: "ทดสอบ", codes: "", kWp: 258),
            .init(name: "ยังไม่ได้ตั้งชื่อโครงการ", codes: "", kWp: 0)
        ]
        let missing = Set(MPTemplates.missing(existing, among: all).map(\.id))
        XCTAssertEqual(Set(all.map(\.id)).subtracting(missing), ["P3-005", "P3-001", "P4-031", "P4-044"])
        XCTAssertTrue(missing.contains("P4-001"))
        XCTAssertEqual(missing.count, 98)
    }

    /// What `MPStationFilesSheet` gives a new station: its own file, dates and progress kept, and the file's facts,
    /// the station code among them, which the Master Plan sheet pairs it by.
    func testAStationsOwnFileGivesItsPlanAndFacts() throws {
        let c = try XCTUnwrap(cases().first { $0.id == "P3-005" })
        let r = try MPTemplates.plan(c, kickoff: nil)
        XCTAssertEqual(r.data, try Data(contentsOf: c.url), "the file as it is")
        var t = ProjectSetup.Target(stationName: c.name, kWp: c.kWp ?? 0, customerName: c.branch)
        let fields = ProjectSetup.defaultFields(r.imported.setup.changes(for: t))
        r.imported.setup.apply(fields, to: &t)
        XCTAssertEqual(t.station.code, "P3-005")
        XCTAssertEqual(t.stationName, "สถานีผลิตน้ำบ้านนา")
        XCTAssertEqual(t.kWp, 88.92)
        XCTAssertEqual(c.branch, "กปภ.สาขาบ้านนา")
        XCTAssertFalse(r.imported.wbs.isEmpty)
    }
}

import XCTest
@testable import TCRoofCore

/// A plan file's project facts (`ProjectSetup`): its title and set-up lines read and written back, and the facts taken
/// into a job (`changes`, `apply`).
final class ProjectSetupTests: XCTestCase {
    static let title = "แผนโครงการ P3-001 – สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล 163.02 kWp"
    static let line = "กปภ.สาขาชัยบาดาล, ภาคเหนือ-กลาง, กฟภ. เขต น.3, Inverter 160 kW (ไม่ต้อง พค.2), Zero export HV, "
        + "คำขอ PPIM1A5072BC, วิศวกร เปรม, Admin บีม, ผรม. B"

    func p3001() -> ProjectSetup { .parse(title: Self.title, line: Self.line) }

    func testTheLinesRead() {
        let s = p3001()
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
    }

    func testPartsAreFoundByTheirWordsNotTheirPlace() {
        let s = ProjectSetup.parse(title: nil, line: "ผรม. S, Inverter 1250.5 kW (ต้องยื่น พค.2), something else, Zero export LV")
        XCTAssertEqual(s.contractor, "S")
        XCTAssertEqual(s.inverterKW, 1250.5)
        XCTAssertEqual(s.needsPK2, true)
        XCTAssertEqual(s.zeroExport, "LV")
        XCTAssertNil(s.branch)
        XCTAssertTrue(ProjectSetup.parse(title: "Master Plan Weekly", line: "").isEmpty)
        XCTAssertTrue(ProjectSetup.isSetupLine(Self.line))
        XCTAssertFalse(ProjectSetup.isSetupLine("ถัดไป: ◆ ผลพิจารณาแบบ กฟภ."))
    }

    func testTheCodeLineFillsOnlyWhatIsMissing() {
        var s = ProjectSetup()
        s.readCodeLine(": P3-001, ผรม. B, วิศวกร เปรม, ข้อมูล ณ 19/10/2026 (Plan = Baseline)")
        XCTAssertEqual(s.code, "P3-001")
        XCTAssertEqual(s.contractor, "B")
        XCTAssertEqual(s.engineer, "เปรม")
        var t = p3001()
        t.readCodeLine(": P9-999, ผรม. Z, วิศวกร X")
        XCTAssertEqual(t.code, "P3-001")
        XCTAssertEqual(t.contractor, "B")
    }

    /// A file with a set-up line names its people there: `รหัส` still naming someone the line left out gives no one.
    func testTheSetUpLineNamesThePeople() {
        var s = ProjectSetup.parse(title: Self.title, line: "กปภ.สาขาชัยบาดาล, ภาคเหนือ-กลาง, Zero export HV")
        s.readCodeLine(": P3-001, ผรม. B, วิศวกร เปรม, ข้อมูล ณ 19/10/2026", people: false)
        XCTAssertEqual(s.code, "P3-001")
        XCTAssertNil(s.engineer)
        XCTAssertNil(s.contractor)
    }

    /// A job's people are its own: export takes out of the line those the job has no one for.
    func testPeopleTheJobHasNoOneForLeaveTheLine() {
        var s = ProjectSetup()
        s.engineer = "สมชาย"
        XCTAssertEqual(s.rewrite(line: Self.line, dropPeople: true),
                       "กปภ.สาขาชัยบาดาล, ภาคเหนือ-กลาง, กฟภ. เขต น.3, Inverter 160 kW (ไม่ต้อง พค.2), Zero export HV, "
                        + "คำขอ PPIM1A5072BC, วิศวกร สมชาย")
        XCTAssertEqual(s.rewrite(line: ": P3-001, ผรม. B, วิศวกร เปรม, ข้อมูล ณ 19/10/2026", dropPeople: true),
                       ": P3-001, วิศวกร สมชาย, ข้อมูล ณ 19/10/2026")
        XCTAssertEqual(s.rewrite(line: Self.line), Self.line.replacingOccurrences(of: "วิศวกร เปรม", with: "วิศวกร สมชาย"),
                       "without dropPeople the file keeps whom the job has no one for")
    }

    func testLinesAreWrittenBackInPlace() {
        // nothing changed: the same line
        XCTAssertEqual(p3001().rewrite(line: Self.line), Self.line)
        XCTAssertEqual(p3001().rewrite(title: Self.title), Self.title)
        var s = ProjectSetup()
        s.inverterKW = 250
        s.contractor = "S"
        s.stationName = "สถานีใหม่"
        XCTAssertEqual(s.rewrite(line: Self.line), Self.line
            .replacingOccurrences(of: "Inverter 160 kW (ไม่ต้อง พค.2)", with: "Inverter 250 kW (ต้องยื่น พค.2)")
            .replacingOccurrences(of: "ผรม. B", with: "ผรม. S"))
        XCTAssertEqual(s.rewrite(title: Self.title), "แผนโครงการ P3-001 – สถานีใหม่ 163.02 kWp")
        XCTAssertEqual(s.rewrite(title: "Master Plan"), "Master Plan")
        // the same kWp keeps the title as written
        var same = ProjectSetup()
        same.kWp = 182.4
        XCTAssertEqual(same.rewrite(title: "แผนโครงการ P3-004 – สถานีผลิตน้ำลพบุรี 182.40 kWp"), "แผนโครงการ P3-004 – สถานีผลิตน้ำลพบุรี 182.40 kWp")
    }

    func testANewJobTakesEveryFactTicked() {
        let s = p3001()
        let changes = s.changes(for: .init())
        XCTAssertEqual(changes.map(\.field), [.stationName, .kWp, .code, .branch, .area, .peaZone, .inverter, .zeroExport,
                                              .ppimRequest, .engineer, .admin, .contractor])
        XCTAssertTrue(changes.allSatisfy(\.fills))
        var t = ProjectSetup.Target()
        s.apply(ProjectSetup.defaultFields(changes), to: &t)
        XCTAssertEqual(t.stationName, "สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล")
        XCTAssertEqual(t.kWp, 163.02)
        XCTAssertEqual(t.customerName, "กปภ.สาขาชัยบาดาล")
        XCTAssertEqual(t.station.branch, "สาขาชัยบาดาล")
        XCTAssertEqual(t.inverterKW, 160)
        XCTAssertNil(t.station.over200kVA, "the size already says no พค.2")
        XCTAssertEqual(t.station.code, "P3-001")
        XCTAssertEqual(t.station.area, "ภาคเหนือ-กลาง")
        XCTAssertEqual(t.station.peaZone, "กฟภ. เขต น.3")
        XCTAssertEqual(t.station.zeroExport, "HV")
        XCTAssertEqual(t.station.ppimRequest, "PPIM1A5072BC")
        XCTAssertEqual(t.station.admin, "บีม")
        XCTAssertEqual(t.routine.siteEngineer, "เปรม")
        XCTAssertEqual(t.routine.subcontractor, "B")
        // once taken, the same file has nothing more to change
        XCTAssertEqual(s.changes(for: t), [])
    }

    func testWhatTheTeamTypedIsOfferedUnticked() {
        var s = p3001()
        s.owner = "การประปาส่วนภูมิภาค"
        s.points = [.init(type: "หลังคาลอนคู่", count: 3, modules: 140, kWp: 79.8), .init(type: "ถังน้ำใส", count: 1, modules: 146, kWp: 83.22)]
        var t = ProjectSetup.Target(stationName: "สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล", kWp: 160, customerName: "การประปาส่วนภูมิภาคสาขาชัยบาดาล")
        t.routine.subcontractor = "A"
        t.station.branch = "สาขาชัยบาดาล"
        let changes = s.changes(for: t)
        let by = Dictionary(uniqueKeysWithValues: changes.map { ($0.field, $0) })
        XCTAssertNil(by[.stationName], "same name")
        XCTAssertEqual(by[.kWp]?.current, "160 kWp")
        XCTAssertEqual(by[.kWp]?.fills, false)
        XCTAssertEqual(by[.contractor]?.current, "A")
        XCTAssertEqual(by[.contractor]?.fills, false)
        // the branch is written two ways in two places; the same branch is no change
        XCTAssertNil(by[.branch])
        // the report's employer still the app's default: replacing it loses nothing
        XCTAssertEqual(by[.owner]?.fills, true)
        XCTAssertEqual(by[.locations]?.proposed, "หลังคาลอนคู่ 1, หลังคาลอนคู่ 2, หลังคาลอนคู่ 3, ถังน้ำใส 1")
        let ticked = ProjectSetup.defaultFields(changes)
        XCTAssertFalse(ticked.contains(.kWp))
        XCTAssertFalse(ticked.contains(.contractor))
        XCTAssertTrue(ticked.contains(.locations))
        s.apply(ticked, to: &t)
        XCTAssertEqual(t.kWp, 160, "left as typed")
        XCTAssertEqual(t.routine.subcontractor, "A")
        XCTAssertEqual(t.routine.employer, "การประปาส่วนภูมิภาค")
        XCTAssertEqual(t.routine.locations.count, 4)
    }

    func testPK2FollowsTheSizeUnlessTheFileSaysOtherwise() {
        var s = ProjectSetup.parse(title: nil, line: "Inverter 250 kW (ต้องยื่น พค.2)")
        var t = ProjectSetup.Target()
        t.station.over200kVA = false
        s.apply([.inverter], to: &t)
        XCTAssertEqual(t.inverterKW, 250)
        XCTAssertNil(t.station.over200kVA, "the size says it")
        s = ProjectSetup.parse(title: nil, line: "Inverter 250 kW (ไม่ต้อง พค.2)")
        s.apply([.inverter], to: &t)
        XCTAssertEqual(t.station.over200kVA, false, "the file's word where it disagrees with the size")
    }

    func testTheNewStationFactsStayOutOfAnOldStationsJSON() throws {
        let old = #"{"buildingRoute":"unknown","requestType":"new","sellsPower":false,"srtProject":true,"docs":{},"dueDates":{},"branch":"","region":""}"#
        let station = StationDocs.Station.decode(old)
        XCTAssertNil(station.code)
        let again = try XCTUnwrap(station.json)
        XCTAssertFalse(again.contains("peaZone"))
        var s = station
        s.peaZone = "กฟภ. เขต น.3"
        XCTAssertEqual(StationDocs.Station.decode(s.json).peaZone, "กฟภ. เขต น.3")
    }

    func testBranchNames() {
        XCTAssertEqual(ProjectSetup.branchName("กปภ.สาขาชัยบาดาล"), "ชัยบาดาล")
        XCTAssertEqual(ProjectSetup.branchName("การประปาส่วนภูมิภาคสาขาชัยบาดาล"), "ชัยบาดาล")
        XCTAssertEqual(ProjectSetup.branchName("สาขาชัยบาดาล"), "ชัยบาดาล")
    }
}

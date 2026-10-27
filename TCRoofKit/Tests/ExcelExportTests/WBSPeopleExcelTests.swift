import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The plan file's people and the team's edits to it: `ผู้รับผิดชอบ` names the job's people (`MPTemplates.roles`,
/// `wbs-roles.json`), the set-up line is the file's word on who they are, a `Y` without a date stays without one, and a
/// progress-only re-import takes the rows' owner and evidence edited in Excel.
final class WBSPeopleExcelTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func station(_ code: String) throws -> MPTemplates.Case {
        try XCTUnwrap(MPTemplates.cases(in: ProjectPlanTemplateTests.folder).first { $0.id == code })
    }

    /// The job's facts as a file gives them, every field taken.
    func job(_ setup: ProjectSetup) -> ProjectSetup {
        var t = ProjectSetup.Target()
        setup.apply(Set(ProjectSetup.Field.allCases), to: &t)
        return ProjectSetup(t)
    }

    /// The file's `แผนโครงการ` cells changed as Excel would: `edits` by WBS code, column heading and new text (nil
    /// empties it), and `cells` by reference.
    func edit(_ data: Data, rows edits: [(code: String, column: KeyPath<MPWorkbook.WBSHeader, Int?>, text: String?)] = [],
              cells: [String: String?] = [:]) throws -> Data {
        let book = try MPWorkbook.Book(data)
        var sheet = try XCTUnwrap(book.detail)
        let h = try XCTUnwrap(MPWorkbook.wbsHeader(sheet))
        let rows = Dictionary(MPWorkbook.codeRows(sheet, h).map { ($0.code, $0.row) }) { a, _ in a }
        for e in edits {
            let ref = MPWorkbook.Sheet.ref(try XCTUnwrap(h[keyPath: e.column]), try XCTUnwrap(rows[e.code], e.code))
            sheet.cells.set(ref, e.text.map { .inline($0) } ?? .empty)
        }
        for (ref, text) in cells { sheet.cells.set(ref, text.map { .inline($0) } ?? .empty) }
        var zip = book.zip
        zip.set(try XCTUnwrap(book.detailPath), sheet.cells.xml)
        return try zip.write()
    }

    func owner(_ r: MPWorkbook.Imported, _ code: String) -> String? { r.wbs.first { $0.code == code }?.responsible }

    /// Every station file names, in each row with a role, that station's own person for it (its set-up line's) or the
    /// role: what lets export put the job's people in. And a station that took its own file, ticks and all, exports it
    /// back byte for byte: a `Y` the file left without a date gets none, and its people stay where they are.
    func testEveryStationFileAgreesWithTheRolesAndComesBackUnchanged() throws {
        XCTAssertEqual(MPTemplates.roles["1.1"], .engineer)
        XCTAssertEqual(MPTemplates.roles["3.2.5"], .admin)
        XCTAssertEqual(MPTemplates.roles["2.1"], .contractor)
        XCTAssertNil(MPTemplates.roles["1.7.3"], "the utility's row (กฟภ.) names no one of ours")
        XCTAssertNil(MPTemplates.responsible("กฟภ.", code: "1.7.3", people: ProjectSetup()))
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 27))!
        var named = 0
        for c in MPTemplates.cases(in: ProjectPlanTemplateTests.folder) {
            let original = try Data(contentsOf: c.url)
            let r = try MPWorkbook.read(original)
            for item in r.wbs {
                guard let role = MPTemplates.roles[item.code], let who = item.responsible else { continue }
                XCTAssertNil(MPTemplates.responsible(who, code: item.code, people: r.setup), "\(c.id) \(item.code) \(who) as \(role)")
                if who != role.word { named += 1 }
            }
            let ticks = MasterSchedule.mergingTicks([:], fileDone: r.wbsDone, dates: r.wbsDoneDates, base: r.wbsBase,
                                                    by: "pm@tcroof.test", today: today).ticks
            let out = try MPWorkbook.export(original, input: r.input, actual: r.actual, ticks: ticks, setup: job(r.setup))
            XCTAssertEqual(out.changedCells, 0, c.id)
            XCTAssertEqual(out.data, original, c.id)
        }
        XCTAssertGreaterThan(named, 3_000, "the station files name people")
    }

    /// The case behind the change: P3-001 marks 15 rows `Y` with no `เสร็จ` date; export used to write the import's
    /// day into each.
    func testAYWithoutADateStaysWithoutOne() throws {
        let original = try Data(contentsOf: station("P3-001").url)
        let r = try MPWorkbook.read(original)
        let undated = r.wbsDone.subtracting(r.wbsDoneDates.keys)
        XCTAssertGreaterThanOrEqual(undated.count, 15)
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 27))!
        var ticks = MasterSchedule.mergingTicks([:], fileDone: r.wbsDone, dates: r.wbsDoneDates, base: nil, by: "pm@tcroof.test", today: day).ticks
        // a row ticked in the app has its day
        ticks["2.2.1"] = .init(by: "pm@tcroof.test", at: day)
        let back = try MPWorkbook.read(MPWorkbook.export(original, input: r.input, actual: r.actual, ticks: ticks).data)
        XCTAssertEqual(back.wbsDone, r.wbsDone.union(["2.2.1"]))
        XCTAssertEqual(back.wbsDoneDates, r.wbsDoneDates.merging(["2.2.1": day]) { a, _ in a })
    }

    /// Another station's plan (moved to the kickoff) names the job's people, else the roles, in the app and in the file;
    /// the lines take out whom the job has no one for.
    func testAnotherStationsPeopleGiveWayToTheJobs() throws {
        var people = ProjectSetup()
        people.engineer = "สมชาย"
        people.contractor = "K"
        let kickoff = cal.date(from: DateComponents(year: 2027, month: 1, day: 4))
        let moved = try MPTemplates.plan(station("P3-028"), kickoff: kickoff, people: people)
        let source = try MPWorkbook.read(Data(contentsOf: station("P3-028").url))
        XCTAssertNotEqual(source.setup.engineer, "สมชาย")
        XCTAssertEqual(owner(moved.imported, "1.1"), "สมชาย")
        XCTAssertEqual(owner(moved.imported, "2.1"), "ผรม. K")
        XCTAssertEqual(owner(moved.imported, "0.2"), "Admin", "no admin: the role")
        // the Inverter station's steps carry their row's
        if let step = moved.imported.wbs.first(where: { $0.code.hasPrefix("2.5.1.") }) {
            XCTAssertEqual(step.responsible, owner(moved.imported, "2.5.1"))
        }
        // with no one at all: the roles
        let bare = try MPTemplates.plan(station("P3-028"), kickoff: kickoff)
        XCTAssertEqual(owner(bare.imported, "1.1"), "วศ.")
        XCTAssertEqual(owner(bare.imported, "2.1"), "ผรม.")

        var t = ProjectSetup.Target(stationName: "สถานีทดสอบ", kWp: 100, customerName: "กปภ.สาขาทดสอบ", inverterKW: 100)
        t.routine.siteEngineer = "สมชาย"
        t.routine.subcontractor = "K"
        let out = try MPWorkbook.export(moved.data, input: moved.imported.input, actual: moved.imported.actual, setup: ProjectSetup(t))
        let back = try MPWorkbook.read(out.data)
        for item in back.wbs where MPTemplates.roles[item.code] != nil && item.responsible != nil {
            XCTAssertEqual(item.responsible, owner(moved.imported, item.code), item.code)
        }
        XCTAssertEqual(back.setup.engineer, "สมชาย")
        XCTAssertEqual(back.setup.contractor, "K")
        XCTAssertNil(back.setup.admin, "P3-028's admin is not this station's")
        XCTAssertFalse(back.wbs.contains { $0.responsible == source.setup.admin }, "nor in any row")
    }

    /// The edit that started it: P3-001 with its people taken out of the set-up line and most rows changed to roles
    /// in Excel, a few names left behind and `รหัส` still naming them. The import reads no one, and export puts the
    /// roles in the rows left behind and takes the names out of `รหัส`.
    func testNamesLeftBehindInExcelBecomeTheRoles() throws {
        let original = try Data(contentsOf: station("P3-001").url)
        let line = "กปภ.สาขาชัยบาดาล, ภาคเหนือ-กลาง, กฟภ. เขต น.3, Inverter 160 kW (ไม่ต้อง พค.2), Zero export HV"
        let edited = try edit(original, rows: [("0.1", \.responsible, "วศ."), ("0.2", \.responsible, "Admin"),
                                              ("0.2", \.evidence, nil)],
                              cells: ["A2": line])
        let r = try MPWorkbook.read(edited)
        XCTAssertNil(r.setup.engineer, "the set-up line names no one; รหัส is not read for people")
        XCTAssertNil(r.setup.admin)
        XCTAssertNil(r.setup.contractor)
        XCTAssertEqual(r.setup.code, "P3-001")
        XCTAssertEqual(owner(r, "1.1"), "เปรม", "left behind in Excel")
        XCTAssertEqual(owner(r, "3.2.5"), "บีม")

        let out = try MPWorkbook.export(edited, input: r.input, actual: r.actual, setup: job(r.setup))
        let back = try MPWorkbook.read(out.data)
        XCTAssertEqual(owner(back, "1.1"), "วศ.")
        XCTAssertEqual(owner(back, "3.2.5"), "Admin")
        XCTAssertEqual(owner(back, "2.1"), "ผรม.")
        XCTAssertEqual(owner(back, "0.1"), "วศ.")
        let code = try XCTUnwrap(MPWorkbook.Book(out.data).layout.code)
        XCTAssertFalse(code.contains("เปรม") || code.contains("ผรม. B"), code)
        XCTAssertTrue(code.hasPrefix("P3-001"), code)
        XCTAssertFalse(back.wbs.contains { ["เปรม", "บีม", "ผรม. B"].contains($0.responsible ?? "") })
        // the other columns are as edited
        XCTAssertNil(back.wbs.first { $0.code == "0.2" }?.evidence)
        XCTAssertEqual(back.wbs.map(\.title), r.wbs.map(\.title))

        // re-imported for its progress only, the job takes the rows' edits made in Excel since its kept file
        let kept = try MPWorkbook.read(original).wbs
        let merged = MasterSchedule.mergingText(kept, file: back.wbs, base: kept)
        XCTAssertEqual(merged.items.first { $0.code == "1.1" }?.responsible, "วศ.")
        XCTAssertNil(merged.items.first { $0.code == "0.2" }?.evidence, "a blanked หลักฐาน comes in blank")
        XCTAssertEqual(merged.items.map(\.code), kept.map(\.code))
    }
}

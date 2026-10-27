import XCTest
@testable import TCRoofCore

/// WBS ticks (docs/specs/project-plan-wbs.md, step 2): booked into the plan's progress once each, taken back on untick,
/// and a contractor's taken in only where theirs to change.
final class WBSTicksTests: XCTestCase {
    let cal = MasterSchedule.calendar
    func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: d))! }

    /// 2.1 at 20 in the plan, its sub-tasks 8 and 12, a row of the other case and part 0's row at 0.
    var input: MasterSchedule.Input {
        var i = MasterSchedule.Input(installStart: day(5), installEnd: day(22), kickoff: day(1), engineeringStart: day(1),
                                     siteHandover: day(2), over200kVA: false)
        i.fixed = ["structure": .init(start: day(5), end: day(22), weight: 20)]
        return i
    }
    let items: [MasterSchedule.WorkItem] = [
        .init(code: "2.1", title: "ติดตั้งโครงสร้าง", weight: 20, level: 1),
        .init(code: "2.1.1", title: "    ยึดขาจับ", weight: 8),
        .init(code: "2.1.2", title: "    ติดตั้ง Rail", weight: 12),
        .init(code: "2.1.3", title: "    ทางเดินบนเสา (ไม่เกี่ยวกับสถานีนี้)", weight: 5),
        .init(code: "0.1.1", title: "    แผนบริหารโครงการ", weight: 0),
    ]
    func tick(_ d: Int, _ by: String = "team@tcroof.test") -> MasterSchedule.WBSTick { .init(by: by, at: day(d)) }

    func testATickBooksItsWeightInItsWeek() {
        var a = MasterSchedule.Actual()
        XCTAssertTrue(MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.1": tick(7)], input: input))
        XCTAssertEqual(a.points["structure"], [MasterSchedule.Actual.key(day(7)): 8])
        XCTAssertEqual(a.started["structure"], day(7))
        XCTAssertNil(a.finished["structure"], "8 of 20 isn't finished")

        // the second sub-task a week on: the task reaches its weight and finishes that day
        let ticks = ["2.1.1": tick(7), "2.1.2": tick(15)]
        MasterSchedule.bookWBS(&a, items: items, ticks: ticks, input: input)
        XCTAssertEqual(a.points["structure"]?.values.reduce(0, +), 20)
        XCTAssertEqual(a.points["structure"]?[MasterSchedule.Actual.key(day(15))], 12)
        XCTAssertEqual(a.finished["structure"], day(15))

        // again: nothing changes, so every team device can run it
        let once = a
        XCTAssertFalse(MasterSchedule.bookWBS(&a, items: items, ticks: ticks, input: input))
        XCTAssertEqual(a, once)
    }

    func testUntickTakesItsBookingBack() {
        var a = MasterSchedule.Actual()
        MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.1": tick(7), "2.1.2": tick(7)], input: input)
        MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.2": tick(7)], input: input)
        XCTAssertEqual(a.points["structure"], [MasterSchedule.Actual.key(day(7)): 12])
        XCTAssertEqual(Set(a.fromWBS.keys), ["2.1.2"])
        MasterSchedule.bookWBS(&a, items: items, ticks: [:], input: input)
        XCTAssertNil(a.points["structure"])
        XCTAssertTrue(a.fromWBS.isEmpty)
    }

    /// Progress booked by hand counts: a tick books only what's left of the task's weight.
    func testATickNeverPassesItsTasksWeight() {
        var a = MasterSchedule.Actual()
        a.points["structure"] = [MasterSchedule.Actual.key(day(6)): 15]
        MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.1": tick(7)], input: input)
        XCTAssertEqual(a.points["structure"]?.values.reduce(0, +), 20)
        XCTAssertEqual(a.fromWBS["2.1.1"]?.points, 5)
        // taking it back takes those 5 away, not 8
        MasterSchedule.bookWBS(&a, items: items, ticks: [:], input: input)
        XCTAssertEqual(a.points["structure"]?.values.reduce(0, +), 15)
    }

    /// 2.1.2 split into steps (as 2.5.1 is by the Inverter station table): the steps book, 2.1.2 itself doesn't.
    func testARowWithStepsBooksOnlyItsSteps() {
        let split = items + [.init(code: "2.1.2.1", title: "ฐานราก", weight: 4.8, level: 3),
                             .init(code: "2.1.2.2", title: "โครงเหล็ก", weight: 7.2, level: 3)]
        XCTAssertEqual(split.parentCodes, ["2.1", "2.1.2"])
        var a = MasterSchedule.Actual()
        MasterSchedule.bookWBS(&a, items: split, ticks: ["2.1.2": tick(7), "2.1.2.1": tick(8)], input: input)
        XCTAssertEqual(a.points["structure"]?.values.reduce(0, +) ?? 0, 4.8, accuracy: 1e-9)
        XCTAssertNil(a.fromWBS["2.1.2"])
    }

    /// A plan file's ticks (step 3): only what was ticked or unticked in the file since the export changes the job.
    func testTicksFromAFileTakeOnlyWhatChangedThere() {
        let local = ["2.1.1": tick(7), "2.1.3": tick(9, "sub@contractor.test")]
        // exported with 2.1.1 and 2.1.3; in Excel 2.1.2 was ticked (with a date) and 2.1.1 unticked; 2.1.3 left
        let r = MasterSchedule.mergingTicks(local, fileDone: ["2.1.2", "2.1.3"], dates: ["2.1.2": day(12)],
                                            base: ["2.1.1", "2.1.3"], by: "pm@tcroof.test", today: day(20))
        XCTAssertEqual(Set(r.ticks.keys), ["2.1.2", "2.1.3"])
        XCTAssertEqual(r.ticks["2.1.2"], .init(by: "pm@tcroof.test", at: day(12)))
        XCTAssertEqual(r.ticks["2.1.3"], local["2.1.3"], "a tick the file didn't change keeps who made it")
        XCTAssertEqual(r.changed, 2)

        // a tick made in the app after the export stays, though the file never had it
        let later = MasterSchedule.mergingTicks(local, fileDone: ["2.1.3"], dates: [:], base: ["2.1.3"], by: "pm@tcroof.test", today: day(20))
        XCTAssertEqual(later.ticks, local)
        XCTAssertEqual(later.changed, 0)

        // a file the app never wrote: its Y rows are added, dated today without a date, and nothing is taken away
        let first = MasterSchedule.mergingTicks([:], fileDone: ["2.1.1"], dates: [:], base: nil, by: "pm@tcroof.test", today: day(20))
        XCTAssertEqual(first.ticks["2.1.1"]?.at, day(20))
        // that day is only the import's: export writes no date for it
        XCTAssertEqual(first.ticks["2.1.1"]?.undated, true)
        XCTAssertNil(r.ticks["2.1.2"]?.undated, "a row with its date is dated")
    }

    /// A tick saved before `undated` existed reads as dated, and a dated tick writes as before.
    func testOlderTicksRead() throws {
        let old = try JSONDecoder().decode(MasterSchedule.WBSTick.self, from: Data(#"{"by":"a@tcroof.test","at":0}"#.utf8))
        XCTAssertNil(old.undated)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(tick(7)), as: UTF8.self).contains("undated"))
    }

    /// รับเฉพาะความก้าวหน้า takes the rows' owner and evidence changed in Excel since the kept file, a blanked cell too;
    /// what the file didn't change stays the job's.
    func testTheFilesTextsComeInWhereTheyChanged() {
        func row(_ code: String, _ who: String?, _ evidence: String?) -> MasterSchedule.WorkItem {
            var i = MasterSchedule.WorkItem(code: code, title: code, weight: 1)
            i.responsible = who; i.evidence = evidence
            return i
        }
        let base = [row("1.1", "เปรม", "บันทึกการประชุม"), row("1.2", "บีม", "TC-PML-001"), row("1.3", "วศ.", nil)]
        // the job changed 1.3's owner in the app after the export
        let local = [base[0], base[1], row("1.3", "สมชาย", nil)]
        // in Excel: 1.1's owner became a role and its evidence was emptied; 1.2 untouched; 1.3 as exported
        let file = [row("1.1", "วศ.", nil), base[1], base[2], row("9.9", "x", "y")]
        let r = MasterSchedule.mergingText(local, file: file, base: base)
        XCTAssertEqual(r.items, [row("1.1", "วศ.", nil), base[1], row("1.3", "สมชาย", nil)])
        XCTAssertEqual(r.changed, 2)
        // no kept file: whatever the file says otherwise
        let first = MasterSchedule.mergingText(local, file: file, base: nil)
        XCTAssertEqual(first.items[2].responsible, "วศ.")
        XCTAssertEqual(first.changed, 3)
    }

    func testRowsThatWeighNothingBookNothing() {
        var a = MasterSchedule.Actual()
        XCTAssertFalse(MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.3": tick(7), "0.1.1": tick(7), "2.1": tick(7)], input: input))
        XCTAssertTrue(a.fromWBS.isEmpty)
    }

    /// A row the plan no longer has (a new file) takes its booking away.
    func testARowThatLeftThePlanTakesItsBookingBack() {
        var a = MasterSchedule.Actual()
        MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.1": tick(7)], input: input)
        MasterSchedule.bookWBS(&a, items: items.filter { $0.code != "2.1.1" }, ticks: ["2.1.1": tick(7)], input: input)
        XCTAssertNil(a.points["structure"])
    }

    func testAPlanKeepsItsBookingsAndOlderPlansRead() throws {
        var a = MasterSchedule.Actual()
        MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.1": tick(7)], input: input)
        let back = try JSONDecoder().decode(MasterSchedule.Actual.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back, a)
        let old = try JSONDecoder().decode(MasterSchedule.Actual.self, from: Data(#"{"points":{},"started":{},"finished":{},"lateCauses":{}}"#.utf8))
        XCTAssertTrue(old.fromWBS.isEmpty)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("fromWBS"),
                       "a plan without ticks writes as before")
    }

    func testAContractorChangesOnlyContractorTicks() {
        let con = "con@vendor.test", team = "team@tcroof.test"
        let local = ["2.1.1": tick(7, team), "2.1.2": tick(8, con)]
        let contractors: Set = [con]
        // their own new tick comes in; one in the team's name doesn't
        var incoming = local
        incoming["2.2.1"] = tick(9, con)
        incoming["2.3.1"] = tick(9, team)
        var out = MasterSchedule.WBSTick.trusting(incoming, local: local, contractors: contractors)
        XCTAssertEqual(Set(out.keys), ["2.1.1", "2.1.2", "2.2.1"])
        // they take back their own tick, not the team's
        incoming = ["2.2.1": tick(9, con)]
        out = MasterSchedule.WBSTick.trusting(incoming, local: out, contractors: contractors)
        XCTAssertEqual(Set(out.keys), ["2.1.1", "2.2.1"])
        // nor rewrite the team's in their name
        out = MasterSchedule.WBSTick.trusting(["2.1.1": tick(10, con), "2.2.1": tick(9, con)], local: out, contractors: contractors)
        XCTAssertEqual(out["2.1.1"], tick(7, team))
    }

    func testWhoTicksAndWhoTakesBack() {
        let con = "con@vendor.test", eng = "eng@tcroof.test", other = "other@tcroof.test"
        let job = JobAccess(externals: [con], supervisor: eng)
        let contractor = Permissions(role: .external, email: con), team = Permissions(role: .internalTeam, email: other)
        let supervisor = Permissions(role: .internalTeam, email: eng), manager = Permissions(role: .manager, email: "m@tcroof.test")
        XCTAssertTrue(contractor.mayTickWBS(on: job))
        XCTAssertFalse(Permissions(role: .external, email: "else@vendor.test").mayTickWBS(on: job), "not their job")
        XCTAssertTrue(team.mayTickWBS(on: job))
        let byContractor = tick(7, con), byTeam = tick(7, other)
        XCTAssertTrue(contractor.mayTakeBack(byContractor, on: job))
        XCTAssertFalse(contractor.mayTakeBack(byTeam, on: job))
        XCTAssertTrue(team.mayTakeBack(byTeam, on: job))
        XCTAssertFalse(team.mayTakeBack(byContractor, on: job), "a team member takes back only their own")
        XCTAssertTrue(supervisor.mayTakeBack(byContractor, on: job))
        XCTAssertTrue(manager.mayTakeBack(byContractor, on: job))
    }

    func testARowMovesWithItsPlan() {
        var item = MasterSchedule.WorkItem(code: "2.1.1", title: "ยึดขาจับ")
        item.baselineStart = day(5); item.forecastEnd = day(9)
        let moved = item.shifted(days: 7)
        XCTAssertEqual(moved.baselineStart, day(12))
        XCTAssertEqual(moved.forecastEnd, day(16))
        XCTAssertNil(moved.baselineEnd)
    }
}

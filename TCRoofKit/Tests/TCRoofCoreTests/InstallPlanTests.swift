import XCTest
@testable import TCRoofCore

/// The `แผนก่อสร้าง` tab's plan (docs/ui/install-tracking-ipad-v2 §6), on the board's stages: day 0 is 24/9/2026,
/// today is day 6, days 10–11 wait on the utility.
final class InstallPlanTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func d(_ i: Int) -> Date { cal.date(byAdding: .day, value: i, to: cal.date(from: DateComponents(year: 2026, month: 9, day: 24))!)! }

    typealias Sub = InstallGantt.Sub

    /// Four of the board's seven stages: done, running (3 of 5 sub-tasks done), next, and the handover after the wait.
    func plan(teamSize: Int? = nil, crew: [Date: Int] = [:]) -> InstallPlan {
        let rows: [InstallGantt.Row] = [
            .init(id: "s3", code: "3", title: "ติดตั้งแผง", status: .done, start: d(3), end: d(4), actualStart: d(3), actualEnd: d(4), percent: 100,
                  subs: [Sub("โซน A", percent: 100, start: d(3), end: d(3)), Sub("โซน B", percent: 100, start: d(3), end: d(4))]),
            .init(id: "s4", code: "4", title: "ระบบ DC", status: .current, start: d(5), end: d(7), actualStart: d(5), actualEnd: d(6), percent: 60,
                  subs: [Sub("สตริง 1–6", percent: 100, start: d(5), end: d(5)), Sub("สตริง 7–12", percent: 100, start: d(6), end: d(6)),
                         Sub("ตู้ DC", percent: 100, start: d(6), end: d(6)), Sub("วัด Voc", percent: 0, start: d(7), end: d(7)),
                         Sub("ป้ายเตือน", percent: 0, start: d(7), end: d(7))]),
            .init(id: "s5", code: "5", title: "อินเวอร์เตอร์", status: .waiting, start: d(8), end: d(9), percent: 0,
                  subs: [Sub("ยึดอินเวอร์เตอร์", percent: 0, start: d(8), end: d(8)), Sub("สาย AC", percent: 0, start: d(8), end: d(9))]),
            .init(id: "s7", code: "7", title: "ขนานไฟ", status: .waiting, start: d(12), end: d(12), percent: 0,
                  // places from the daily reports have no days of their own
                  subs: [Sub("ไม่ระบุตำแหน่ง", percent: 0)])]
        var p = InstallPlan(gantt: InstallGantt(rows: rows, today: d(6)), nonWorking: [d(10), d(11)],
                            tracking: InstallTracking(actual: 50, planned: 52, start: d(0), due: d(12), today: d(6)), crew: crew, calendar: cal)
        p.teamSize = teamSize
        return p
    }

    /// The plan file's WBS in place of the places: a stage's sub-tasks moved with the stage, ticked ones done, the other
    /// case's left out; a stage the WBS doesn't cover keeps its places.
    func testWBSSubTasksReplaceThePlaces() {
        // the board's stage s4 is "dcSide" here (2.2): the file has its line 2 days before the plan
        let rows: [InstallGantt.Row] = [
            .init(id: "dcSide", code: "2.2", title: "ระบบ DC", status: .current, start: d(5), end: d(9), percent: 30,
                  subs: [Sub("สตริง 1–6", percent: 100, start: d(5), end: d(5))]),
            .init(id: "panels", code: "2.3", title: "แผง", status: .waiting, start: d(9), end: d(10), percent: 0,
                  subs: [Sub("โซน A", percent: 0)])]
        var p = InstallPlan(gantt: InstallGantt(rows: rows, today: d(6)), nonWorking: [], tracking: nil, calendar: cal)
        func item(_ code: String, _ title: String, _ s: Int, _ e: Int) -> MasterSchedule.WorkItem {
            var i = MasterSchedule.WorkItem(code: code, title: title, weight: 2)
            i.baselineStart = d(s); i.baselineEnd = d(e)
            return i
        }
        let wbs = [item("2.2", "ติดตั้งอุปกรณ์ไฟฟ้าด้าน DC", 3, 7), item("2.2.1", "    รางเดินสาย DC", 3, 4),
                   item("2.2.2", "    สาย PV", 5, 7), item("2.2.9", "    ทางเดิน HV (ไม่เกี่ยวกับสถานีนี้)", 3, 3)]
        p.useWBS(wbs, ticked: ["2.2.1"], calendar: cal)

        let dc = p.stages[0].subs
        XCTAssertEqual(dc.map(\.code), ["2.2.1", "2.2.2"])
        XCTAssertEqual(dc.map(\.title), ["รางเดินสาย DC", "สาย PV"])
        // moved 2 days with the stage
        XCTAssertEqual(dc[0].start, d(5)); XCTAssertEqual(dc[0].end, d(6))
        XCTAssertEqual(dc[1].start, d(7)); XCTAssertEqual(dc[1].end, d(9))
        XCTAssertEqual(dc[0].status, .done); XCTAssertEqual(dc[0].percent, 100)
        XCTAssertEqual(dc[0].baselineEnd, d(4)); XCTAssertEqual(dc[0].slip, 2, "the file's own dates are its baseline")
        XCTAssertEqual(dc[1].status, .waiting, "starts after today")
        // the panels stage has no WBS rows here: its place stays
        XCTAssertEqual(p.stages[1].subs.map(\.title), ["โซน A"])
    }

    /// The baseline under each stage: the plan file's WBS lines, or the plan before its first re-plan when there is one.
    func testStagesCarryTheirBaselineAndSlip() {
        func line(_ code: String, _ s: Int, _ e: Int) -> MasterSchedule.WorkItem {
            var i = MasterSchedule.WorkItem(code: code, title: code, weight: 5, level: 1)
            i.baselineStart = d(s); i.baselineEnd = d(e)
            return i
        }
        let wbs = [line("2.2", 5, 6), line("2.3", 9, 9), line("2.2.1", 5, 5)]
        var input = MasterSchedule.Input(installStart: d(0), installEnd: d(20), kickoff: d(-30), engineeringStart: d(-25),
                                         siteHandover: d(-1), over200kVA: false)
        let fromFile = InstallPlan.baselineDates(input: input, wbs: wbs, calendar: cal)
        XCTAssertEqual(fromFile["dcSide"], d(5)...d(6))
        XCTAssertEqual(fromFile["panels"], d(9)...d(9))
        XCTAssertEqual(fromFile.count, 2, "only the task lines, not the sub-tasks")

        input.baseline = ["dcSide": .init(start: d(4), end: d(5), weight: 5)]
        XCTAssertEqual(InstallPlan.baselineDates(input: input, wbs: wbs, calendar: cal), ["dcSide": d(4)...d(5)],
                       "a re-plan's baseline wins over the file's")

        let rows: [InstallGantt.Row] = [
            .init(id: "dcSide", code: "2.2", title: "ระบบ DC", status: .current, start: d(5), end: d(9), percent: 30, subs: []),
            .init(id: "panels", code: "2.3", title: "แผง", status: .waiting, start: d(9), end: d(10), percent: 0, subs: []),
            .init(id: "inverter", code: "2.5", title: "Inverter", status: .waiting, start: d(10), end: d(11), percent: 0, subs: [])]
        var p = InstallPlan(gantt: InstallGantt(rows: rows, today: d(6)), nonWorking: [], tracking: nil, calendar: cal)
        XCTAssertNil(p.slip)
        p.useBaseline(fromFile)
        XCTAssertEqual(p.stages.map(\.row.slip), [3, 1, nil])
        XCTAssertEqual(p.stages[0].row.baselineStart, d(5))
        XCTAssertEqual(p.slip, 1, "the last end of the stages with a baseline against their last baseline end")
        XCTAssertEqual(InstallPlan.slipText(3), "ช้า 3 วัน")
        XCTAssertEqual(InstallPlan.slipText(0), "ตรงแผน")
        XCTAssertEqual(InstallPlan.slipText(-2), "เร็ว 2 วัน")
    }

    func testStagesAreCriticalUntilDone() {
        let p = plan()
        XCTAssertEqual(p.stages.map(\.row.critical), [false, true, true, true], "a done stage is no longer outlined")
        XCTAssertEqual(p.stages.map(\.row.float), [0, 0, 0, 0], "the wait days are not float")
        XCTAssertEqual(p.stages[1].row.days, 3)
    }

    func testSubTaskStatusFloatAndCriticalRing() {
        let dc = plan().stages[1].subs
        XCTAssertEqual(dc.map(\.code), ["4.1", "4.2", "4.3", "4.4", "4.5"])
        XCTAssertEqual(dc.map(\.status), [.done, .done, .done, .waiting, .waiting], "a sub-task after today waits")
        XCTAssertEqual(dc.map(\.float), [2, 1, 1, 0, 0], "float runs from the sub-task's end to its stage's end")
        XCTAssertEqual(dc.map(\.critical), [false, false, false, true, true], "only open sub-tasks with no float are ringed")
        // a done stage's sub-tasks are done whatever their percent
        XCTAssertTrue(plan().stages[0].subs.allSatisfy { $0.status == .done && !$0.critical })
    }

    func testRunningStageSubTaskThatHasStartedIsCurrent() {
        let row = InstallGantt.Row(id: "s4", code: "4", title: "ระบบ DC", status: .current, start: d(5), end: d(7), percent: 20,
                                   subs: [Sub("วัด Voc", percent: 0, start: d(6), end: d(7)), Sub("ป้าย", percent: 0, start: d(7), end: d(7))])
        let p = InstallPlan(gantt: InstallGantt(rows: [row], today: d(6)), nonWorking: [], tracking: nil, calendar: cal)
        XCTAssertEqual(p.stages[0].subs.map(\.status), [.current, .waiting])
        XCTAssertNil(p.onPlan, "no tracking figure, no plan status")
    }

    func testPlaceWithoutDaysSpansItsStageWithNoFloat() {
        let sub = plan().stages[3].subs[0]
        XCTAssertEqual(sub.start, d(12))
        XCTAssertEqual(sub.end, d(12))
        XCTAssertNil(sub.float)
        XCTAssertFalse(sub.critical)
    }

    func testFiguresAndNextStage() {
        let p = plan()
        XCTAssertEqual(p.days.count, 10, "from the first start (day 3) to the last end (day 12)")
        // 27/9/2026 (day 3) is a Sunday, days 10 (also a Sunday) and 11 wait
        XCTAssertTrue(InstallPlan.isSunday(d(3)))
        XCTAssertEqual(p.workingDays, 7)
        XCTAssertEqual(p.subCount, 10)
        XCTAssertEqual(p.nextStage?.id, "s5", "the stage after the running one")
        XCTAssertEqual(p.onPlan, true, "-2 points is within the tolerance")
    }

    func testCrewOverTheTeam() {
        let p = plan(teamSize: 8, crew: [d(5): 7, d(6): 9, d(8): 4])
        XCTAssertEqual(p.crewDays.count, p.days.count)
        XCTAssertEqual(p.crewDays.first { $0.date == d(6) }?.count, 9)
        XCTAssertEqual(p.overTeam, [d(6)])
        XCTAssertTrue(plan(crew: [d(6): 20]).overTeam.isEmpty, "no team size, nothing to be over")
    }

    // MARK: CHA-64

    /// A stage still marked waiting by the MP plan whose sub-tasks have started reads as running, with their progress.
    func testStageRollsUpItsSubTasks() {
        let row = InstallGantt.Row(id: "s4", code: "2.2", title: "ระบบ DC", status: .waiting, start: d(5), end: d(8), percent: 0,
                                   subs: [Sub("ราง", percent: 100, start: d(5), end: d(6)), Sub("สาย", percent: 50, start: d(7), end: d(8))])
        let p = InstallPlan(gantt: InstallGantt(rows: [row], today: d(7)), nonWorking: [], tracking: nil, calendar: cal)
        XCTAssertEqual(p.stages[0].row.status, .current)
        XCTAssertEqual(p.stages[0].row.percent, 75, accuracy: 0.01, "2 days at 100 % and 2 at 50 %")

        // every place reported so far done doesn't finish the stage; every WBS row ticked does
        let all = InstallGantt.Row(id: "panels", code: "2.3", title: "แผง", status: .current, start: d(5), end: d(6), percent: 40,
                                   subs: [Sub("A", percent: 100, start: d(5), end: d(5)), Sub("B", percent: 100, start: d(6), end: d(6))])
        var q = InstallPlan(gantt: InstallGantt(rows: [all], today: d(7)), nonWorking: [], tracking: nil, calendar: cal)
        XCTAssertEqual(q.stages[0].row.status, .current)
        XCTAssertEqual(q.stages[0].row.percent, 100, "the places' progress")
        var line = MasterSchedule.WorkItem(code: "2.3.1", title: "ยึดแผง", weight: 1)
        line.baselineStart = d(5); line.baselineEnd = d(6)
        q.useWBS([line], ticked: ["2.3.1"], calendar: cal)
        XCTAssertEqual(q.stages[0].row.status, .done, "every WBS row ticked")
        XCTAssertFalse(q.stages[0].row.critical)
    }

    /// Work past its end and not done is on the critical path, its stage too, with no float tail.
    func testLateWorkIsCritical() {
        let rows: [InstallGantt.Row] = [
            .init(id: "s4", code: "2.2", title: "ระบบ DC", status: .current, start: d(0), end: d(4), percent: 50,
                  subs: [Sub("Bonding", percent: 0, start: d(0), end: d(2)), Sub("ICL", percent: 100, start: d(3), end: d(4))]),
            .init(id: "s9", code: "3", title: "ส่งมอบ", status: .waiting, start: d(20), end: d(30), percent: 0, subs: [])]
        let p = InstallPlan(gantt: InstallGantt(rows: rows, today: d(10)), nonWorking: [], tracking: nil, calendar: cal)
        let dc = p.stages[0]
        XCTAssertTrue(dc.subs[0].critical, "late and open")
        XCTAssertEqual(dc.subs[0].float, 0)
        XCTAssertFalse(dc.subs[1].critical, "done")
        XCTAssertTrue(dc.row.critical)
        XCTAssertEqual(dc.row.float, 0)
    }

    /// One status with its days: earned schedule's days behind, or the forecast's.
    func testOneScheduleStatusWithDays() {
        let rows: [InstallGantt.Row] = [.init(id: "s4", code: "2.2", title: "DC", status: .current, start: d(0), end: d(20), percent: 20, subs: [])]
        let g = InstallGantt(rows: rows, today: d(10))
        let behind = InstallPlan(gantt: g, nonWorking: [], tracking: InstallTracking(actual: 20, planned: 50, start: d(0), due: d(20),
                                                                                  today: d(10), earned: d(7)), calendar: cal)
        XCTAssertEqual(behind.schedule, .behind)
        XCTAssertEqual(behind.lateDays, 3)
        XCTAssertEqual(behind.scheduleText, "ช้ากว่าแผน 3 วัน")
        let on = InstallPlan(gantt: g, nonWorking: [], tracking: InstallTracking(actual: 48, planned: 50, start: d(0), due: d(20),
                                                                              today: d(10), earned: d(9)), calendar: cal)
        XCTAssertEqual(on.scheduleText, "ตามแผน")
        let ahead = InstallPlan(gantt: g, nonWorking: [], tracking: InstallTracking(actual: 70, planned: 50, start: d(0), due: d(20),
                                                                                 today: d(10), earned: d(14)), calendar: cal)
        XCTAssertEqual(ahead.scheduleText, "เร็วกว่าแผน 4 วัน")
        XCTAssertNil(InstallPlan(gantt: g, nonWorking: [], tracking: nil, calendar: cal).scheduleText)
    }

    /// A milestone is passed when its work is complete; a past day with the work open is overdue.
    func testMilestoneStateFollowsItsWork() {
        typealias M = InstallPlan.Milestone
        let today = d(10)
        XCTAssertEqual(M(title: "ส่งมอบ", date: d(9), done: false).state(today: today, calendar: cal), .overdue(1))
        XCTAssertEqual(M(title: "ส่งมอบ", date: d(9), done: true).state(today: today, calendar: cal), .done)
        XCTAssertEqual(M(title: "ส่งมอบ", date: d(12), done: true).state(today: today, calendar: cal), .done, "done early")
        XCTAssertEqual(M(title: "ส่งมอบ", date: d(10), done: false).state(today: today, calendar: cal), .today)
        XCTAssertEqual(M(title: "ส่งมอบ", date: d(13), done: false).state(today: today, calendar: cal), .ahead(3))
        XCTAssertEqual(M(title: "ส่งมอบ", date: d(9)).state(today: today, calendar: cal), .done, "no linked work: by the date")
    }

    /// The `วันทำงาน` column leaves out Sundays and the hatched days.
    func testRowWorkingDays() {
        let p = plan()
        // s5: days 8 and 9 (2–3/10), both working
        XCTAssertEqual(p.workingDays(of: p.stages[2].row), 2)
        var r = p.stages[2].row
        r.start = d(3); r.end = d(11)
        XCTAssertEqual(r.days, 9)
        XCTAssertEqual(p.workingDays(of: r), 6, "27/9 and 4/10 are Sundays, 5/10 waits")
    }
}

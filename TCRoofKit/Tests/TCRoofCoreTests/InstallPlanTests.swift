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
        XCTAssertEqual(dc[1].status, .waiting, "starts after today")
        // the panels stage has no WBS rows here: its place stays
        XCTAssertEqual(p.stages[1].subs.map(\.title), ["โซน A"])
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
}

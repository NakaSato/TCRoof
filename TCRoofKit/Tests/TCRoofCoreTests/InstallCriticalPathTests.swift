import XCTest
@testable import TCRoofCore

final class InstallCriticalPathTests: XCTestCase {
    let cal = MasterSchedule.calendar

    /// Day `i` of the board's plan: 0 is 24/9/2026.
    func d(_ i: Int) -> Date { cal.date(byAdding: .day, value: i, to: cal.date(from: DateComponents(year: 2026, month: 9, day: 24))!)! }
    func task(_ id: String, _ a: Int, _ b: Int) -> InstallCriticalPath.Task { .init(id: id, start: d(a), end: d(b)) }

    /// The board's seven stages run one after another; the Sunday (27/9) and the two days waiting on the utility
    /// (4–5/10) are not spare time, so every stage is critical.
    func testBoardStagesAreAllCritical() {
        let stages = [task("1", 0, 0), task("2", 1, 2), task("3", 3, 4), task("4", 5, 7), task("5", 8, 8), task("6", 9, 9), task("7", 12, 12)]
        let off: Set<Date> = [d(3), d(10), d(11)]
        XCTAssertEqual(InstallCriticalPath.critical(stages, nonWorking: off, calendar: cal), Set(stages.map(\.id)))
        // counted in calendar days the wait before stage 7 would be float
        XCTAssertEqual(InstallCriticalPath.float(stages, calendar: cal)["6"], 2)
        XCTAssertEqual(InstallCriticalPath.float(stages, calendar: cal)["7"], 0)
    }

    /// A short task beside a long one floats until the next task that follows both.
    func testParallelTaskFloats() {
        let tasks = [task("frame", 0, 5), task("cabinet", 0, 2), task("panels", 6, 8)]
        let f = InstallCriticalPath.float(tasks, calendar: cal)
        XCTAssertEqual(f["frame"], 0)
        XCTAssertEqual(f["panels"], 0)
        XCTAssertEqual(f["cabinet"], 3)
        XCTAssertEqual(InstallCriticalPath.critical(tasks, calendar: cal), ["frame", "panels"])
    }

    /// Tasks that hand over on the same day (the MP plan's pre-commissioning ends the day training starts) are linked.
    func testSameDayHandoverLinks() {
        let tasks = [task("pre", 0, 2), task("training", 2, 4), task("monitoring", 0, 1)]
        let f = InstallCriticalPath.float(tasks, calendar: cal)
        XCTAssertEqual(f["pre"], 0)
        XCTAssertEqual(f["training"], 0)
        XCTAssertEqual(f["monitoring"], 0, "training starts the day after it ends")
    }

    func testMPPlanEndsOnACriticalTask() {
        let input = MasterSchedule.Input(installStart: d(0), installEnd: d(59), kickoff: d(-30), engineeringStart: d(-30),
                                         siteHandover: d(-5), over200kVA: false)
        let tasks = MasterSchedule.plan(input, calendar: cal).compactMap { p -> InstallCriticalPath.Task? in
            guard p.task.part != .permit, let s = p.start, let e = p.end else { return nil }
            return .init(id: p.task.rawValue, start: s, end: e)
        }
        let critical = InstallCriticalPath.critical(tasks, calendar: cal)
        XCTAssertTrue(critical.contains("training"))
        XCTAssertTrue(critical.contains("preCommissioning"))
        XCTAssertFalse(critical.isEmpty)
        XCTAssertLessThan(critical.count, tasks.count, "the overlapping construction tasks are not all critical")
    }

    func testSubTaskFloatSkipsDaysOff() {
        XCTAssertEqual(InstallCriticalPath.float(subEnd: d(5), stageEnd: d(7), calendar: cal), 2)
        XCTAssertEqual(InstallCriticalPath.float(subEnd: d(7), stageEnd: d(7), calendar: cal), 0)
        XCTAssertEqual(InstallCriticalPath.float(subEnd: d(9), stageEnd: d(12), nonWorking: [d(10), d(11)], calendar: cal), 1)
    }

    func testEmptyPlan() {
        XCTAssertTrue(InstallCriticalPath.float([], calendar: cal).isEmpty)
    }

    // MARK: from the plan's links (CHA-77)

    func row(_ code: String, _ a: Int, _ b: Int, after links: [MasterSchedule.WBSDependency] = []) -> MasterSchedule.WorkItem {
        var item = MasterSchedule.WorkItem(code: code, title: code)
        item.baselineStart = d(a); item.baselineEnd = d(b); item.days = b - a + 1
        item.dependencies = links.isEmpty ? nil : links
        return item
    }

    /// Panels start two days after the structure starts (SS+2). Read from the dates, the structure has a day of float
    /// and the inverter none, since panels start the day after it ends; by the links it is the other way round.
    func testLinksDecideWhereTheDatesDisagree() throws {
        let wbs = [row("2.1", 0, 5), row("2.3", 2, 6, after: [.init(predecessor: "2.1", lagDays: 2, type: .startToStart)]), row("2.5", 0, 1)]
        let dated = InstallCriticalPath.float([task("structure", 0, 5), task("panels", 2, 6), task("inverter", 0, 1)], calendar: cal)
        XCTAssertEqual(dated["structure"], 1)
        XCTAssertEqual(dated["inverter"], 0)
        let starts = ["structure": d(0), "panels": d(2), "inverter": d(0)]
        let linked = try XCTUnwrap(InstallCriticalPath.float(wbs: wbs, starts: starts, calendar: cal))
        XCTAssertEqual(linked["structure"], 0, "panels can't start until two days after it starts")
        XCTAssertEqual(linked["panels"], 0)
        XCTAssertEqual(linked["inverter"], 5, "nothing waits on it")
    }

    func testAPlanWithoutLinksKeepsTheDates() {
        XCTAssertNil(InstallCriticalPath.float(wbs: [row("2.1", 0, 5), row("2.3", 2, 6)], starts: [:], calendar: cal))
        let broken = [row("2.3", 2, 6, after: [.init(predecessor: "2.9")])]
        XCTAssertNil(InstallCriticalPath.float(wbs: broken, starts: [:], calendar: cal), "links that don't hold together")
    }

    /// The rows move with their task's start in the plan before the passes.
    func testRowsMoveWithTheirTask() throws {
        let wbs = [row("2.1", 0, 5), row("2.3", 2, 6, after: [.init(predecessor: "2.1", lagDays: 2, type: .startToStart)])]
        let linked = try XCTUnwrap(InstallCriticalPath.float(wbs: wbs, starts: ["panels": d(8)], calendar: cal))
        XCTAssertEqual(linked["structure"], 6, "panels start on day 8 now, so the structure can slip six days")
        XCTAssertEqual(linked["panels"], 0)
    }

    func testTheConstructionPlanTakesTheLinksFloat() {
        let g = InstallGantt(rows: [
            .init(id: "structure", code: "2.1", title: "structure", status: .waiting, start: d(0), end: d(5), percent: 0),
            .init(id: "panels", code: "2.3", title: "panels", status: .waiting, start: d(2), end: d(6), percent: 0),
            .init(id: "inverter", code: "2.5", title: "inverter", status: .waiting, start: d(0), end: d(1), percent: 0)
        ], today: d(0))
        var plan = InstallPlan(gantt: g, nonWorking: [], tracking: nil, calendar: cal)
        XCTAssertEqual(plan.stages.first { $0.id == "inverter" }?.row.critical, true, "read from the dates")
        plan.useWBS([row("2.1", 0, 5), row("2.3", 2, 6, after: [.init(predecessor: "2.1", lagDays: 2, type: .startToStart)]), row("2.5", 0, 1)],
                    ticked: [], calendar: cal)
        XCTAssertEqual(plan.stages.first { $0.id == "structure" }?.row.float, 0)
        XCTAssertEqual(plan.stages.first { $0.id == "structure" }?.row.critical, true)
        XCTAssertEqual(plan.stages.first { $0.id == "inverter" }?.row.float, 5)
        XCTAssertEqual(plan.stages.first { $0.id == "inverter" }?.row.critical, false)
        XCTAssertEqual(plan.stages.first { $0.id == "panels" }?.row.after, "2.1 SS+2")
    }
}

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
}

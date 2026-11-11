import XCTest
@testable import TCRoofCore

/// CHA-87: the schedule reserve after the install end, and how fast it is used against the work done.
final class ScheduleBufferTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }

    /// The same plan as HandoverRangeTests: install 1 ก.พ.–18 เม.ย. 2026 (77 days), ≥ 200 kVA.
    func input() -> MasterSchedule.Input {
        MasterSchedule.Input(installStart: d(2026, 2, 1), installEnd: d(2026, 4, 18), kickoff: d(2026, 1, 10),
                             engineeringStart: d(2026, 1, 12), siteHandover: d(2026, 1, 20), over200kVA: true)
    }

    /// Every task booked as planned, week by week, through `day`'s week.
    func onPlan(through day: Date) -> MasterSchedule.Actual {
        let i = input(), plan = MasterSchedule.plan(i, calendar: cal)
        var a = MasterSchedule.Actual()
        for (task, weeks) in MasterSchedule.plannedPoints(plan, calendar: cal) {
            for (week, pts) in weeks where week <= day && pts > 0 { a.set(pts, task: task, week: week, weight: i.weight(task), calendar: cal) }
        }
        return a
    }

    func testZonesAtTheirBoundaries() {
        XCTAssertEqual(ScheduleBuffer.zone(used: 0, done: 0), .green)
        XCTAssertEqual(ScheduleBuffer.zone(used: 40, done: 40), .green, "used as fast as the work: still green")
        XCTAssertEqual(ScheduleBuffer.zone(used: 40.5, done: 40), .amber)
        XCTAssertEqual(ScheduleBuffer.zone(used: 73, done: 40), .amber, "exactly a third ahead")
        XCTAssertEqual(ScheduleBuffer.zone(used: 73.5, done: 40), .red)
        XCTAssertEqual(ScheduleBuffer.zone(used: 99, done: 95), .amber)
        XCTAssertEqual(ScheduleBuffer.zone(used: 100, done: 100), .red, "all used is red, however far the work is")
    }

    func testSizeIsTheAuthoritySpreadPlusTenPercent() {
        let plan = MasterSchedule.plan(input(), calendar: cal)
        let size = ScheduleBuffer.size(plan: plan, input: input(), calendar: cal)
        XCTAssertEqual(size.management, 8, "10 % of 77 days")
        XCTAssertGreaterThan(size.contingency, 0, "PPIM, อ.1, พค.2 and กฟภ. are open at baseline")
        XCTAssertEqual(size.total, size.contingency + size.management)
        XCTAssertEqual(ScheduleBuffer.Size(contingency: 0, management: 0).total, 1)
    }

    func testOnPlanUsesNothingAndTheProtectedDateIsAfterTheEnd() throws {
        // three weeks in, every task booked as planned: the forecast is the end itself
        let s = try XCTUnwrap(ScheduleBuffer.status(input: input(), actual: onPlan(through: d(2026, 2, 22)), today: d(2026, 2, 22), calendar: cal))
        XCTAssertEqual(s.usedDays, 0)
        XCTAssertEqual(s.remainingDays, s.size.total)
        XCTAssertEqual(s.protectedDate, cal.date(byAdding: .day, value: s.size.total, to: d(2026, 4, 18)))
        XCTAssertEqual(s.zone, .green)
        XCTAssertNil(ScheduleBuffer.status(input: input(), actual: .init(), today: d(2026, 1, 20), calendar: cal),
                     "before the install starts")
    }

    func testNothingBookedFallsBehindAndUsesTheBuffer() throws {
        // a month in with nothing booked: the forecast runs past the end
        let s = try XCTUnwrap(ScheduleBuffer.status(input: input(), actual: .init(), today: d(2026, 3, 4), calendar: cal))
        XCTAssertGreaterThan(s.usedDays, 0)
        XCTAssertEqual(s.now.done, 0)
        XCTAssertGreaterThan(s.now.used, 0)
        XCTAssertNotEqual(s.zone, .green, "buffer used with no work done")
        XCTAssertEqual(s.history.last, s.now)
        XCTAssertEqual(s.history.count, 5, "weeks ending 7, 14, 21, 28 ก.พ., then today")
        XCTAssertTrue(zip(s.history, s.history.dropFirst()).allSatisfy { $0.date < $1.date })
    }
}

import XCTest
@testable import TCRoofCore

/// CHA-80: the handover's likely (P50) and late (P90) days from three-point durations of the authority tasks.
final class HandoverRangeTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }

    /// 1.2 12–19 ม.ค., 1.4 20 ม.ค.–10 ก.พ., 1.5 28 มี.ค.–18 เม.ย., 1.7 11–18 เม.ย.; install 1 ก.พ.–18 เม.ย.
    func input() -> MasterSchedule.Input {
        MasterSchedule.Input(installStart: d(2026, 2, 1), installEnd: d(2026, 4, 18), kickoff: d(2026, 1, 10),
                             engineeringStart: d(2026, 1, 12), siteHandover: d(2026, 1, 20), over200kVA: true)
    }

    func range(_ actual: MasterSchedule.Actual = .init(), today: Date, base: Date? = nil,
               estimates: [MasterSchedule.Task: HandoverRange.Estimate] = HandoverRange.defaults) -> HandoverRange.Result? {
        HandoverRange.forecast(plan: MasterSchedule.plan(input()), actual: actual, base: base ?? d(2026, 4, 18), installEnd: d(2026, 4, 18),
                               today: today, estimates: estimates, calendar: cal)
    }

    func testOneDurationCollapsesToThePointForecast() throws {
        let one = HandoverRange.Estimate(1, 1, 1)
        let r = try XCTUnwrap(range(today: d(2026, 1, 5), base: d(2026, 4, 25),
                                    estimates: [.engineering: one, .buildingPermit: one, .pk2: one, .gridConnection: one]))
        XCTAssertEqual(r.likely, d(2026, 4, 25))
        XCTAssertEqual(r.late, d(2026, 4, 25))
    }

    func testDefaultsGiveALateCaseAfterTheLikelyDay() throws {
        let r = try XCTUnwrap(range(today: d(2026, 1, 5)))
        XCTAssertEqual(r.tasks, [.engineering, .buildingPermit, .pk2, .gridConnection])
        XCTAssertGreaterThanOrEqual(r.likely, d(2026, 4, 18))
        XCTAssertGreaterThan(r.late, r.likely, "พค.2 at up to 2.5 × 21 days should push the late case")
        // the same plan gives the same range
        XCTAssertEqual(range(today: d(2026, 1, 5)), r)
    }

    func testAnEarlyTaskWithSpareDaysDoesNotMoveIt() throws {
        // 1.2 at twice its 7 days still ends months before the install end
        let r = try XCTUnwrap(range(today: d(2026, 1, 5), estimates: [.engineering: .init(0.8, 1, 2)]))
        XCTAssertEqual(r.likely, d(2026, 4, 18))
        XCTAssertEqual(r.late, d(2026, 4, 18))
    }

    func testFinishedTasksLeaveNoRange() {
        var a = MasterSchedule.Actual()
        for t in [MasterSchedule.Task.engineering, .buildingPermit, .pk2, .gridConnection] {
            a.setDates(t, started: d(2026, 1, 12), finished: d(2026, 1, 20))
        }
        XCTAssertNil(range(a, today: d(2026, 1, 25)))
    }

    func testAnOverdueInspectionEndsTodayAtTheSoonest() throws {
        // 1.7 should have ended 18 เม.ย.; on 25 เม.ย. it is still open
        let one = HandoverRange.Estimate(1, 1, 1)
        let r = try XCTUnwrap(range(today: d(2026, 4, 25), estimates: [.gridConnection: one]))
        XCTAssertEqual(r.likely, d(2026, 4, 25))
        XCTAssertEqual(r.late, d(2026, 4, 25))
    }

    func testTheBriefCarriesTheRange() throws {
        let b = ScheduleBrief(jobID: "j", station: "S", input: input(), actual: .init(), today: d(2026, 1, 5), calendar: cal)
        // the range moves out from the brief's own point forecast
        let r = try XCTUnwrap(range(today: d(2026, 1, 5), base: d(2026, 4, 20)))
        XCTAssertEqual(b.handoverForecast, "2026-04-20")
        XCTAssertEqual(b.handoverLikely, ScheduleBrief.day(r.likely, calendar: cal))
        XCTAssertEqual(b.handoverLate, ScheduleBrief.day(r.late, calendar: cal))
        XCTAssertEqual(b.handoverRangeTasks, ["1.2", "1.4", "1.5", "1.7"])
    }

    func testTriangularStaysInsideItsEnds() {
        let e = HandoverRange.Estimate(0.8, 1, 2.5)
        XCTAssertEqual(HandoverRange.triangular(e, 0), 0.8, accuracy: 1e-9)
        XCTAssertEqual(HandoverRange.triangular(e, 0.999999), 2.5, accuracy: 0.01)
        XCTAssertEqual(HandoverRange.triangular(e, (1 - 0.8) / (2.5 - 0.8)), 1, accuracy: 1e-9)
    }
}

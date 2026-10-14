import XCTest
@testable import TCRoofCore

final class InstallTrackingTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()

    func day(_ d: Int, month: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: month, day: d))! }

    /// 24/9 – 6/10 is 13 days, as on the board.
    func tracking(actual: Double, planned: Double, weekAgo: Double? = nil) -> InstallTracking {
        InstallTracking(actual: actual, planned: planned, actualWeekAgo: weekAgo, start: day(24), due: day(6, month: 10), today: day(30))
    }

    func testScheduleKeepsFivePointsEitherSideOnPlan() {
        XCTAssertEqual(tracking(actual: 50, planned: 52).schedule, .onPlan)
        XCTAssertEqual(tracking(actual: 46, planned: 52).schedule, .behind)
        XCTAssertEqual(tracking(actual: 58, planned: 52).schedule, .ahead)
        XCTAssertEqual(tracking(actual: 50, planned: 52).variance, -2)
    }

    func testGainAndSPI() {
        let t = tracking(actual: 50, planned: 52, weekAgo: 36)
        XCTAssertEqual(t.gainThisWeek, 14)
        XCTAssertEqual(t.spi!, 50.0 / 52, accuracy: 1e-9)
        XCTAssertNil(tracking(actual: 0, planned: 0).spi)
        XCTAssertNil(tracking(actual: 10, planned: 20).gainThisWeek)
    }

    func testForecastStretchesThePeriodBySPI() {
        // 13 days at SPI 0.5 take 26: 24/9 + 25 days
        let late = tracking(actual: 25, planned: 50)
        XCTAssertEqual(late.forecastEnd(calendar: cal), day(19, month: 10))
        XCTAssertEqual(late.slackDays(calendar: cal), -13)
        // ahead of plan finishes early
        XCTAssertLessThan(tracking(actual: 60, planned: 50).forecastEnd(calendar: cal), day(6, month: 10))
        // nothing planned yet, or done: the due date
        XCTAssertEqual(tracking(actual: 0, planned: 0).forecastEnd(calendar: cal), day(6, month: 10))
        XCTAssertEqual(tracking(actual: 100, planned: 80).slackDays(calendar: cal), 0)
    }
}

final class InstallGanttTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func day(_ d: Int, month: Int = 10) -> Date { cal.date(from: DateComponents(year: 2026, month: month, day: d))! }

    func plan() -> (MasterSchedule.Input, [MasterSchedule.PlannedTask]) {
        let input = MasterSchedule.Input(installStart: day(1), installEnd: day(31), kickoff: day(1, month: 8), engineeringStart: day(5, month: 8),
                                         siteHandover: day(20, month: 9), over200kVA: false)
        return (input, MasterSchedule.plan(input, calendar: cal))
    }

    func testRowsAreTheInstallTasksWithTheirStatus() {
        let (_, p) = plan()
        var a = MasterSchedule.Actual()
        a.setPercent(100, task: .structure, week: day(4), over200kVA: false, calendar: cal)
        a.setPercent(40, task: .panels, week: day(11), over200kVA: false, calendar: cal)
        let g = InstallGantt(plan: p, actual: a, places: [:], today: day(14), calendar: cal)
        XCTAssertFalse(g.rows.contains { $0.code.hasPrefix("1.") }, "permit tasks stay out")
        XCTAssertEqual(g.rows.first { $0.id == "structure" }?.status, .done)
        let panels = g.rows.first { $0.id == "panels" }!
        XCTAssertEqual(panels.status, .current)
        XCTAssertEqual(panels.percent, 40, accuracy: 1e-9)
        XCTAssertNotNil(panels.forecastEnd)
        XCTAssertEqual(g.rows.first { $0.id == "training" }?.status, .waiting)
    }

    func testOverrunIsDaysPastThePlannedEnd() {
        let (_, p) = plan()
        let dc = p.first { $0.task == .dcSide }!
        let late = cal.date(byAdding: .day, value: 3, to: dc.end!)!
        let g = InstallGantt(plan: p, actual: MasterSchedule.Actual(), places: [:], today: late, calendar: cal)
        // past its end with nothing booked: late by the days since
        XCTAssertEqual(g.rows.first { $0.id == "dcSide" }?.overrunDays, 3)
    }

    func testPlacesKeepTheLatestPercentInFirstSeenOrder() {
        var r1 = RoutineReport.Daily(date: day(5)), r2 = RoutineReport.Daily(date: day(6))
        r1.progress = [.init(task: .structure, description: "", location: "หลังคา 2", percent: 30),
                       .init(task: .structure, description: "", location: "หลังคา 1", percent: 50)]
        r2.progress = [.init(task: .structure, description: "", location: "หลังคา 2", percent: 80)]
        let places = RoutineReport.places(reports: [r1, r2], through: day(6), settings: .init())
        XCTAssertEqual(places[.structure]?.map(\.title), ["หลังคา 2", "หลังคา 1"])
        XCTAssertEqual(places[.structure]?.map(\.percent), [80, 50])
        XCTAssertEqual(RoutineReport.places(reports: [r1, r2], through: day(5), settings: .init())[.structure]?.first?.percent, 30)
    }
}

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

    func testLateCauseIsKeptAndOldPlansStillDecode() throws {
        let old = #"{"points":{"structure":{"2026-10-04":5}},"started":{},"finished":{}}"#
        let a = try JSONDecoder().decode(MasterSchedule.Actual.self, from: Data(old.utf8))
        XCTAssertEqual(a.points["structure"]?["2026-10-04"], 5)
        XCTAssertTrue(a.lateCauses.isEmpty)

        var b = a
        b.lateCauses["dcSide"] = .material
        let back = try JSONDecoder().decode(MasterSchedule.Actual.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(back, b)
        let (_, p) = plan()
        XCTAssertEqual(InstallGantt(plan: p, actual: back, places: [:], today: day(14), calendar: cal).rows.first { $0.id == "dcSide" }?.lateCause, .material)

        // a cause from a newer build is dropped, the rest of the plan kept
        let newer = #"{"points":{},"lateCauses":{"dcSide":"crane","panels":"weather"}}"#
        XCTAssertEqual(try JSONDecoder().decode(MasterSchedule.Actual.self, from: Data(newer.utf8)).lateCauses, ["panels": .weather])
    }

    func testEarnedScheduleMovesTheDueDateByTheDaysBehind() {
        // the plan reached today's actual 6 days ago: the end moves 6 days, not by the whole period over the SPI
        let t = InstallTracking(actual: 6, planned: 93, start: day(24, month: 9), due: day(6), today: day(30, month: 9), earned: day(24, month: 9))
        XCTAssertEqual(t.forecastEnd(calendar: cal), day(12))
        XCTAssertEqual(t.slackDays(calendar: cal), -6)
        // ahead: the plan reaches today's actual in 2 days, so 2 days early
        let ahead = InstallTracking(actual: 60, planned: 50, start: day(24, month: 9), due: day(6), today: day(30, month: 9), earned: day(2))
        XCTAssertEqual(ahead.slackDays(calendar: cal), 2)
    }

    func testEarnedDateInterpolatesThePlansWeeks() throws {
        // one task of 100 points over four weeks from Sunday 4 ต.ค. 2569: 25 a week, each reached at its week's end
        var i = MasterSchedule.Input(installStart: day(4, month: 10), installEnd: day(31, month: 10), kickoff: day(4, month: 10),
                                     engineeringStart: day(4, month: 10), siteHandover: day(4, month: 10), over200kVA: false)
        i.fixed = ["structure": .init(start: day(4, month: 10), end: day(31, month: 10), weight: 100)]
        let plan = MasterSchedule.plan(i, calendar: cal).filter { $0.task == .structure }
        let total = MasterSchedule.status(plan: plan, actual: MasterSchedule.Actual(), through: day(31, month: 10), calendar: cal).planned
        XCTAssertEqual(total, 100, accuracy: 0.5)
        // 50 % is reached at the end of the second week, Saturday 17 ต.ค.
        let e = try XCTUnwrap(InstallTracking.earnedDate(plan: plan, actual: MasterSchedule.Actual(), done: 50, start: day(4, month: 10), calendar: cal))
        XCTAssertEqual(e, day(17, month: 10))
        // 37.5 % half way through the second week
        let m = try XCTUnwrap(InstallTracking.earnedDate(plan: plan, actual: MasterSchedule.Actual(), done: 37.5, start: day(4, month: 10), calendar: cal))
        XCTAssertTrue((day(13, month: 10)...day(14, month: 10)).contains(m))
        XCTAssertNil(InstallTracking.earnedDate(plan: plan, actual: MasterSchedule.Actual(), done: 101, start: day(4, month: 10), calendar: cal))
    }
}

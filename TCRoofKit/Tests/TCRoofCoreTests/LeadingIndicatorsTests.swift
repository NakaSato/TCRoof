import XCTest
@testable import TCRoofCore

/// CHA-85: leading indicators with thresholds, from data the app already keeps.
final class LeadingIndicatorsTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: h))! }

    /// Wednesday 4 มี.ค. 2026: its week starts Sunday 1 มี.ค.
    var today: Date { d(2026, 3, 4) }

    func input(waits: [ERCFlow.Wait] = [], failed: [LeadingIndicators.FailedItem] = [], dailies: [RoutineReport.Daily] = [],
               need: Int? = nil, requests: [RoutineReport.WeeklyRequest] = [], end: Date? = nil) -> LeadingIndicators.Input {
        .init(waits: waits, failedICL: failed, dailies: dailies, crewNeed: need, requests: requests,
              installStart: d(2026, 2, 1), installEnd: end ?? d(2026, 4, 30))
    }

    func indicator(_ kind: LeadingIndicator.Kind, _ input: LeadingIndicators.Input, today: Date? = nil) -> LeadingIndicator? {
        LeadingIndicators.compute(input, today: today ?? self.today, calendar: cal).first { $0.kind == kind }
    }

    func daily(_ date: Date, crew: Int, problems: [RoutineReport.Problem] = []) -> RoutineReport.Daily {
        var r = RoutineReport.Daily(date: date)
        r.crew = [.init(name: "ช่าง", count: crew)]
        r.problems = problems
        return r
    }

    func testAuthorityWaitTripsOnceItsLimitHasPassed() throws {
        let soon = ERCFlow.Wait(step: .inspectionResult, since: "2026-02-01", due: "2026-03-06", left: 2)
        XCTAssertFalse(try XCTUnwrap(indicator(.authorityOverdue, input(waits: [soon]))).tripped)
        let over = ERCFlow.Wait(step: .designResult, since: "2026-01-01", due: "2026-03-01", left: -3)
        let i = try XCTUnwrap(indicator(.authorityOverdue, input(waits: [soon, over])))
        XCTAssertEqual(i.value, 3)
        XCTAssertTrue(i.tripped)
        XCTAssertTrue(i.detail.contains("เกินกำหนด 3"), i.detail)
        XCTAssertNil(indicator(.authorityOverdue, input()), "no wait, nothing to measure")
    }

    func testFailedICLCountsOnceAWeekHasGoneWithoutAPass() throws {
        let fresh = LeadingIndicators.FailedItem(name: "ICL-2.1-03 แรงบิด", checkedAt: d(2026, 3, 2))
        let old = LeadingIndicators.FailedItem(name: "ICL-4-01 ค่าฉนวน", checkedAt: d(2026, 2, 20))
        let undated = LeadingIndicators.FailedItem(name: "ICL-5-02 ป้าย", checkedAt: nil)
        XCTAssertEqual(indicator(.iclFailed, input(failed: [fresh]))?.value, 0)
        let i = try XCTUnwrap(indicator(.iclFailed, input(failed: [fresh, old, undated])))
        XCTAssertEqual(i.value, 2)
        XCTAssertTrue(i.tripped)
        XCTAssertTrue(i.detail.hasPrefix("ICL-4-01"), i.detail)
    }

    func testCrewUnderNeedTripsAtTwoWeeksRunning() throws {
        // last week (22–28 ก.พ.) 4 a day, the week before 5, before that 8; the plan needs 6
        let dailies = [daily(d(2026, 2, 23), crew: 4), daily(d(2026, 2, 24), crew: 4),
                       daily(d(2026, 2, 16), crew: 5), daily(d(2026, 2, 9), crew: 8),
                       daily(d(2026, 3, 2), crew: 1)] // this week doesn't count yet
        let i = try XCTUnwrap(indicator(.crewShort, input(dailies: dailies, need: 6)))
        XCTAssertEqual(i.value, 2)
        XCTAssertTrue(i.tripped)
        XCTAssertEqual(indicator(.crewShort, input(dailies: Array(dailies.prefix(2)), need: 6))?.value, 1,
                       "a week with no report ends the run")
        XCTAssertNil(indicator(.crewShort, input(dailies: dailies)), "no crew need, nothing to compare")
    }

    func testOpenProblemsCountOnlyNearHandover() throws {
        let p = RoutineReport.Problem(description: "รอสาย AC", since: d(2026, 3, 2))
        var closed = RoutineReport.Problem(description: "ฝนตก", since: d(2026, 3, 1))
        let dailies = [daily(d(2026, 3, 1), crew: 5, problems: [closed]), daily(d(2026, 3, 2), crew: 5, problems: [p])]
        XCTAssertNil(indicator(.openProblems, input(dailies: dailies)), "handover more than 14 days off")
        closed.closed = true
        let near = input(dailies: dailies + [daily(d(2026, 3, 3), crew: 5, problems: [closed, p])], end: d(2026, 3, 15))
        let i = try XCTUnwrap(indicator(.openProblems, near))
        XCTAssertEqual(i.value, 1)
        XCTAssertTrue(i.tripped)
        XCTAssertTrue(i.detail.contains("อีก 11 วันส่งมอบ"), i.detail)
    }

    func testWeeklyRequestLateUntilSent() throws {
        let i = try XCTUnwrap(indicator(.requestLate, input()))
        XCTAssertEqual(i.value, 3, "Sunday to Wednesday")
        XCTAssertTrue(i.tripped)
        XCTAssertFalse(try XCTUnwrap(indicator(.requestLate, input(), today: d(2026, 3, 1))).tripped, "Sunday: not late yet")
        var r = RoutineReport.WeeklyRequest(weekStart: d(2026, 3, 1))
        XCTAssertEqual(indicator(.requestLate, input(requests: [r]))?.detail, "ร่างไว้ ยังไม่ส่งขออนุมัติ")
        r.sentAt = d(2026, 2, 27)
        XCTAssertEqual(indicator(.requestLate, input(requests: [r]))?.value, 0)
        XCTAssertNil(indicator(.requestLate, input(), today: d(2026, 5, 10)), "after the install period")
    }

    func testHandedOverStationHasNone() {
        var i = input(waits: [ERCFlow.Wait(step: .designResult, since: "2026-01-01", due: "2026-03-01", left: -3)])
        i.completed = true
        XCTAssertTrue(LeadingIndicators.compute(i, today: today, calendar: cal).isEmpty)
    }

    func testNotificationOncePerIndicatorOnTheNextMonday() throws {
        let tripped = LeadingIndicator(kind: .crewShort, value: 2, threshold: 2, detail: "ต้องการ 6 คน")
        let quiet = LeadingIndicator(kind: .requestLate, value: 0, threshold: 1)
        let wed = LeadingIndicatorNotification.plans(jobKey: "J1", station: "บ้านโป่ง", indicators: [tripped, quiet], now: d(2026, 3, 4, 10), calendar: cal)
        let plan = try XCTUnwrap(wed.first)
        XCTAssertEqual(wed.count, 1)
        XCTAssertEqual(plan.fireDate(now: d(2026, 3, 4, 10)), d(2026, 3, 9, 8))
        XCTAssertEqual(plan.type, .mp)
        XCTAssertEqual(plan.info[NotificationInfo.job], "J1")
        // the same plan, the same id all week, so it is posted once
        let sat = LeadingIndicatorNotification.plans(jobKey: "J1", station: "บ้านโป่ง", indicators: [tripped], now: d(2026, 3, 7, 20), calendar: cal)
        XCTAssertEqual(sat.first?.id, plan.id)
        XCTAssertEqual(sat.first?.fireDate(now: d(2026, 3, 7, 20)), d(2026, 3, 9, 8))
        // Sunday night: still Monday 9 มี.ค. 08:00
        let sun = LeadingIndicatorNotification.plans(jobKey: "J1", station: "บ้านโป่ง", indicators: [tripped], now: d(2026, 3, 8, 23), calendar: cal)
        XCTAssertEqual(sun.first?.id, plan.id)
    }

    func testCrewNeedScalesTheRecentCrewByTheNeededPace() throws {
        let input = MasterSchedule.Input(installStart: d(2026, 2, 1), installEnd: d(2026, 4, 18), kickoff: d(2026, 1, 10),
                                         engineeringStart: d(2026, 1, 12), siteHandover: d(2026, 1, 20), over200kVA: true)
        let dailies = [daily(d(2026, 3, 2), crew: 5), daily(d(2026, 3, 3), crew: 5)]
        XCTAssertNil(Assistant.Strategy.crewNeed(input: input, actual: .init(), dailies: [], workingWeekdays: [2, 3, 4, 5, 6, 7],
                                                 today: today, calendar: cal), "no crew reported")
        let need = try XCTUnwrap(Assistant.Strategy.crewNeed(input: input, actual: .init(), dailies: dailies,
                                                             workingWeekdays: [2, 3, 4, 5, 6, 7], today: today, calendar: cal))
        XCTAssertGreaterThan(need, 5, "nothing booked a month in: more than today's crew is needed")
    }

    func testAssistantGivesOnlyTrippedIndicators() throws {
        var job = Assistant.Job(id: "J1", station: "บ้านโป่ง", input: nil, canEdit: false)
        XCTAssertNil(job.trippedIndicators)
        job.indicators = [LeadingIndicator(kind: .requestLate, value: 0, threshold: 1),
                          LeadingIndicator(kind: .crewShort, value: 3, threshold: 2, detail: "ต้องการ 6 คน")]
        let t = try XCTUnwrap(job.trippedIndicators)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].kri, "R03")
        XCTAssertEqual(t[0].unit, "สัปดาห์")
    }
}

import XCTest
@testable import TCRoofCore

/// docs/ui/daily-report-ipad: the one-page daily report's figures, on a July 2025 (ก.ค. 2568) station.
final class RoutineDayTests: XCTestCase {
    typealias R = RoutineReport
    private let cal = RoutineReport.calendar

    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2025, month: 7, day: day))! }

    private func daily(_ day: Int, _ lines: [(MasterSchedule.Task?, String, Double)]) -> R.Daily {
        var r = R.Daily(date: d(day))
        r.progress = lines.map { .init(task: $0.0, description: "", location: $0.1, percent: $0.2) }
        return r
    }

    // MARK: station % today

    func testStationGainFromWeightsAndLocationCount() {
        // structure (20 %) reported at two roofs: each roof's 100 % today is 10 station points
        let before = [daily(1, [(.structure, "หลังคา 1", 0), (.structure, "หลังคา 2", 50)])]
        let today = daily(2, [(.structure, "หลังคา 1", 100), (.structure, "หลังคา 2", 50), (nil, "ลาน", 30)])
        let s = R.Settings()
        XCTAssertEqual(R.stationGain(today.progress[0], on: today, previous: before, settings: s, over200kVA: false), 10, accuracy: 1e-9)
        XCTAssertEqual(R.stationGain(today.progress[1], on: today, previous: before, settings: s, over200kVA: false), 0, accuracy: 1e-9)
        XCTAssertEqual(R.stationGain(today.progress[2], on: today, previous: before, settings: s, over200kVA: false), 0)
        XCTAssertEqual(R.stationGain(today, previous: before, settings: s, over200kVA: false), 10, accuracy: 1e-9)
        // the settings say structure covers five roofs: 100 % at one is 4 points
        var five = R.Settings()
        five.taskLocations["structure"] = ["หลังคา 1", "หลังคา 2", "หลังคา 3", "หลังคา 4", "หลังคา 5"]
        XCTAssertEqual(R.stationGain(today, previous: before, settings: five, over200kVA: false), 4, accuracy: 1e-9)
    }

    func testStandingAgainstThePlan() {
        let start = d(1)
        let input = MasterSchedule.Input(installStart: start, installEnd: cal.date(byAdding: .day, value: 60, to: start)!,
                                         kickoff: cal.date(byAdding: .day, value: -30, to: start)!,
                                         engineeringStart: cal.date(byAdding: .day, value: -20, to: start)!,
                                         siteHandover: cal.date(byAdding: .day, value: -2, to: start)!, over200kVA: false)
        let plan = MasterSchedule.plan(input)
        let today = daily(9, [(.structure, "หลังคา 1", 60)])
        let st = R.standing(.structure, on: today, previous: [], settings: R.Settings(), plan: plan)
        XCTAssertEqual(st.actual, 60, accuracy: 1e-9)
        let planned = MasterSchedule.status(plan: plan, actual: .init(), through: d(9)).plannedByTask[.structure] ?? 0
        XCTAssertEqual(st.planned, planned, accuracy: 1e-9)
        XCTAssertEqual(st.behind, planned - 60, accuracy: 1e-9)
    }

    // MARK: quick picks

    func testQuickPicksCappedAtWhatIsLeft() {
        XCTAssertEqual(R.quickPicks(before: 0), [10, 20, 30, 50, 100])
        XCTAssertEqual(R.quickPicks(before: 56), [10, 20, 30, 44])
        XCTAssertEqual(R.quickPicks(before: 80), [10, 20])
        XCTAssertEqual(R.quickPicks(before: 90), [10])
        XCTAssertEqual(R.quickPicks(before: 95), [5])
        XCTAssertEqual(R.quickPicks(before: 100), [])
    }

    // MARK: labour

    func testLabourHoursWithRainInsideAndOutsideTheWorkingTime() {
        var r = R.Daily(date: d(2))
        r.crew = [.init(name: "ผู้ปฏิบัติงาน", count: 9)]
        r.workStart = "08.00"; r.workEnd = "18.00"
        // rain 06–07 (before work), 13–16 (inside), 19 (after)
        r.weather = R.weatherHours.map { [6, 7, 13, 14, 15, 16, 19].contains($0) ? .rain : .fine }
        let l = R.labour(r)
        XCTAssertEqual(l.hours, 10)
        XCTAssertEqual(l.rainHours, 4)
        XCTAssertEqual(l.total, 90)
        XCTAssertEqual(l.working, 54)
        r.workEnd = "17:00"
        XCTAssertEqual(R.labour(r).total, 81)
        XCTAssertEqual(R.hour("8:30"), 8)
    }

    // MARK: planned work

    func testPlannedPinAddsALineForTheTaskAndLocation() {
        let start = d(1)
        let input = MasterSchedule.Input(installStart: start, installEnd: cal.date(byAdding: .day, value: 60, to: start)!,
                                         kickoff: cal.date(byAdding: .day, value: -30, to: start)!,
                                         engineeringStart: cal.date(byAdding: .day, value: -20, to: start)!,
                                         siteHandover: cal.date(byAdding: .day, value: -2, to: start)!, over200kVA: false)
        let plan = MasterSchedule.plan(input)
        let before = [daily(1, [(.structure, "หลังคา 1", 40), (.structure, "หลังคา 2", 100)])]
        let today = daily(2, [(.structure, "หลังคา 3", 10)])
        var s = R.Settings()
        // with no list for the task: where it was reported and isn't done
        var ghosts = R.plannedNotReported(on: today, previous: before, settings: s, plan: plan).filter { $0.task == .structure }
        XCTAssertEqual(ghosts.map(\.location), ["หลังคา 1"])
        XCTAssertEqual(ghosts[0].percent, 40)
        let added = R.startToday(ghosts[0])
        XCTAssertEqual(added.task, .structure)
        XCTAssertEqual(added.location, "หลังคา 1")
        XCTAssertEqual(added.percent, 50)
        XCTAssertNotEqual(added.id, ghosts[0].id)
        // the settings' list wins; today's location isn't offered again
        s.taskLocations["structure"] = ["หลังคา 3", "หลังคา 4"]
        ghosts = R.plannedNotReported(on: today, previous: before, settings: s, plan: plan).filter { $0.task == .structure }
        XCTAssertEqual(ghosts.map(\.location), ["หลังคา 4"])
        // a task not planned this week is never offered
        XCTAssertFalse(R.plannedNotReported(on: today, previous: before, settings: s, plan: plan).contains { $0.task == .training })
    }

    // MARK: days

    func testReportDaySkipsDaysOffAndStopsAtTheLimit() {
        let s = R.Settings()  // จ.–ส.
        // Sat 5 → Mon 7, skipping Sunday
        XCTAssertEqual(R.reportDay(from: d(5), by: 1, settings: s), d(7))
        XCTAssertEqual(R.reportDay(from: d(7), by: -1, settings: s), d(5))
        XCTAssertNil(R.reportDay(from: d(5), by: 1, settings: s, limit: d(6)))
        XCTAssertEqual(R.thaiWeekdayDate(d(2)), "พ. 2 ก.ค. 2568")
    }
}

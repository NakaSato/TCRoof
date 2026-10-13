import XCTest
@testable import TCRoofCore

final class PWAOverviewTests: XCTestCase {
    func station(_ id: String, kWp: Double = 100, actual: Double, plan: Double?, contractor: String = "A", sent: Bool? = true) -> InstallStationSummary {
        InstallStationSummary(id: id, name: id, kWp: kWp, actual: actual, plan: plan, contractor: contractor, reportSentToday: sent)
    }

    func testPaceUsesTheThresholdOnBothSides() {
        XCTAssertEqual(InstallOverview.pace(station("a", actual: 48, plan: 50)), .behind)
        XCTAssertEqual(InstallOverview.pace(station("b", actual: 49, plan: 50)), .onPlan)
        XCTAssertEqual(InstallOverview.pace(station("c", actual: 51, plan: 50)), .onPlan)
        XCTAssertEqual(InstallOverview.pace(station("d", actual: 52, plan: 50)), .ahead)
        XCTAssertEqual(InstallOverview.pace(station("e", actual: 47, plan: 50), threshold: 5), .onPlan)
        XCTAssertEqual(InstallOverview.pace(station("f", actual: 45, plan: 50), threshold: 5), .behind)
    }

    func testNoPlanIsNeitherBehindNorAhead() {
        let s = station("a", actual: 10, plan: nil)
        XCTAssertNil(InstallOverview.pace(s))
        XCTAssertNil(s.variance)
        let t = InstallOverview.totals([s])
        XCTAssertNil(t.plan)
        XCTAssertEqual([t.behind, t.onPlan, t.ahead], [0, 0, 0])
    }

    func testBarMarksDoneCurrentAndOverdueSegments() {
        typealias B = InstallOverview.BarSegment
        // the board's late card: 22 % of a 28 % plan
        XCTAssertEqual(InstallOverview.bar(station("a", actual: 22, plan: 28)),
                       [B.done, .done, .current] + Array(repeating: B.ahead, count: 7))
        // behind by more than a segment: the plan's segments past the current one are overdue
        XCTAssertEqual(InstallOverview.bar(station("b", actual: 22, plan: 51)),
                       [B.done, .done, .current, .overdue, .overdue, .overdue] + Array(repeating: B.ahead, count: 4))
        // on plan or with no plan nothing is overdue
        XCTAssertEqual(InstallOverview.bar(station("c", actual: 71, plan: 68)),
                       Array(repeating: B.done, count: 7) + [B.current, .ahead, .ahead])
        XCTAssertFalse(InstallOverview.bar(station("d", actual: 5, plan: nil)).contains(.overdue))
        XCTAssertEqual(InstallOverview.bar(station("e", actual: 100, plan: 100)), Array(repeating: B.done, count: 10))
    }

    func testAveragesAreWeightedByKWp() {
        let t = InstallOverview.totals([station("a", kWp: 300, actual: 20, plan: 40), station("b", kWp: 100, actual: 60, plan: 80)])
        XCTAssertEqual(t.actual, 30)
        XCTAssertEqual(t.plan, 50)
        XCTAssertEqual(t.kWp, 400)
    }

    func testAveragesAreEqualWhenNoStationHasKWp() {
        let t = InstallOverview.totals([station("a", kWp: 0, actual: 20, plan: 40), station("b", kWp: 0, actual: 60, plan: 80)])
        XCTAssertEqual(t.actual, 40)
        XCTAssertEqual(t.plan, 60)
        XCTAssertNil(InstallOverview.weighted([]))
    }

    func testPlanAverageSkipsStationsWithoutAPlan() {
        let t = InstallOverview.totals([station("a", kWp: 100, actual: 20, plan: 40), station("b", kWp: 900, actual: 60, plan: nil)])
        XCTAssertEqual(t.plan, 40)
        XCTAssertEqual(t.actual, 56)
    }

    func testTotalsCountPaceAndReports() {
        let t = InstallOverview.totals([
            station("a", actual: 38, plan: 50, sent: true), station("b", actual: 50, plan: 52, sent: false),
            station("c", actual: 71, plan: 68, sent: true), station("d", actual: 8, plan: 8, sent: nil),
        ])
        XCTAssertEqual([t.behind, t.onPlan, t.ahead], [2, 1, 1])
        XCTAssertEqual([t.reporting, t.sent, t.unsent], [3, 2, 1])
    }

    func testContractorsCountStationsAndBehind() {
        let c = InstallOverview.contractors([
            station("a", actual: 38, plan: 50, contractor: "B"), station("b", actual: 50, plan: 50, contractor: "A"),
            station("c", actual: 20, plan: 30, contractor: "B"), station("d", actual: 1, plan: 1, contractor: ""),
        ])
        XCTAssertEqual(c, [.init(name: "A", stations: 1, behind: 0), .init(name: "B", stations: 2, behind: 2)])
    }

    func testRowsFilterAndSortMostBehindFirst() {
        let all = [station("a", actual: 71, plan: 68), station("b", actual: 22, plan: 28, contractor: "B", sent: false),
                   station("c", actual: 38, plan: 50), station("d", actual: 5, plan: nil, sent: false)]
        XCTAssertEqual(InstallOverview.rows(all, filter: .behind).map(\.id), ["c", "b"])
        XCTAssertEqual(InstallOverview.rows(all, filter: .noReport).map(\.id), ["b", "d"])
        XCTAssertEqual(InstallOverview.rows(all, filter: .all).map(\.id), ["c", "b", "a", "d"])
        XCTAssertEqual(InstallOverview.rows(all, filter: .all, contractor: "B").map(\.id), ["b"])
    }

    func testMaintenanceTotals() {
        let t = MaintenanceOverview.totals([
            .init(id: "a", name: "a", kWp: 100, energy: 300, expected: 400, pr: 80),
            .init(id: "b", name: "b", kWp: 300, energy: 100, expected: 400, pr: 60, status: .alarm),
            .init(id: "c", name: "c", kWp: 100, energy: 0, expected: 200, pr: 0, status: .offline),
        ])
        XCTAssertEqual(t.yield, 40)
        XCTAssertEqual(t.pr, 65, "the offline station is left out of the PR average")
        XCTAssertEqual([t.normal, t.alarm, t.offline], [1, 1, 1])
        XCTAssertNil(MaintenanceOverview.totals([]).pr)
    }

    func testMaintenanceFiltersAndDueTasks() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))!
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: now))! }
        let ok = MaintenanceStationSummary(id: "a", name: "a", nextPM: day(14))
        let late = MaintenanceStationSummary(id: "b", name: "b", status: .offline, nextPM: day(15))
        XCTAssertTrue(MaintenanceOverview.matches(ok, .pmSoon, now: now, calendar: cal))
        XCTAssertFalse(MaintenanceOverview.matches(late, .pmSoon, now: now, calendar: cal))
        XCTAssertFalse(MaintenanceOverview.matches(ok, .issue, now: now, calendar: cal))
        XCTAssertTrue(MaintenanceOverview.matches(late, .issue, now: now, calendar: cal))
        let tasks = [MaintenanceTask(id: "1", date: day(20), title: "x", assignee: ""), .init(id: "2", date: day(7), title: "y", assignee: ""),
                     .init(id: "3", date: day(-1), title: "z", assignee: ""), .init(id: "4", date: day(0), title: "w", assignee: "")]
        XCTAssertEqual(MaintenanceOverview.due(tasks, now: now, calendar: cal).map(\.id), ["4", "2"])
    }
}

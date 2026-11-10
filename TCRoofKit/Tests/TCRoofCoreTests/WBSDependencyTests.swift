import XCTest
@testable import TCRoofCore

final class WBSDependencyTests: XCTestCase {
    let cal = MasterSchedule.calendar
    func d(_ day: Int) -> Date {
        cal.date(byAdding: .day, value: day, to: cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!)!
    }
    func item(_ code: String, _ day: Int, _ days: Int = 1, after links: [MasterSchedule.WBSDependency] = []) -> MasterSchedule.WorkItem {
        var item = MasterSchedule.WorkItem(code: code, title: code)
        item.baselineStart = d(day); item.baselineEnd = d(day + days - 1); item.days = days
        item.dependencies = links.isEmpty ? nil : links
        return item
    }
    func testUnconfiguredPlansKeepTheirDatesAndProse() {
        var row = item("2.1.1", 0)
        row.predecessor = "ย้อนจาก 2.10 (60 วัน)"
        let result = WBSDependencies.schedule([row])
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.forecasts.isEmpty)
    }
    func testFinishToStartAndWorkingDayLag() throws {
        let a = item("2.1.1", 0, 2)
        let b = item("2.2.1", 0, 2, after: [.init(predecessor: a.code, lagDays: 2)])
        let result = WBSDependencies.schedule([b, a], calendar: cal)
        XCTAssertTrue(result.isValid)
        let forecast = try XCTUnwrap(result.forecasts[b.code])
        XCTAssertEqual(forecast.start, d(4))
        XCTAssertEqual(forecast.end, d(5))
        XCTAssertTrue(forecast.critical)
        XCTAssertEqual(result.forecasts[a.code]?.float, 0)
        XCTAssertEqual(b.baselineStart, d(0))
    }
    func testHolidaysAreSkippedInLagAndDuration() {
        let a = item("2.1.1", 4)
        let b = item("2.2.1", 4, 2, after: [.init(predecessor: a.code, lagDays: 1)])
        let result = WBSDependencies.schedule([a, b], nonWorking: [d(5), d(6), d(8)], calendar: cal)
        XCTAssertEqual(result.forecasts[b.code]?.start, d(9))
        XCTAssertEqual(result.forecasts[b.code]?.end, d(10))
    }
    func testParallelBranchesHaveExplicitCriticalPathAndFloat() {
        let a = item("2.1.1", 0, 3)
        let b = item("2.2.1", 0)
        let c = item("2.3.1", 0, after: [.init(predecessor: a.code), .init(predecessor: b.code)])
        let result = WBSDependencies.schedule([a, b, c], calendar: cal)
        XCTAssertEqual(result.forecasts[c.code]?.start, d(3))
        XCTAssertEqual(result.forecasts[a.code]?.float, 0)
        XCTAssertEqual(result.forecasts[b.code]?.float, 2)
        XCTAssertEqual(result.forecasts[c.code]?.float, 0)
    }
    func testReleaseDatesDoNotMoveEarlierAndUnlinkedRowsStayPut() {
        let a = item("2.1.1", 0)
        let b = item("2.2.1", 10, after: [.init(predecessor: a.code)])
        let separate = item("2.4.1", 2, 2)
        let result = WBSDependencies.schedule([a, b, separate], calendar: cal)
        XCTAssertEqual(result.forecasts[b.code]?.start, d(10))
        XCTAssertEqual(result.forecasts[separate.code]?.start, d(2))
        XCTAssertEqual(result.forecasts[separate.code]?.end, d(3))
    }
    func testMissingPredecessorAndNegativeLagAreRejected() {
        let a = item("2.1.1", 0, after: [.init(predecessor: "missing", lagDays: -1)])
        let result = WBSDependencies.schedule([a])
        XCTAssertTrue(result.forecasts.isEmpty)
        XCTAssertTrue(result.issues.contains(.missingPredecessor(task: a.code, predecessor: "missing")))
        XCTAssertTrue(result.issues.contains(.negativeLag(task: a.code, predecessor: "missing")))
    }
    func testCycleIncludesOnlyItsMembersNotBlockedSuccessor() {
        let a = item("2.1.1", 0, after: [.init(predecessor: "2.2.1")])
        let b = item("2.2.1", 0, after: [.init(predecessor: "2.1.1")])
        let c = item("2.3.1", 0, after: [.init(predecessor: a.code)])
        let result = WBSDependencies.schedule([a, b, c])
        XCTAssertEqual(result.issues, [.cycle([a.code, b.code, a.code])])
        XCTAssertTrue(result.forecasts.isEmpty)
    }
    func testSelfCycleAndDuplicateLinksAreRejected() {
        var a = item("2.1.1", 0, after: [.init(predecessor: "2.1.1")])
        XCTAssertEqual(WBSDependencies.schedule([a]).issues, [.cycle([a.code, a.code])])
        a.dependencies = [.init(predecessor: "2.2.1"), .init(predecessor: "2.2.1")]
        XCTAssertTrue(WBSDependencies.schedule([a, item("2.2.1", 0)]).issues.contains(.duplicateLink(task: a.code, predecessor: "2.2.1")))
    }
    func testSummaryAndInactiveRowsCannotBePredecessors() {
        var part = item("2", 0)
        part.dependencies = [.init(predecessor: "2.2.1")]
        let result = WBSDependencies.schedule([part, item("2.1", 0), item("2.1.1", 0), item("2.2.1", 0)])
        XCTAssertTrue(result.issues.contains(.invalidEndpoint("2")))
        var inactive = item("2.4.1", 0)
        inactive.title += " (ไม่ต้องยื่น)"
        XCTAssertTrue(WBSDependencies.schedule([inactive, item("2.2.1", 0, after: [.init(predecessor: inactive.code)])]).issues.contains(.invalidEndpoint(inactive.code)))
    }
    func testMissingDatesAndDuplicateCodesAreRejected() {
        var a = item("2.1.1", 0)
        a.baselineStart = nil
        let b = item("2.2.1", 0, after: [.init(predecessor: a.code)])
        XCTAssertTrue(WBSDependencies.schedule([a, b]).issues.contains(.invalidDates(a.code)))
        XCTAssertTrue(WBSDependencies.schedule([b, b]).issues.contains(.duplicateCode(b.code)))
    }
    func testOldJSONDecodesAndConfiguredLinksRoundTrip() throws {
        let old = Data(#"{"code":"2.1.1","title":"old","weight":1,"level":2}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(MasterSchedule.WorkItem.self, from: old).dependencies)
        let row = item("2.2.1", 0, after: [.init(predecessor: "2.1.1", lagDays: 3)])
        XCTAssertEqual(try JSONDecoder().decode(MasterSchedule.WorkItem.self, from: JSONEncoder().encode(row)), row)
    }

    func testProjectCalendarAppliesBeyondOriginalPlanEnd() {
        var settings = RoutineReport.Settings()
        settings.workingWeekdays = [2, 3, 4, 5, 6]
        settings.holidays = [RoutineReport.dayKey(d(8))]
        let a = item("2.1.1", 4)
        let b = item("2.2.1", 4, 2, after: [.init(predecessor: a.code, lagDays: 1)])
        let result = WBSDependencies.schedule([a, b], settings: settings, calendar: cal)
        XCTAssertEqual(result.forecasts[b.code]?.start, d(9))
        XCTAssertEqual(result.forecasts[b.code]?.end, d(10))
        settings.workingWeekdays = []
        XCTAssertEqual(WBSDependencies.schedule([a, b], settings: settings).issues, [.noWorkingDays])
    }

    func testExtremeLagIsRejectedBeforeCalendarArithmetic() {
        let a = item("2.1.1", 0)
        let b = item("2.2.1", 0, after: [.init(predecessor: a.code, lagDays: Int.max)])
        XCTAssertEqual(WBSDependencies.schedule([a, b]).issues, [.invalidLag(task: b.code, predecessor: a.code)])
    }

    func testConstructionPlanShowsForecastAndKeepsBaseline() throws {
        let g = InstallGantt(rows: [
            .init(id: "structure", code: "2.1", title: "structure", status: .waiting, start: d(0), end: d(1), percent: 0),
            .init(id: "panels", code: "2.3", title: "panels", status: .waiting, start: d(0), end: d(1), percent: 0)
        ], today: d(0))
        let a = item("2.1.1", 0, 2)
        let b = item("2.3.1", 0, 2, after: [.init(predecessor: a.code, lagDays: 1)])
        let rows = [item("2.1", 0, 2), a, item("2.3", 0, 2), b]
        var plan = InstallPlan(gantt: g, nonWorking: [], tracking: nil, calendar: cal)
        plan.useWBS(rows, ticked: [], calendar: cal)
        let forecast = try XCTUnwrap(plan.stages.last?.subs.first)
        XCTAssertEqual(forecast.start, d(3))
        XCTAssertEqual(forecast.end, d(4))
        XCTAssertEqual(forecast.baselineStart, d(0))
        XCTAssertEqual(forecast.baselineEnd, d(1))
        XCTAssertEqual(forecast.after, a.code + " +1 วัน")
        XCTAssertTrue(forecast.critical)
        XCTAssertEqual(plan.end, d(4))
        XCTAssertEqual(plan.stages.last?.row.end, d(4))
        XCTAssertTrue(plan.dependencyIssues.isEmpty)
        var invalid = rows
        invalid[3].dependencies = [.init(predecessor: "missing")]
        var unchanged = InstallPlan(gantt: g, nonWorking: [], tracking: nil, calendar: cal)
        unchanged.useWBS(invalid, ticked: [], calendar: cal)
        XCTAssertEqual(unchanged.end, d(1))
        XCTAssertFalse(unchanged.dependencyIssues.isEmpty)
    }

    func testForecastHeaderRespectsWorkingSundays() {
        var settings = RoutineReport.Settings()
        settings.workingWeekdays = Set(1...7)
        let g = InstallGantt(rows: [
            .init(id: "structure", code: "2.1", title: "structure", status: .waiting, start: d(5), end: d(6), percent: 0),
            .init(id: "panels", code: "2.3", title: "panels", status: .waiting, start: d(5), end: d(6), percent: 0)
        ], today: d(5))
        var plan = InstallPlan(gantt: g, nonWorking: [], tracking: nil, calendar: cal)
        plan.useWBS([item("2.1.1", 5), item("2.3.1", 5, after: [.init(predecessor: "2.1.1")])], ticked: [], settings: settings, calendar: cal)
        XCTAssertEqual(plan.stages.last?.subs.first?.start, d(6))
        XCTAssertEqual(plan.workingDays, 2)
    }

    // MARK: start-to-start and finish-to-finish (CHA-76)

    func testStartToStartAndFinishToFinishMoveTheStartAndTheFinish() throws {
        let a = item("2.1.1", 0, 4)
        let b = item("2.3.1", 0, 2, after: [.init(predecessor: a.code, lagDays: 3, type: .startToStart),
                                            .init(predecessor: a.code, lagDays: 2, type: .finishToFinish)])
        let result = WBSDependencies.schedule([a, b], calendar: cal)
        XCTAssertTrue(result.isValid, result.issues.map(\.message).joined(separator: "\n"))
        let forecast = try XCTUnwrap(result.forecasts[b.code])
        XCTAssertEqual(forecast.start, d(3), "SS+3: three working days after 2.1.1 starts")
        XCTAssertEqual(forecast.end, d(5), "FF+2: stretched to two working days after 2.1.1 finishes")
        XCTAssertEqual(result.forecasts[a.code]?.float, 0)
    }

    func testStartToStartLagZeroStartsTheSameDayAndLeavesFloat() {
        let a = item("2.1.1", 0, 4)
        let b = item("2.5.1", 0, 2, after: [.init(predecessor: a.code, type: .startToStart)])
        let result = WBSDependencies.schedule([a, b], calendar: cal)
        XCTAssertEqual(result.forecasts[b.code]?.start, d(0))
        XCTAssertEqual(result.forecasts[b.code]?.end, d(1))
        XCTAssertEqual(result.forecasts[b.code]?.float, 2, "it can slip until 2.1.1's finish")
    }

    func testFinishToFinishOnlyLaterThanTheRowsOwnFinish() {
        let a = item("2.1.1", 0, 2)
        let b = item("2.2.1", 0, 4, after: [.init(predecessor: a.code, type: .finishToFinish)])
        let result = WBSDependencies.schedule([a, b], calendar: cal)
        XCTAssertEqual(result.forecasts[b.code]?.start, d(0))
        XCTAssertEqual(result.forecasts[b.code]?.end, d(3))
    }

    func testSameRowLinkedBySSAndFFIsNotADuplicate() {
        let a = item("2.1.1", 0)
        let b = item("2.3.1", 0, after: [.init(predecessor: a.code, type: .startToStart), .init(predecessor: a.code, type: .finishToFinish)])
        XCTAssertTrue(WBSDependencies.schedule([a, b]).isValid)
        let c = item("2.3.1", 0, after: [.init(predecessor: a.code, type: .startToStart), .init(predecessor: a.code, lagDays: 1, type: .startToStart)])
        XCTAssertTrue(WBSDependencies.schedule([a, c]).issues.contains(.duplicateLink(task: c.code, predecessor: a.code)))
    }

    func testOldLinksDecodeAsFinishToStartAndStayWrittenWithoutAType() throws {
        let old = Data(#"{"predecessor":"2.1.1","lagDays":2}"#.utf8)
        let link = try JSONDecoder().decode(MasterSchedule.WBSDependency.self, from: old)
        XCTAssertEqual(link, .init(predecessor: "2.1.1", lagDays: 2))
        XCTAssertEqual(link.type, .finishToStart)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(link), as: UTF8.self), #"{"lagDays":2,"predecessor":"2.1.1"}"#)
        let ss = MasterSchedule.WBSDependency(predecessor: "2.1", lagDays: 3, type: .startToStart)
        XCTAssertEqual(try JSONDecoder().decode(MasterSchedule.WBSDependency.self, from: encoder.encode(ss)), ss)
        XCTAssertEqual(ss.label, "2.1 SS+3")
        XCTAssertEqual(link.label, "2.1.1 +2 วัน")
    }

    func testTaskLinesLinkAndTheirSubTasksFollow() throws {
        let rows = [item("2.1", 0, 4), item("2.1.1", 0, 2), item("2.1.2", 2, 2),
                    item("2.3", 0, 4, after: [.init(predecessor: "2.1", lagDays: 2, type: .startToStart)]),
                    item("2.3.1", 0, 2), item("2.3.2", 2, 2)]
        let result = WBSDependencies.schedule(rows, calendar: cal)
        XCTAssertTrue(result.isValid, result.issues.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(result.forecasts["2.3"]?.start, d(2))
        XCTAssertEqual(result.forecasts["2.3"]?.end, d(5))
        XCTAssertEqual(result.forecasts["2.3.1"]?.start, d(2))
        XCTAssertEqual(result.forecasts["2.3.1"]?.end, d(3))
        XCTAssertEqual(result.forecasts["2.3.2"]?.start, d(4))
        XCTAssertEqual(result.forecasts["2.3.2"]?.end, d(5))
        XCTAssertEqual(result.forecasts["2.1.2"]?.start, d(2), "the predecessor's sub-tasks stay")
    }

    func testASubTaskCannotBeLinkedInsideALinkedTaskLine() {
        let rows = [item("2.1", 0, 4), item("2.1.1", 0, 2),
                    item("2.3", 0, 4, after: [.init(predecessor: "2.1", type: .startToStart)]),
                    item("2.3.1", 0, 2, after: [.init(predecessor: "2.1.1")])]
        let issues = WBSDependencies.schedule(rows).issues
        XCTAssertTrue(issues.contains(.linkedInsideTask(task: "2.1", sub: "2.1.1")))
        XCTAssertTrue(issues.contains(.linkedInsideTask(task: "2.3", sub: "2.3.1")))
    }

    func testParsesTheWorkbooksTypedLinksOnly() {
        XCTAssertEqual(WBSDependencies.parse("2.1 SS+3, 2.1 FF+2"),
                       [.init(predecessor: "2.1", lagDays: 3, type: .startToStart), .init(predecessor: "2.1", lagDays: 2, type: .finishToFinish)])
        XCTAssertEqual(WBSDependencies.parse("Master Plan, FS 2.1–2.9+0").map(\.predecessor), (1...9).map { "2.\($0)" })
        XCTAssertEqual(WBSDependencies.parse("Master Plan, FS 2.2, 2.3+1"),
                       [.init(predecessor: "2.2", lagDays: 1), .init(predecessor: "2.3", lagDays: 1)])
        XCTAssertEqual(WBSDependencies.parse("ย้อนจาก 2.10 (60 วัน)"), [])
        XCTAssertEqual(WBSDependencies.parse("3.2.7, 3.2.6"), [])
        XCTAssertEqual(WBSDependencies.parse("Master Plan"), [])
    }

    func testWorkbookLinksSkipRowsThisStationLeavesOut() throws {
        func row(_ code: String, _ text: String?, title: String? = nil) -> MasterSchedule.WorkItem {
            var r = item(code, 0, 2)
            r.predecessor = text
            if let title { r.title = title }
            return r
        }
        let rows = [row("2.1", "ย้อนจาก 2.10 (4 วัน)"), row("2.1.1", nil), row("2.2", "2.3 SS+1, 2.3 FF+1"),
                    row("2.3", "2.1 SS+3, 2.1 FF+2"),
                    row("2.4", "2.2 SS+2, 2.2 FF+0", title: "2.4 Firefighter (ไม่ต้องติดตั้ง)"),
                    row("2.10", "Master Plan, FS 2.1–2.9+0")]
        let linked = try XCTUnwrap(WBSDependencies.fromWorkbook(rows))
        let links = Dictionary(uniqueKeysWithValues: linked.map { ($0.code, $0.dependencies ?? []) })
        XCTAssertEqual(links["2.3"]?.map(\.label), ["2.1 SS+3", "2.1 FF+2"])
        XCTAssertEqual(links["2.4"], [], "a row the station leaves out gets no links")
        XCTAssertEqual(links["2.10"]?.map(\.predecessor), ["2.1", "2.2", "2.3"], "2.4 left out, 2.5–2.9 missing")
        XCTAssertEqual(links["2.1"], [])
        XCTAssertTrue(WBSDependencies.schedule(linked, calendar: cal).isValid)
        XCTAssertNil(WBSDependencies.fromWorkbook([row("2.1", "Master Plan")]))
    }
}

import XCTest
@testable import TCRoofCore

final class InstallSummaryWorkerTests: XCTestCase {
    private let calendar = MasterSchedule.calendar

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func input(_ id: String) throws -> InstallSummaryInput {
        let plan = MasterSchedule.Input(installStart: date(1), installEnd: date(30), kickoff: date(1),
                                        engineeringStart: date(1), siteHandover: date(1), over200kVA: true)
        return InstallSummaryInput(base: .init(id: id, mpNumber: 189, name: "Station \(id)", kWp: 100,
                                              actual: 0, contractor: "TCR01", dueDate: date(30), reportSentToday: false),
                                   planJSON: String(decoding: try JSONEncoder().encode(plan), as: UTF8.self), actualJSON: nil)
    }

    func testBackgroundSummaryKeepsScheduleAndPermitResults() async throws {
        let input = try input("one")
        let now = date(25)
        let planInput = try JSONDecoder().decode(MasterSchedule.Input.self, from: Data(input.planJSON!.utf8))
        let plan = MasterSchedule.plan(planInput)
        let status = MasterSchedule.status(plan: plan, actual: .init(), through: now)
        let result = await InstallSummaryWorker().summaries([input], at: now)
        XCTAssertEqual(result.first?.actual, status.actual)
        XCTAssertEqual(result.first?.plan, status.planned)
        XCTAssertEqual(result.first?.permits, InstallOverview.permits(RoutineReport.permits(plan: plan, actual: .init(), at: now)))
        XCTAssertEqual(result.first?.name, input.base.name)
        XCTAssertEqual(result.first?.dueDate, input.base.dueDate)
    }

    func testOnlyEditedStationIsRebuiltAndOrderIsPreserved() async throws {
        let worker = InstallSummaryWorker()
        let first = try input("one")
        var second = try input("two")
        _ = await worker.summaries([first, second], at: date(25))
        let count = await worker.calculationCount
        XCTAssertEqual(count, 2)
        _ = await worker.summaries([second, first], at: date(25).addingTimeInterval(60))
        let unchanged = await worker.calculationCount
        XCTAssertEqual(unchanged, 2, "scrolling, tab switches and the minute tick reuse results")
        second.base.name = "Renamed"
        second.base.reportSentToday = true
        let result = await worker.summaries([second, first], at: date(25))
        XCTAssertEqual(result.map(\.id), ["two", "one"])
        XCTAssertEqual(result.first?.name, "Renamed")
        XCTAssertEqual(result.first?.reportSentToday, true)
        let edited = await worker.calculationCount
        XCTAssertEqual(edited, 3)
    }

    func testPlanProgressDayRolloverAndRemovalInvalidateResults() async throws {
        let worker = InstallSummaryWorker()
        var input = try input("one")
        _ = await worker.summaries([input], at: date(25))
        var actual = MasterSchedule.Actual()
        actual.points[MasterSchedule.Task.structure.rawValue] = [MasterSchedule.Actual.key(date(25)): 5]
        input.actualJSON = String(decoding: try JSONEncoder().encode(actual), as: UTF8.self)
        let progress = await worker.summaries([input], at: date(25))
        XCTAssertGreaterThan(progress.first?.actual ?? 0, 0)
        _ = await worker.summaries([input], at: date(26))
        let count = await worker.calculationCount
        XCTAssertEqual(count, 3)
        let removed = await worker.summaries([], at: date(26))
        XCTAssertTrue(removed.isEmpty)
        _ = await worker.summaries([input], at: date(26))
        let reinserted = await worker.calculationCount
        XCTAssertEqual(reinserted, 4)
        input.planJSON = "invalid JSON"
        let fallback = await worker.summaries([input], at: date(26))
        XCTAssertEqual(fallback, [input.base], "a missing or invalid plan still shows the project")
    }

    func testOneHundredThreeStationsReuseTheirSummaries() async throws {
        let worker = InstallSummaryWorker()
        let inputs = try (1...103).map { try input(String($0)) }
        let start = Date()
        let first = await worker.summaries(inputs, at: date(25))
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        for _ in 0..<10 {
            let reused = await worker.summaries(inputs, at: date(25))
            XCTAssertEqual(reused, first)
        }
        let builds = await worker.calculationCount
        XCTAssertEqual(builds, 103, "opening and redrawing the same 103 projects must not rebuild them")
        print("PROJECT SUMMARIES: 103 cold=\(Int(cold * 1000))ms; 10 cached passes=\(Int(Date().timeIntervalSince(warmStart) * 1000))ms")
    }
}

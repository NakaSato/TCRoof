import XCTest
@testable import TCRoofCore

final class PlanLanesTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()
    /// Sunday 27 Sep 2026.
    private var week: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 27))! }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: week)! }
    private func jobs(_ spans: [(String, Int, Int)]) -> [(id: String, start: Date, end: Date)] {
        spans.map { (id: $0.0, start: day($0.1), end: day($0.2)) }
    }

    func testNoOverlapSharesOneLane() {
        let lanes = PlanLanes.assign(jobs([("a", 0, 1), ("b", 3, 4), ("c", 6, 9)]), calendar: cal)
        XCTAssertEqual(Set(lanes.values), [0])
    }

    func testThreeOverlappingJobsTakeThreeLanes() {
        let lanes = PlanLanes.assign(jobs([("a", 0, 5), ("b", 1, 4), ("c", 2, 3)]), calendar: cal)
        XCTAssertEqual(lanes, ["a": 0, "b": 1, "c": 2])
    }

    func testLaneIsReusedAfterAJobEnds() {
        let lanes = PlanLanes.assign(jobs([("a", 0, 2), ("b", 1, 8), ("c", 3, 4)]), calendar: cal)
        XCTAssertEqual(lanes["c"], 0)
        XCTAssertEqual(lanes["b"], 1)
    }

    func testJobStartingOnTheDayAnotherEndsNeedsANewLane() {
        let lanes = PlanLanes.assign(jobs([("a", 0, 2), ("b", 2, 3)]), calendar: cal)
        XCTAssertEqual(lanes, ["a": 0, "b": 1])
    }

    func testInputOrderDoesNotMatter() {
        let lanes = PlanLanes.assign(jobs([("late", 4, 5), ("early", 0, 6)]), calendar: cal)
        XCTAssertEqual(lanes, ["early": 0, "late": 1])
    }

    func testSegmentsKeepTheLaneAcrossWeeksAndFlagContinuation() {
        let all = jobs([("long", 3, 14), ("short", 8, 9)])
        let lanes = PlanLanes.assign(all, calendar: cal)
        let first = PlanLanes.segments(all, lanes: lanes, weekStart: week, calendar: cal)
        let second = PlanLanes.segments(all, lanes: lanes, weekStart: day(7), calendar: cal)
        let third = PlanLanes.segments(all, lanes: lanes, weekStart: day(14), calendar: cal)

        XCTAssertEqual(first.map(\.id), ["long"])
        XCTAssertEqual(first[0].startColumn, 3)
        XCTAssertEqual(first[0].endColumn, 6)
        XCTAssertFalse(first[0].continuesBefore)
        XCTAssertTrue(first[0].continuesAfter)

        XCTAssertEqual(second.map(\.id), ["long", "short"])
        XCTAssertEqual(second.map(\.lane), [0, 1])
        XCTAssertTrue(second[0].continuesBefore && second[0].continuesAfter)
        XCTAssertEqual(second[1].startColumn, 1)
        XCTAssertEqual(second[1].endColumn, 2)

        XCTAssertEqual(third.map(\.lane), [0])
        XCTAssertEqual(third[0].endColumn, 0)
        XCTAssertTrue(third[0].continuesBefore)
        XCTAssertFalse(third[0].continuesAfter)
    }
}

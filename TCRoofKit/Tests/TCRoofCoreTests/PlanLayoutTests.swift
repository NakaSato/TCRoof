import XCTest
@testable import TCRoofCore

final class PlanLayoutTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()
    /// Sunday 4 Oct 2026.
    private var week: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 4))! }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: week)! }
    private func lanes(_ jobs: [(id: String, start: Int, end: Int)]) -> [PlanLayout.Bar<String>] {
        PlanLayout.lanes(for: jobs.map { (id: $0.id, start: day($0.start), end: day($0.end)) }, weekStart: week, calendar: cal)
    }

    func testOverlappingJobsTakeSeparateLanes() {
        let bars = lanes([("a", 1, 3), ("b", 2, 4)])
        XCTAssertEqual(bars.map(\.id), ["a", "b"])
        XCTAssertEqual(bars.map(\.lane), [0, 1])
    }

    func testLaterJobReusesFreedLane() {
        let bars = lanes([("a", 0, 2), ("b", 1, 5), ("c", 3, 4)])
        XCTAssertEqual(bars.first { $0.id == "c" }?.lane, 0)
    }

    func testLongerJobFirstOnTheSameDay() {
        let bars = lanes([("short", 2, 2), ("long", 2, 5)])
        XCTAssertEqual(bars.map(\.id), ["long", "short"])
    }

    func testFourthOverlappingJobIsDropped() {
        let bars = lanes([("a", 0, 6), ("b", 1, 6), ("c", 2, 6), ("d", 3, 4)])
        XCTAssertEqual(bars.map(\.id), ["a", "b", "c"])
    }

    func testColumnsClipToTheWeekWithContinuationFlags() {
        let bars = lanes([("before", -3, 1), ("after", 5, 9), ("both", -1, 8), ("inside", 2, 3), ("outside", 7, 9)])
        let byID = Dictionary(uniqueKeysWithValues: bars.map { ($0.id, $0) })
        XCTAssertNil(byID["outside"])
        XCTAssertEqual(byID["before"].map { [$0.startColumn, $0.endColumn] }, [0, 1])
        XCTAssertEqual(byID["before"]?.continuesBefore, true)
        XCTAssertEqual(byID["before"]?.continuesAfter, false)
        XCTAssertEqual(byID["after"].map { [$0.startColumn, $0.endColumn] }, [5, 6])
        XCTAssertEqual(byID["after"]?.continuesBefore, false)
        XCTAssertEqual(byID["after"]?.continuesAfter, true)
        XCTAssertEqual(byID["both"].map { [$0.continuesBefore, $0.continuesAfter] }, [true, true])
        XCTAssertEqual(byID["inside"].map { [$0.continuesBefore, $0.continuesAfter] }, [false, false])
        XCTAssertEqual(byID["inside"]?.span, 2)
    }

    func testShortName() {
        XCTAssertEqual(PlanLayout.shortName("คุณดารา ภัทรปรีดา"), "ดารา ภัทรปรีดา")
        XCTAssertEqual(PlanLayout.shortName("บริษัท คิดดี จำกัด"), "คิดดี จำกัด")
        XCTAssertEqual(PlanLayout.shortName("ร้านกาแฟบ้านสวน"), "ร้านกาแฟบ้านสวน")
    }
}

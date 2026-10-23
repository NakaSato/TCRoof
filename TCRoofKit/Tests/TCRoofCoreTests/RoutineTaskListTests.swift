import XCTest
@testable import TCRoofCore

/// docs/ui/daily-report-ipad-v2: the task list's 10-segment bar, its ± 5 % steps, the groups by location, and
/// `Problem.lineKey` decoding old reports.
final class RoutineTaskListTests: XCTestCase {
    typealias R = RoutineReport

    func testSegmentTap() {
        // 30 % done before today: segments 1–3 are done, so ignored
        XCTAssertNil(R.todayFromSegment(1, before: 30))
        XCTAssertNil(R.todayFromSegment(3, before: 30))
        XCTAssertEqual(R.todayFromSegment(4, before: 30)!, 10, accuracy: 1e-9)
        XCTAssertEqual(R.todayFromSegment(10, before: 30)!, 70, accuracy: 1e-9)
        // part of a segment done: up to its end
        XCTAssertEqual(R.todayFromSegment(4, before: 35)!, 5, accuracy: 1e-9)
        // out of range is clamped to the bar, and nothing is left past 100
        XCTAssertEqual(R.todayFromSegment(12, before: 95)!, 5, accuracy: 1e-9)
        XCTAssertNil(R.todayFromSegment(10, before: 100))
    }

    func testPlusMinusFive() {
        XCTAssertEqual(R.stepToday(0, before: 40, by: -5), 0)
        XCTAssertEqual(R.stepToday(0, before: 40, by: 5), 5)
        XCTAssertEqual(R.stepToday(60, before: 40, by: 5), 60)    // at the cap
        XCTAssertEqual(R.stepToday(58, before: 40, by: 5), 60)    // capped at what is left
        XCTAssertEqual(R.stepToday(3, before: 40, by: -5), 0)
        XCTAssertEqual(R.stepToday(0, before: 100, by: 5), 0)
    }

    func testLocationGroups() {
        let lines = [("หลังคา 10", 1), ("ห้องอินเวอร์เตอร์", 2), ("หลังคา 2", 3), ("", 4), ("หลังคา 2", 5), ("หลังคา 1", 6)]
            .map { R.ProgressLine(task: nil, description: "\($0.1)", location: $0.0) }
        let g = R.locationGroups(lines)
        XCTAssertEqual(g.map(\.location), ["หลังคา 1", "หลังคา 2", "หลังคา 10", "ห้องอินเวอร์เตอร์", ""])
        XCTAssertEqual(g[1].lines.map(\.description), ["3", "5"])
    }

    func testProblemLineKeyDecodesOldReports() throws {
        let old = #"{"id":"9C2B8C0A-6C42-4C34-9F5E-2B9B5F0A1C11","description":"ฝนตก","solution":"","closed":false,"since":0}"#
        let p = try JSONDecoder().decode(R.Problem.self, from: Data(old.utf8))
        XCTAssertNil(p.lineKey)
        XCTAssertEqual(p.description, "ฝนตก")
        var keyed = p; keyed.lineKey = "panels|-|หลังคา 1"
        let back = try JSONDecoder().decode(R.Problem.self, from: JSONEncoder().encode(keyed))
        XCTAssertEqual(back.lineKey, "panels|-|หลังคา 1")
    }
}

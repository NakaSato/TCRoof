import XCTest
@testable import TCRoofCore

/// `RoutineReport.WeeklySent`: the iPad page's record of a Weekly Report sent.
final class WeeklySentTests: XCTestCase {
    func testDecodesWhatIsThereAndKeepsOnePerWeek() throws {
        let partial = try JSONDecoder().decode(RoutineReport.WeeklySent.self, from: Data(#"{"sentBy":"a@tcroof.test"}"#.utf8))
        XCTAssertEqual(partial.sentBy, "a@tcroof.test")
        XCTAssertEqual(partial.recipients, [])
        XCTAssertEqual(partial.weekStart, .distantPast)

        let cal = RoutineReport.calendar
        let w1 = cal.date(from: DateComponents(year: 2026, month: 9, day: 27))!, w0 = cal.date(byAdding: .day, value: -7, to: w1)!
        let a = RoutineReport.WeeklySent(weekStart: w1, sentAt: w1, sentBy: "a", recipients: ["ทีมภายใน"])
        let b = RoutineReport.WeeklySent(weekStart: w0, sentAt: w0, sentBy: "b", recipients: [])
        var list = RoutineReport.WeeklySent.recording(a, in: [])
        list = RoutineReport.WeeklySent.recording(b, in: list)
        XCTAssertEqual(list.map(\.sentBy), ["b", "a"], "oldest week first")
        let again = RoutineReport.WeeklySent(weekStart: cal.date(byAdding: .hour, value: 5, to: w1)!, sentAt: w1, sentBy: "c", recipients: [])
        XCTAssertEqual(RoutineReport.WeeklySent.recording(again, in: list).map(\.sentBy), ["b", "c"], "the week's earlier send replaced")
        let round = try JSONDecoder().decode([RoutineReport.WeeklySent].self, from: JSONEncoder().encode(list))
        XCTAssertEqual(round, list)
    }
}

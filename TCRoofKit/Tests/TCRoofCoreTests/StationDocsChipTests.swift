import XCTest
@testable import TCRoofCore

/// The install tracking page's package chip and paper colour (docs/ui/install-tracking-ipad-overview §2–§4).
final class StationDocsChipTests: XCTestCase {
    typealias S = StationDocs
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Bangkok")!; return c }()
    var today: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 15))! }
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    func testCompleteIsDoneAndNotNeededCountsAsNeither() {
        let c = S.packageChip([.approved, .signed, .notNeeded], due: day(-3), today: today, calendar: cal)
        XCTAssertEqual(c, .init(text: "ครบ 2/2", level: .done, awaitingApproval: false))
    }

    func testAllHandedInWithOneSubmittedWaits() {
        let c = S.packageChip([.approved, .submitted, .approved], due: nil, today: today, calendar: cal)
        XCTAssertEqual(c, .init(text: "ครบ 3/3", level: .waiting, awaitingApproval: true))
        // a signed paper not handed in yet is still the team's: done, not waiting
        XCTAssertEqual(S.packageChip([.submitted, .signed], due: nil, today: today, calendar: cal).level, .done)
    }

    func testOpenChipCountsPapersAndReadsTheDueDate() {
        let papers: [S.Status] = [.approved, .missing, .draft, .requested]
        XCTAssertEqual(S.packageChip(papers, due: day(7), today: today, calendar: cal), .init(text: "1/4 ฉบับ", level: .dueSoon, awaitingApproval: false))
        XCTAssertEqual(S.packageChip(papers, due: day(0), today: today, calendar: cal).level, .dueSoon)
        XCTAssertEqual(S.packageChip(papers, due: day(8), today: today, calendar: cal).level, .open)
        XCTAssertEqual(S.packageChip(papers, due: day(-1), today: today, calendar: cal).level, .late)
        XCTAssertEqual(S.packageChip(papers, due: nil, today: today, calendar: cal).level, .open)
    }

    func testPaperLevels() {
        XCTAssertEqual(S.level(.submitted), .waiting)
        XCTAssertEqual(S.level(.requested), .waiting)
        XCTAssertEqual(S.level(.draft), .working)
        XCTAssertEqual(S.level(.approved), .done)
        XCTAssertEqual(S.level(.missing), .open)
        XCTAssertEqual(S.level(.notNeeded), .none)
    }
}

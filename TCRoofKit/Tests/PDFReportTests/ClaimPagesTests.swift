import XCTest
@testable import PDFReport
@testable import TCRoofCore

/// The monthly claim's pages (docs/specs/calendar-travel-expenses-swift.md §B5): totals as on the screen, receipts
/// numbered in table order and printed two per page.
final class ClaimPagesTests: XCTestCase {
    private let cal = TravelClaim.calendar
    private func d(_ day: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h))! }

    private func texts(_ p: [ReportLayout.Page]) -> [String] {
        p.flatMap(\.ops).compactMap {
            switch $0 {
            case let .text(t, _, _, _, _, _, _), let .textBox(t, _, _, _, _, _): t
            default: nil
            }
        }
    }

    /// A month of three trips and five receipts.
    static func month(_ d: (Int, Int) -> Date) -> TravelClaim.Summary {
        let days = (1...3).map { i in
            TravelClaim.Day(id: "t\(i)", date: d(i, 8), vehicle: .personal, plate: "1กข 1234",
                            stops: [TravelClaim.Stop(jobID: "A", label: "TC-1", arrivedAt: d(i, 9), departedAt: d(i, 11), legKm: 40),
                                    TravelClaim.Stop(jobID: "B", label: "TC-2", arrivedAt: d(i, 13), departedAt: d(i, 15), legKm: 20)],
                            backKm: 50, rate: 5)
        }
        let items = [
            TravelClaim.Item(id: "e1", date: d(1, 10), category: .fuel, amount: 100_000, vendor: "PTT", hasReceipt: true),
            TravelClaim.Item(id: "e2", date: d(1, 12), category: .toll, amount: 5_000, vendor: "ทางพิเศษ", jobID: "A", hasReceipt: true),
            TravelClaim.Item(id: "e3", date: d(2, 12), category: .parking, amount: 4_000, jobID: "B", hasReceipt: true),
            TravelClaim.Item(id: "e4", date: d(3, 19), category: .lodging, amount: 85_000, vendor: "โรงแรม", jobID: "B", hasReceipt: true),
            TravelClaim.Item(id: "e5", date: d(3, 20), category: .other, amount: 1_550, note: "ถ่ายเอกสาร", hasReceipt: true),
        ]
        return TravelClaim.Summary(days: days, items: items)
    }

    func testTotalsMatchTheSummaryAndEveryReceiptIsPrinted() {
        let s = Self.month(d)
        // 3 × 110 km × 5 baht = 1,650 baht mileage
        XCTAssertEqual(s.mileage, 165_000)
        XCTAssertEqual(s.total, 165_000 + 195_550)
        let receipts = Dictionary(uniqueKeysWithValues: s.items.map { ($0.id, Photo(fileName: "\($0.id).jpg", width: 3, height: 4)) })
        let claim = ClaimPages(header: .init(company: "TCRoof", person: "สมชาย ใจดี", email: "s@x.co", month: d(1), submittedAt: d(31)),
                               summary: s, jobNames: ["A": "TC-1 สถานีหนึ่ง", "B": "TC-2 สถานีสอง"], receipts: receipts)
        let pages = claim.pages()
        let t = texts(pages)
        XCTAssertTrue(t.contains(TravelClaim.baht(s.total)), "grand total")
        XCTAssertTrue(t.contains(TravelClaim.baht(s.mileage)))
        XCTAssertTrue(t.contains("330.0"), "month km")
        XCTAssertTrue(t.contains("#5"))
        XCTAssertTrue(t.contains("สมชาย ใจดี"))
        // the per-job lines add up to the grand total
        XCTAssertEqual(s.byJob.reduce(0) { $0 + $1.amount }, s.total)
        // five receipts, two per page: three appendix pages, each picture once
        let photos = pages.flatMap(\.ops).filter { if case .photo = $0 { true } else { false } }
        XCTAssertEqual(photos.count, 5)
        XCTAssertEqual(pages.filter { p in p.ops.contains { if case .photo = $0 { true } else { false } } }.count, 3)
        XCTAssertEqual(claim.receiptNumbers["e4"], 4)
        // one page count across the claim and its appendix
        XCTAssertTrue(t.contains("หน้า \(pages.count)/\(pages.count)"))
        XCTAssertEqual(t.filter { $0.hasPrefix("หน้า 1/") }.count, 1)
        XCTAssertTrue(t.contains("ไม่ระบุงาน"))
    }

    func testEmptyMonth() {
        let claim = ClaimPages(header: .init(company: "TCRoof", person: "", email: "", month: d(1)),
                               summary: TravelClaim.Summary(days: [], items: []), jobNames: [:])
        let pages = claim.pages()
        XCTAssertEqual(pages.count, 1)
        XCTAssertTrue(texts(pages).contains("ไม่มีการเดินทางในเดือนนี้"))
    }
}

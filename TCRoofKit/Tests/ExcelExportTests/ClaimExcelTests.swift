import XCTest
@testable import ExcelExport
@testable import TCRoofCore

final class ClaimExcelTests: XCTestCase {
    func testClaimWorkbookHoldsTheScreenTotals() throws {
        let cal = TravelClaim.calendar
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
        let s = TravelClaim.Summary(
            days: [TravelClaim.Day(id: "t", date: day, vehicle: .personal, stops: [TravelClaim.Stop(jobID: "A", label: "TC-1", legKm: 30)],
                                   backKm: 30, rate: 5)],
            items: [TravelClaim.Item(id: "e", date: day, category: .toll, amount: 4_500, vendor: "ทางพิเศษ & ด่าน", jobID: "A")])
        let data = try ClaimExcel.export(company: "TCRoof", person: "ผู้เบิก", email: "a@b.co", month: day, submittedAt: nil,
                                         summary: s, jobNames: ["A": "TC-1 สถานี"], receiptNumbers: ["e": 1])
        if let dir = ProcessInfo.processInfo.environment["EXPORT_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("claim.xlsx"))
        }
        let sheet = try XCTUnwrap(ZipArchive(data).string("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(sheet.contains("<v>300.0</v>"), "mileage 60 km × 5")
        XCTAssertTrue(sheet.contains("<v>345.0</v>"), "grand total")
        XCTAssertTrue(sheet.contains("ทางพิเศษ &amp; ด่าน"))
        XCTAssertTrue(sheet.contains(">#1<"))
    }
}

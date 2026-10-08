import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// R2 as a clean one-sheet workbook (docs/specs/routine-reports-swift.md §4.6).
final class DailyReportExcelTests: XCTestCase {
    private func d(_ day: Int) -> Date { RoutineReport.calendar.date(from: DateComponents(year: 2025, month: 7, day: day))! }

    func testDailyWorkbook() throws {
        var y = RoutineReport.Daily(date: d(1))
        y.progress = [.init(task: .inverter, description: "", location: "ห้องอินเวอร์เตอร์", percent: 10)]
        var r = RoutineReport.Daily(date: d(2))
        r.crew = [.init(name: "ผู้ปฏิบัติงาน", count: 7), .init(name: "ช่างไฟฟ้า", count: 0)]
        r.weather[0] = .rain
        r.progress = [.init(task: .inverter, description: "", location: "ห้องอินเวอร์เตอร์", percent: 40)]
        r.problems = [.init(description: "ไฟดับ & <ฝน>", since: d(2))]
        let h = DailyReportExcel.Header(project: "โครงการ", station: "โชคชัย", employer: "กฟภ.", contractor: "TCR",
                                        engineer: "วิศวกร", inspector: "ผู้ตรวจ", engineerSignedAt: d(2), inspectorAckAt: nil)
        let data = try DailyReportExcel.export(r, all: [y, r], header: h)
        if let dir = ProcessInfo.processInfo.environment["EXPORT_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("daily.xlsx"))
        }
        let zip = try ZipArchive(data)
        XCTAssertEqual(zip.string("xl/workbook.xml")?.components(separatedBy: "<sheet ").count, 2)   // one sheet only
        let sheet = try XCTUnwrap(zip.string("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(sheet.contains(">โชคชัย<"))
        XCTAssertTrue(sheet.contains(">R<"))
        XCTAssertTrue(sheet.contains("<v>0.3</v>"))        // วันนี้ +30 %
        XCTAssertTrue(sheet.contains("<v>0.4</v>"))        // สะสม 40 %
        XCTAssertTrue(sheet.contains("ไฟดับ &amp; &lt;ฝน&gt;"))
        XCTAssertFalse(sheet.contains("ช่างไฟฟ้า"))         // zero counts left out
        XCTAssertTrue(sheet.contains("<mergeCells"))
        XCTAssertNotNil(zip.string("xl/styles.xml"))
        XCTAssertNotNil(zip.string("[Content_Types].xml"))
    }
}

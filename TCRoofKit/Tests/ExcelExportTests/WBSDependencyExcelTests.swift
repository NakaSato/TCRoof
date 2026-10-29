import XCTest
@testable import ExcelExport
@testable import TCRoofCore

final class WBSDependencyExcelTests: XCTestCase {
    func testDependenciesRoundTripClearAndDoNotRewriteWorksheetProse() throws {
        let url = try XCTUnwrap(MPTemplates.cases().first { $0.id == "P3-001" }).url
        let original = try Data(contentsOf: url)
        let imported = try MPWorkbook.read(original)
        var rows = imported.wbs
        let index = try XCTUnwrap(rows.firstIndex { $0.code == "2.2.1" })
        let links = [MasterSchedule.WBSDependency(predecessor: "2.1.1", lagDays: 2)]
        rows[index].dependencies = links
        let forecast = WBSDependencies.schedule(rows, settings: RoutineReport.Settings())
        XCTAssertTrue(forecast.isValid, forecast.issues.map(\.message).joined(separator: "\n"))
        XCTAssertNotNil(forecast.forecasts[rows[index].code])
        let exported = try MPWorkbook.export(original, input: imported.input, actual: imported.actual, wbs: rows)
        let back = try MPWorkbook.read(exported.data)
        let row = try XCTUnwrap(back.wbs.first { $0.code == "2.2.1" })
        XCTAssertEqual(row.dependencies, links)
        XCTAssertEqual(row.predecessor, imported.wbs[index].predecessor)
        XCTAssertEqual(row.baselineStart, imported.wbs[index].baselineStart)
        XCTAssertEqual(row.baselineEnd, imported.wbs[index].baselineEnd)
        XCTAssertEqual(exported.changedCells, 0, "Only custom XML metadata changes")
        let same = try MPWorkbook.export(exported.data, input: back.input, actual: back.actual, wbs: back.wbs)
        XCTAssertEqual(same.data, exported.data)
        let cleared = try MPWorkbook.export(exported.data, input: back.input, actual: back.actual, wbs: imported.wbs)
        XCTAssertNil(try MPWorkbook.read(cleared.data).wbs.first { $0.code == "2.2.1" }?.dependencies)
    }

    func testUnconfiguredWorkbookStaysByteForByteUnchanged() throws {
        let url = try XCTUnwrap(MPTemplates.cases().first { $0.id == "P3-001" }).url
        let original = try Data(contentsOf: url)
        let imported = try MPWorkbook.read(original)
        let exported = try MPWorkbook.export(original, input: imported.input, actual: imported.actual, wbs: imported.wbs)
        XCTAssertEqual(exported.data, original)
    }
}

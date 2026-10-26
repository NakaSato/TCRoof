import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The job's WBS ticks in a template file's `แผนโครงการ` sheet (docs/specs/project-plan-wbs.md, step 3): export writes
/// `เสร็จ (Y)` and its `เสร็จ` date per row, as the full workbook's update sheet would, and a later import takes back
/// only what was changed in Excel since.
final class WBSTicksExcelTests: XCTestCase {
    let cal = MasterSchedule.calendar
    func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: d))! }

    /// P3-001's file with its rows unticked: the station files carry their progress (`Y` on 15 rows).
    func template() throws -> Data {
        let real = try Data(contentsOf: XCTUnwrap(MPTemplates.cases().first { $0.id == "P3-001" }).url)
        let file = try MPWorkbook.read(real)
        return try MPWorkbook.export(real, input: file.input, actual: file.actual, ticks: [:]).data
    }

    func testAStationFileCarriesItsTicks() throws {
        let real = try Data(contentsOf: XCTUnwrap(MPTemplates.cases().first { $0.id == "P3-001" }).url)
        let file = try MPWorkbook.read(real)
        XCTAssertTrue(file.wbsDone.contains("1.1"), "Kick Off is done")
        XCTAssertEqual(file.wbsDone.count, 15)
    }

    func testTicksGoIntoTheSheetAndComeBack() throws {
        let original = try template()
        let file = try MPWorkbook.read(original)
        XCTAssertEqual(file.wbsDone, [])
        XCTAssertEqual(file.wbsBase ?? [], [], "nothing ticked at the clearing export")

        // the Inverter station table's rows have no เสร็จ cells: 2.5.1.2's tick stays in the app, out of the record
        let ticks = ["2.1.1": MasterSchedule.WBSTick(by: "a@tcroof.test", at: day(7)),
                     "2.2.3": MasterSchedule.WBSTick(by: "b@tcroof.test", at: day(9)),
                     "2.5.1.2": MasterSchedule.WBSTick(by: "b@tcroof.test", at: day(9))]
        let out = try MPWorkbook.export(original, input: file.input, actual: file.actual, ticks: ticks)
        XCTAssertEqual(out.changedCells, 4, "a Y and a date per row")
        let back = try MPWorkbook.read(out.data)
        XCTAssertEqual(back.wbsDone, ["2.1.1", "2.2.3"])
        XCTAssertEqual(back.wbsDoneDates, ["2.1.1": day(7), "2.2.3": day(9)])
        XCTAssertEqual(back.wbsBase, ["2.1.1", "2.2.3"])
        XCTAssertEqual(back.input, file.input, "the plan is as it was")
        XCTAssertEqual(back.wbs.count, file.wbs.count)

        // untick one in the app and export the exported file: its Y and date are cleared
        let again = try MPWorkbook.export(out.data, input: file.input, actual: file.actual, ticks: ["2.2.3": ticks["2.2.3"]!])
        let cleared = try MPWorkbook.read(again.data)
        XCTAssertEqual(cleared.wbsDone, ["2.2.3"])
        XCTAssertEqual(cleared.wbsBase, ["2.2.3"])
        XCTAssertNil(cleared.wbsDoneDates["2.1.1"])
    }

    func testNoTicksLeaveTheFileAsItWas() throws {
        let original = try template()
        let file = try MPWorkbook.read(original)
        let out = try MPWorkbook.export(original, input: file.input, actual: file.actual, ticks: [:])
        XCTAssertEqual(out.data, original)
        XCTAssertEqual(out.changedCells, 0)
    }

    /// A row ticked in Excel after the export (Y and a date typed in) comes in; the rest of the job's ticks stay.
    func testATickTypedInExcelComesIn() throws {
        let original = try template()
        let file = try MPWorkbook.read(original)
        let mine = ["2.1.1": MasterSchedule.WBSTick(by: "a@tcroof.test", at: day(7))]
        let exported = try MPWorkbook.export(original, input: file.input, actual: file.actual, ticks: mine).data

        // in Excel: Y and 12 Dec on 2.2.1
        let book = try MPWorkbook.Book(exported)
        var sheet = try XCTUnwrap(book.detail)
        let h = try XCTUnwrap(MPWorkbook.wbsHeader(sheet))
        let row = try XCTUnwrap(MPWorkbook.codeRows(sheet, h).first { $0.code == "2.2.1" }).row
        sheet.cells.set(MPWorkbook.Sheet.ref(try XCTUnwrap(h.doneMark), row), .inline("Y"))
        sheet.cells.set(MPWorkbook.Sheet.ref(try XCTUnwrap(h.doneDate), row), .number(MPWorkbook.Sheet.serial(day(12), cal)))
        var zip = book.zip
        zip.set(try XCTUnwrap(book.detailPath), sheet.cells.xml)
        let edited = try MPWorkbook.read(zip.write())

        XCTAssertEqual(edited.wbsDone, ["2.1.1", "2.2.1"])
        XCTAssertEqual(edited.wbsBase, ["2.1.1"])
        // the app ticked 2.3.1 after exporting
        var local = mine
        local["2.3.1"] = .init(by: "a@tcroof.test", at: day(10))
        let merged = MasterSchedule.mergingTicks(local, fileDone: edited.wbsDone, dates: edited.wbsDoneDates,
                                                 base: edited.wbsBase, by: "pm@tcroof.test", today: day(20))
        XCTAssertEqual(Set(merged.ticks.keys), ["2.1.1", "2.2.1", "2.3.1"])
        XCTAssertEqual(merged.ticks["2.2.1"]?.at, day(12))
        XCTAssertEqual(merged.changed, 1)
    }
}

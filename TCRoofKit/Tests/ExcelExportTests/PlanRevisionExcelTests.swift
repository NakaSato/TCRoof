import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The plan file's baseline box (CHA-79): a plan re-planned in the app writes its current REV, approver and day there.
final class PlanRevisionExcelTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func file() throws -> Data {
        try Data(contentsOf: ProjectPlanTemplateTests.folder.appendingPathComponent("P3-001 แผนโครงการ (นำเข้า TCRoof).xlsx"))
    }

    func box(_ data: Data) throws -> (summary: String?, number: String?, approver: String?, date: Double?) {
        let sheet = try XCTUnwrap(try MPWorkbook.Book(data).detail)
        let c = MPWorkbook.revisionCells(sheet)
        func text(_ at: (col: Int, row: Int)?) -> String? { at.flatMap { sheet.text($0.col, $0.row) } }
        return (text(c.summary), text(c.number), text(c.approver), c.date.flatMap { sheet.number($0.col, $0.row) })
    }

    func testTheBoxIsFoundByItsLabels() throws {
        let sheet = try XCTUnwrap(try MPWorkbook.Book(try file()).detail)
        let c = MPWorkbook.revisionCells(sheet)
        XCTAssertEqual(c.summary.map { MPWorkbook.Sheet.ref($0.col, $0.row) }, "AA4")
        XCTAssertEqual(c.number.map { MPWorkbook.Sheet.ref($0.col, $0.row) }, "AB5")
        XCTAssertEqual(c.approver.map { MPWorkbook.Sheet.ref($0.col, $0.row) }, "AG5")
        XCTAssertEqual(c.date.map { MPWorkbook.Sheet.ref($0.col, $0.row) }, "AL5")
    }

    func testAReplannedPlanWritesItsRevision() throws {
        let original = try file()
        let r = try MPWorkbook.read(original)
        let at = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15)))
        let task = try XCTUnwrap(MasterSchedule.plan(r.input).first { $0.task == .panels && $0.start != nil })
        let action = Assistant.PendingAction(
            id: "p", jobID: "j", station: "s",
            change: .replan(tasks: [.init(task: .panels, start: ScheduleBrief.day(task.start!, calendar: cal),
                                          end: ScheduleBrief.day(cal.date(byAdding: .day, value: 10, to: task.end!)!, calendar: cal))],
                            reason: "แผงมาช้า"),
            title: "", before: "", after: "", changeRequest: "CR-014")
        let input = try XCTUnwrap(action.revised(r.input, by: "pm@tc.co", at: at))

        let out = try MPWorkbook.export(original, input: input, actual: r.actual, revisionApprover: "สมชาย")
        let b = try box(out.data)
        XCTAssertEqual(b.number, "REV 01 (CR-014)")
        XCTAssertEqual(b.approver, "สมชาย")
        XCTAssertEqual(b.date, MPWorkbook.Sheet.serial(cal.startOfDay(for: at), cal))
        XCTAssertEqual(b.summary, "REV 01, อนุมัติแล้ว")

        // without a name, the approver's email; written again, the box stays
        let plain = try box(MPWorkbook.export(original, input: input, actual: r.actual).data)
        XCTAssertEqual(plain.approver, "pm@tc.co")
        let again = try box(MPWorkbook.export(out.data, input: input, actual: r.actual, revisionApprover: "สมชาย").data)
        XCTAssertEqual(again.number, b.number)
        XCTAssertEqual(again.date, b.date)

        // a plan never re-planned in the app leaves the file's own box
        XCTAssertEqual(try box(MPWorkbook.export(original, input: r.input, actual: r.actual).data).number, "REV 00 (จากกำหนดรอบ)")
    }
}

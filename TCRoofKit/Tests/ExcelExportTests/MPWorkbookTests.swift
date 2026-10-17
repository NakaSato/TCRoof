import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// `MPWorkbook` on a station's own plan file: `37. Master Plan Weekly PWA สถานีผลิตน้ำประปาบางไทร …xlsx`.
final class MPWorkbookTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func original() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mp-weekly-bangsai.xlsx"))
    }

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    func testReadsThePlan() throws {
        let r = try MPWorkbook.read(original())
        XCTAssertEqual(r.tasks.count, 18)
        XCTAssertEqual(Set(r.tasks), Set(MasterSchedule.Task.allCases))
        XCTAssertTrue(r.project?.contains("สถานีผลิตน้ำประปาบางไทร") == true)
        XCTAssertEqual(r.owner, "การประปาส่วนภูมิภาคสาขาพระนครศรีอยุธยา")

        let plan = Dictionary(uniqueKeysWithValues: MasterSchedule.plan(r.input).map { ($0.task, $0) })
        // the file's own weights: Permit 15, ติดตั้ง 75, ทดสอบ 10
        XCTAssertEqual(plan.values.reduce(0) { $0 + $1.weight }, 100, accuracy: 1e-9)
        XCTAssertEqual(plan[.kickoff]?.weight, 2)
        XCTAssertEqual(plan[.structure]?.weight, 10)
        XCTAssertEqual(plan[.fireSwitch]?.weight, 7.5)
        XCTAssertEqual(plan[.cop]?.weight, 0)
        XCTAssertEqual(r.input.weight(.preCommissioning), 5)
        XCTAssertTrue(r.input.over200kVA, "พค.2 has weight")

        // cached dates, formulas or not: 2.1 23 ต.ค. – 16 พ.ย. 2567, 1.3 = 2.1's start, 1.5 from its end
        XCTAssertEqual(plan[.structure]?.start, day(2024, 10, 23))
        XCTAssertEqual(plan[.structure]?.end, day(2024, 11, 16))
        XCTAssertEqual(plan[.siteHandover]?.start, day(2024, 10, 23))
        XCTAssertEqual(plan[.pk2]?.start, day(2024, 9, 11))
        XCTAssertEqual(plan[.pk2]?.end, day(2024, 10, 1))
        XCTAssertNil(plan[.cop]?.start)
        XCTAssertEqual(r.input.installStart, day(2024, 10, 23))
        XCTAssertEqual(r.input.installEnd, day(2024, 12, 22))

        XCTAssertTrue(r.actual.points.isEmpty)
        // week columns from 1 ม.ค. 2567 (its Sunday week) to 28 ธ.ค. 2568
        XCTAssertEqual(r.weeks?.lowerBound, day(2023, 12, 31))
        XCTAssertEqual(r.weeks?.upperBound, day(2025, 12, 28))
    }

    func testUnchangedPlanGivesTheSameBytes() throws {
        let data = try original()
        let r = try MPWorkbook.read(data)
        let out = try MPWorkbook.export(data, input: r.input, actual: r.actual)
        XCTAssertEqual(out.changedCells, 0)
        XCTAssertEqual(out.data, data)
    }

    func testActualIsWrittenInPlace() throws {
        let data = try original()
        let r = try MPWorkbook.read(data)
        var a = r.actual
        a.set(4, task: .structure, week: day(2024, 10, 27), weight: 10)
        a.set(2.5, task: .structure, week: day(2024, 11, 3), weight: 10)
        a.set(2, task: .kickoff, week: day(2024, 6, 20), weight: 2)
        a.started[MasterSchedule.Task.structure.rawValue] = day(2024, 10, 25)
        a.finished[MasterSchedule.Task.kickoff.rawValue] = day(2024, 6, 20)
        let out = try MPWorkbook.export(data, input: r.input, actual: a)
        XCTAssertEqual(out.changedCells, 5)
        XCTAssertTrue(out.weeksOutside.isEmpty)

        // read back the same
        let back = try MPWorkbook.read(out.data)
        XCTAssertEqual(back.actual, a)
        XCTAssertEqual(MasterSchedule.plan(back.input), MasterSchedule.plan(r.input))

        // only the sheet's input cells and the recalc flag changed; every other part is the original's
        let before = try ZipArchive(data), after = try ZipArchive(out.data)
        XCTAssertEqual(before.paths, after.paths)
        for p in before.paths where p != "xl/worksheets/sheet1.xml" && p != "xl/workbook.xml" {
            XCTAssertEqual(before.data(p), after.data(p), p)
        }
        XCTAssertEqual(after.string("xl/workbook.xml"),
                       before.string("xl/workbook.xml")?.replacingOccurrences(of: #"<calcPr calcId="191029"/>"#,
                                                                              with: #"<calcPr calcId="191029" fullCalcOnLoad="1"/>"#))
        let sheetBefore = before.string("xl/worksheets/sheet1.xml")!, sheetAfter = after.string("xl/worksheets/sheet1.xml")!
        XCTAssertTrue(sheetBefore.contains(#"<c r="BC30" s="36"/>"#))
        XCTAssertTrue(sheetAfter.contains(#"<c r="BC30" s="36"><v>4</v></c>"#), "2.1 Actual, week of 27 ต.ค. 2567 (BC8)")
        XCTAssertTrue(sheetAfter.contains(#"<c r="BD30" s="36"><v>2.5</v></c>"#))
        XCTAssertTrue(sheetAfter.contains(#"<c r="AJ14" s="57"><v>2</v></c>"#), "1.1 Actual, week of 16 มิ.ย. 2567 (AJ8)")
        XCTAssertTrue(sheetAfter.contains(#"<c r="G30" s="57"><v>45590</v></c>"#), "actual start 25 ต.ค. 2567")
        XCTAssertTrue(sheetAfter.contains(#"<c r="H14" s="150"><v>45463</v></c>"#))
        XCTAssertEqual(sheetAfter.count - sheetBefore.count, [#"<v>4</v></c>"#, #"<v>2.5</v></c>"#, #"<v>2</v></c>"#,
                                                               #"<v>45590</v></c>"#, #"<v>45463</v></c>"#].reduce(0) { $0 + $1.count - 1 })

        // clearing the points again gives back the original sheet
        let cleared = try MPWorkbook.export(out.data, input: r.input, actual: r.actual)
        XCTAssertEqual(try ZipArchive(cleared.data).string("xl/worksheets/sheet1.xml"), sheetBefore)
    }

    func testChangedPlanFreezesTheDates() throws {
        let data = try original()
        let r = try MPWorkbook.read(data)
        var input = r.input
        input.fixed?[MasterSchedule.Task.panels.rawValue] = .init(start: day(2024, 11, 20), end: day(2024, 12, 1), weight: 10)
        let out = try MPWorkbook.export(data, input: input, actual: r.actual)
        XCTAssertGreaterThan(out.changedCells, 0)

        let back = try MPWorkbook.read(out.data)
        XCTAssertEqual(MasterSchedule.plan(back.input), MasterSchedule.plan(input))
        let zip = try ZipArchive(out.data), sheet = zip.string("xl/worksheets/sheet1.xml")!
        XCTAssertTrue(sheet.contains(#"<c r="G33" s="57"><v>45616</v></c>"#), "2.3 starts 20 พ.ย. 2567, a value now")
        // 1.3's start was a formula on 2.1's; it is a value now, so it can't move when Excel recalculates
        XCTAssertFalse(sheet.contains("<f>G29</f>"))
        XCTAssertFalse(zip.contains("xl/calcChain.xml"))
        XCTAssertFalse(zip.string("[Content_Types].xml")!.contains("calcChain"))
        XCTAssertFalse(zip.string("xl/_rels/workbook.xml.rels")!.contains("calcChain"))
        // the weekly plan stays formulas
        XCTAssertTrue(sheet.contains(#"IF(L$10&gt;$K13,"0",IF(L$10&lt;$J13,"0",$E13/($K13-$J13+1)))"#))
    }

    func testAPlanMadeInTheAppIsWrittenOver() throws {
        let data = try original()
        var input = try MPWorkbook.read(data).input
        input.fixed = nil   // ตั้งค่าแผน › คำนวณตามสูตร
        let out = try MPWorkbook.export(data, input: input, actual: .init())
        let back = try MPWorkbook.read(out.data)
        let a = MasterSchedule.plan(input), b = MasterSchedule.plan(back.input)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.weight, y.weight, x.task.code)
            XCTAssertEqual(x.start, y.start, x.task.code)
            XCTAssertEqual(x.end, y.end, x.task.code)
        }
    }

    func testWeeksOutsideTheFileAreReported() throws {
        let data = try original()
        let r = try MPWorkbook.read(data)
        var a = r.actual
        a.set(1, task: .training, week: day(2026, 3, 1), weight: 5)
        let out = try MPWorkbook.export(data, input: r.input, actual: a)
        XCTAssertEqual(out.weeksOutside, ["2026-03-01"])
        XCTAssertEqual(out.changedCells, 0)
    }

    func testNotAPlan() {
        XCTAssertThrowsError(try MPWorkbook.read(Data("hello".utf8))) { XCTAssertEqual($0 as? MPWorkbook.Failure, .notWorkbook) }
    }

    func testImportedWeightsCapProgress() throws {
        let input = try MPWorkbook.read(original()).input
        var a = MasterSchedule.Actual()
        a.setPercent(100, task: .structure, week: day(2024, 11, 3), weight: input.weight(.structure))
        XCTAssertEqual(a.points(.structure, week: day(2024, 11, 3)), 10)
        a.setPercent(100, task: .cop, week: day(2024, 11, 3), weight: input.weight(.cop))
        XCTAssertEqual(a.points(.cop, week: day(2024, 11, 3)), 0)
    }
}

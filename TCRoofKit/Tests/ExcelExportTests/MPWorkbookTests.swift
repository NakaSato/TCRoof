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

    /// Every formula of the untouched file works out to the result Excel saved in it.
    func testFormulasMatchExcelsResults() throws {
        let book = try MPWorkbook.Book(original())
        var f = book.sheet.formulas(cal)
        var checked = 0, unknown: [String] = [], wrong: [String] = []
        for p in f.formulas.keys.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
            let ref = MPWorkbook.Sheet.ref(p.col, p.row)
            let v = f.value(p), saved = book.sheet.cell(ref)!.cached
            if v == .unknown { unknown.append(ref); continue }
            checked += 1
            if !MPWorkbook.Sheet.same(saved, v) { wrong.append("\(ref) \(saved) ≠ \(v)") }
        }
        XCTAssertEqual(wrong, [], "\(wrong.count) of \(checked)")
        XCTAssertEqual(unknown, [])
        XCTAssertGreaterThan(checked, 3000)
    }

    /// Booked progress moves the Part sums, the cumulative actual (row 56) and the S-curve chart's saved series.
    func testExportWorksOutTheResults() throws {
        let data = try original()
        let r = try MPWorkbook.read(data)
        var a = r.actual
        a.set(4, task: .structure, week: day(2024, 10, 27), weight: 10)       // BC30
        a.set(2.5, task: .structure, week: day(2024, 11, 3), weight: 10)      // BD30
        let out = try MPWorkbook.export(data, input: r.input, actual: a)
        let zip = try ZipArchive(out.data), sheet = zip.string("xl/worksheets/sheet1.xml")!
        let cells = MPWorkbook.Sheet(sheet, shared: [])
        XCTAssertEqual(cells.number(MPWorkbook.Sheet.split("BC28")!.0, 28), 4, "Part ติดตั้ง Actual")
        XCTAssertEqual(cells.number(MPWorkbook.Sheet.split("BC55")!.0, 55), 4)
        XCTAssertEqual(cells.number(MPWorkbook.Sheet.split("BC56")!.0, 56), 4, "cumulative actual")
        XCTAssertEqual(cells.number(MPWorkbook.Sheet.split("BD56")!.0, 56), 6.5)
        XCTAssertEqual(cells.number(MPWorkbook.Sheet.split("DL56")!.0, 56), 6.5)
        XCTAssertEqual(cells.number(MPWorkbook.Sheet.split("BC54")!.0, 54), 19, "the plan's cumulative stays")
        // the chart's actual series (AD56:DL56): BC is point 25
        let chart = zip.string("xl/charts/chart1.xml")!
        XCTAssertTrue(chart.contains(#"<c:pt idx="25"><c:v>4</c:v></c:pt><c:pt idx="26"><c:v>6.5</c:v></c:pt>"#))
        XCTAssertTrue(chart.contains(#"<c:ptCount val="87"/>"#))
        // and the untouched parts of the original stay
        let before = try ZipArchive(data)
        XCTAssertEqual(zip.data("xl/charts/chart2.xml"), before.data("xl/charts/chart2.xml"))
        XCTAssertEqual(zip.data("xl/styles.xml"), before.data("xl/styles.xml"))
    }

    /// The fixture's formulas all work out as Excel saved them.
    func testImportChecksTheFormulas() throws {
        let check = try MPWorkbook.read(original()).formulas
        XCTAssertTrue(check.isComplete)
        XCTAssertGreaterThan(check.count, 3000)
    }

    /// The fixture with one sheet part changed, packed again.
    func variant(_ change: (String) -> String) throws -> Data {
        var zip = try ZipArchive(original())
        zip.set("xl/worksheets/sheet1.xml", change(zip.string("xl/worksheets/sheet1.xml")!))
        return try zip.write()
    }

    /// A function the app doesn't know: that cell and everything reading it are unknown, the rest still works out.
    func testUnknownFunctionsAreReported() throws {
        let data = try variant { $0.replacingOccurrences(of: ">SUM(L47,L27,L11)</f>", with: ">SUMPRODUCT(L47,L27,L11)</f>") }
        let r = try MPWorkbook.read(data)
        XCTAssertTrue(r.formulas.unknown.contains("L53"))
        XCTAssertTrue(r.formulas.unknown.contains("DL54"), "the cumulative row reads L53")
        XCTAssertTrue(r.formulas.differs.isEmpty)
        // export still works out the rest
        var a = r.actual
        a.set(4, task: .structure, week: day(2024, 10, 27), weight: 10)
        let sheet = MPWorkbook.Sheet(try ZipArchive(MPWorkbook.export(data, input: r.input, actual: a).data).string("xl/worksheets/sheet1.xml")!, shared: [])
        XCTAssertEqual(sheet.number(MPWorkbook.Sheet.split("BC56")!.0, 56), 4)
    }

    /// A saved result the app works out differently: export writes no results of its own.
    func testAFileTheAppMisreadsKeepsExcelsResults() throws {
        let data = try variant { $0.replacingOccurrences(of: #"<f>H27-G27</f><v>58</v>"#, with: #"<f>H27-G27</f><v>57</v>"#) }
        let r = try MPWorkbook.read(data)
        XCTAssertEqual(r.formulas.differs, ["I27"])
        var a = r.actual
        a.set(4, task: .structure, week: day(2024, 10, 27), weight: 10)
        let zip = try ZipArchive(MPWorkbook.export(data, input: r.input, actual: a).data)
        let sheet = MPWorkbook.Sheet(zip.string("xl/worksheets/sheet1.xml")!, shared: [])
        XCTAssertEqual(sheet.number(MPWorkbook.Sheet.split("BC30")!.0, 30), 4, "the input is written")
        XCTAssertEqual(sheet.number(MPWorkbook.Sheet.split("BC56")!.0, 56), 0, "Excel's saved result stays")
        XCTAssertEqual(zip.data("xl/charts/chart1.xml"), try ZipArchive(data).data("xl/charts/chart1.xml"))
        XCTAssertTrue(zip.string("xl/workbook.xml")!.contains("fullCalcOnLoad=\"1\""), "Excel works them out on opening")
    }

    /// Taking an Excel-edited copy's progress back: a booking moved in Excel moves, one booked in the app since stays.
    func testAMoveInExcelComesBackAsAMove() throws {
        let r = try MPWorkbook.read(original())
        XCTAssertNil(r.base, "a file the app never wrote")
        var a = r.actual
        a.set(4, task: .structure, week: day(2024, 10, 27), weight: 10)       // BC30
        let exported = try MPWorkbook.export(original(), input: r.input, actual: a).data
        let back = try MPWorkbook.read(exported)
        XCTAssertEqual(back.base, back.actual, "the record is what the file holds")
        XCTAssertEqual(back.base?.points(.structure, week: day(2024, 10, 27)), 4)
        XCTAssertTrue(back.coverage.tasks.contains(MasterSchedule.Task.structure.rawValue))
        XCTAssertTrue(back.coverage.weeks.contains(MasterSchedule.Actual.key(day(2024, 11, 3))))
        XCTAssertEqual(try MPWorkbook.export(exported, input: back.input, actual: back.actual).data, exported,
                       "nothing new: the same bytes, record and all")

        // in Excel: 27 ต.ค.'s 4 moved to 3 พ.ย. (BD30); in the app since the export: 2 in 10 พ.ย.
        var zip = try ZipArchive(exported)
        var xml = zip.string("xl/worksheets/sheet1.xml")!
        XCTAssertTrue(xml.contains(#"<c r="BC30" s="36"><v>4</v></c>"#))
        xml = xml.replacingOccurrences(of: #"<c r="BC30" s="36"><v>4</v></c>"#, with: #"<c r="BC30" s="36"/>"#)
        xml = xml.replacingOccurrences(of: #"<c r="BD30" s="36"/>"#, with: #"<c r="BD30" s="36"><v>4</v></c>"#)
        zip.set("xl/worksheets/sheet1.xml", xml)
        let edited = try MPWorkbook.read(zip.write())
        var app = a
        app.set(2, task: .structure, week: day(2024, 11, 10), weight: 10)
        let (merged, changed) = app.merging(edited.actual, base: edited.base, covering: edited.coverage)
        XCTAssertEqual(merged.points(.structure, week: day(2024, 10, 27)), 0, "moved in Excel")
        XCTAssertEqual(merged.points(.structure, week: day(2024, 11, 3)), 4)
        XCTAssertEqual(merged.points(.structure, week: day(2024, 11, 10)), 2, "booked in the app since")
        XCTAssertEqual(changed, 2)

        // a record that is out of date (the file edited in Excel) is brought up to date by the next export
        let again = try MPWorkbook.export(zip.write(), input: edited.input, actual: edited.actual)
        XCTAssertEqual(again.changedCells, 0)
        XCTAssertEqual(try MPWorkbook.read(again.data).base, edited.actual)
    }

    /// The record survives being read whatever prefix and declaration a save gives the part.
    func testTheRecordReadsAfterASave() throws {
        var a = MasterSchedule.Actual()
        a.set(1.5, task: .panels, week: day(2024, 11, 3), weight: 10)
        var zip = ZipArchive()
        zip.set("xl/_rels/workbook.xml.rels", #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>"#)
        zip.set("[Content_Types].xml", #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"></Types>"#)
        MPWorkbook.Snapshot.write(a, into: &zip)
        XCTAssertTrue(zip.string("[Content_Types].xml")!.contains(#"<Default Extension="xml" ContentType="application/xml"/>"#))
        XCTAssertEqual(MPWorkbook.Snapshot.read(zip), a)
        let saved = zip.string("customXml/item1.xml")!
            .replacingOccurrences(of: #"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"#, with: "<?xml version=\"1.0\"?><!-- saved -->")
            .replacingOccurrences(of: "tc:", with: "ns0:").replacingOccurrences(of: "xmlns:tc", with: "xmlns:ns0")
        zip.set("customXml/item1.xml", saved)
        XCTAssertEqual(MPWorkbook.Snapshot.read(zip), a)
        // written again: the same part, no second one
        MPWorkbook.Snapshot.write(a, into: &zip)
        XCTAssertFalse(zip.contains("customXml/item2.xml"))
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

        // only the sheet's cells, the S-curve's saved series and the recalc flag changed, and the progress record was
        // added (`Snapshot`); every other part is the original's
        let before = try ZipArchive(data), after = try ZipArchive(out.data)
        let record = ["customXml/item1.xml", "customXml/itemProps1.xml", "customXml/_rels/item1.xml.rels"]
        XCTAssertEqual(before.paths + record, after.paths)
        for p in before.paths where !["xl/worksheets/sheet1.xml", "xl/workbook.xml", "xl/charts/chart1.xml",
                                      "xl/_rels/workbook.xml.rels", "[Content_Types].xml"].contains(p) {
            XCTAssertEqual(before.data(p), after.data(p), p)
        }
        XCTAssertEqual(back.base, a, "the record is the progress the file now holds")
        XCTAssertEqual(after.string("xl/_rels/workbook.xml.rels"),
                       before.string("xl/_rels/workbook.xml.rels")?.replacingOccurrences(of: "</Relationships>", with:
                           #"<Relationship Id="rIdTCRoofProgress" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml" Target="../customXml/item1.xml"/></Relationships>"#))
        XCTAssertEqual(after.string("[Content_Types].xml"),
                       before.string("[Content_Types].xml")?.replacingOccurrences(of: "</Types>", with:
                           #"<Override PartName="/customXml/itemProps1.xml" ContentType="application/vnd.openxmlformats-officedocument.customXmlProperties+xml"/></Types>"#))
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
        // besides the five inputs, only formula results changed: every formula and style is the original's
        let cellsBefore = SheetCells(sheetBefore), cellsAfter = SheetCells(sheetAfter)
        XCTAssertEqual(Set(cellsBefore.refs), Set(cellsAfter.refs))
        let inputs: Set = ["BC30", "BD30", "AJ14", "G30", "H14"]
        func formula(_ el: String) -> String { el.replacingOccurrences(of: #"<v>[^<]*</v>|\s t="[a-z]+""#, with: "", options: .regularExpression) }
        var results = 0
        for ref in cellsBefore.refs where !inputs.contains(ref) {
            let a = cellsBefore.element(ref)!, b = cellsAfter.element(ref)!
            guard a != b else { continue }
            XCTAssertTrue(a.contains("<f"), "\(ref) isn't a formula")
            XCTAssertEqual(formula(a), formula(b), ref)
            results += 1
        }
        XCTAssertGreaterThan(results, 50, "the Part sums and cumulative rows move")
        XCTAssertEqual(sheetAfter.components(separatedBy: "</sheetData>").last, sheetBefore.components(separatedBy: "</sheetData>").last,
                       "merges, conditional formats and print set-up stay")

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
        // 2.3's end (G33 + Day) still works out, so it stays a formula; 1.3 = 2.1's start didn't move and stays too;
        // 2.4 starts 5 days before 2.3 ends, which no longer matches the file's plan, so it becomes a value
        XCTAssertTrue(sheet.contains("<f>G33+I33</f><v>45627</v>"), "2.3 ends 1 ธ.ค. 2567 by its own formula")
        XCTAssertTrue(sheet.contains(#"<c r="I33" s="151"><v>11</v></c>"#) || sheet.contains("<c r=\"I33\""))
        XCTAssertTrue(sheet.contains("<f>G29</f>"))
        XCTAssertFalse(sheet.contains("<f>H33-5</f>"))
        XCTAssertTrue(sheet.contains("<f>G35+I35</f>"), "2.4's end follows its start")
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

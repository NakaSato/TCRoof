import XCTest
@testable import TCRoofCore

/// The sheet preview's source map (docs/ui/iec62446-sheet-before), on the แพรกหนามแดง sample.
final class IECSheetSourceTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    func testEachRowGoesToItsStep() throws {
        let inv = try sample().inverters[0]
        for ref in ["E12", "E16", "E18"] { XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .before), .beforeVoltage, ref) }
        for ref in ["E13", "E14"] { XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .before), .beforeInsulation, ref) }
        XCTAssertEqual(IECReport.sheetSource("E21", inverter: inv, phase: .before), .afterVoltage)
        for ref in ["C3", "E5", "O5", "AA4", "E8", "E9", "E29", "E30", "AA30"] {
            XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .before), .setup, ref)
        }
        // the overview's checks and the energy rows (on a before sheet) aren't tinted
        for ref in ["E11", "E20", "E22", "AA25", "B5", "Y12"] { XCTAssertNil(IECReport.sheetSource(ref, inverter: inv, phase: .before), ref) }
        XCTAssertEqual(IECReport.sheetSource("E22", inverter: inv, phase: .after), .energy)
        XCTAssertEqual(IECReport.sheetSource("E17", inverter: inv, phase: .after), .afterVoltage)
    }

    /// `INV nn-หลัง` (board 5b): steps 1–3 as on the before sheet, step 4 on rows 17 / 19 and E21, step 5 on the energy cells.
    func testTheAfterSheetAddsStepsFourAndFive() throws {
        let inv = try sample().inverters[0]
        for ref in ["E12", "E16", "E18"] { XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .after), .beforeVoltage, ref) }
        for ref in ["E13", "E14"] { XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .after), .beforeInsulation, ref) }
        for ref in ["E17", "U19", "E21"] { XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .after), .afterVoltage, ref) }
        for ref in ["E22", "E23", "E24", "E25", "E26", "AA25", "AA26"] {
            XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .after), .energy, ref)
        }
        for ref in ["C3", "E8", "AA30"] { XCTAssertEqual(IECReport.sheetSource(ref, inverter: inv, phase: .after), .setup, ref) }
        for ref in ["E11", "E20", "E27"] { XCTAssertNil(IECReport.sheetSource(ref, inverter: inv, phase: .after), ref) }
    }

    func testEmptySlotsStayWhite() throws {
        let r = try sample()
        // INV 2 uses slots 1, 3, 5, 7, 9–12: column F (slot 2) is empty
        XCTAssertNil(IECReport.sheetSource("F16", inverter: r.inverters[1], phase: .before))
        XCTAssertEqual(IECReport.sheetSource("G16", inverter: r.inverters[1], phase: .before), .beforeVoltage)
        XCTAssertNil(IECReport.sheetSource("F17", inverter: r.inverters[1], phase: .after), "after rows too")
        XCTAssertEqual(IECReport.sheetSource("G19", inverter: r.inverters[1], phase: .after), .afterVoltage)
        XCTAssertEqual(IECReport.sheetSlot("I16"), 5)
        XCTAssertNil(IECReport.sheetSlot("AA9"))
    }
}

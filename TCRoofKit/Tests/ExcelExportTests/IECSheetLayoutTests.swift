import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// The sheet preview's layout read from the template, and `IECExcel.cells` against the original (docs/ui/iec62446-sheet-before).
final class IECSheetLayoutTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TCRoofCoreTests/Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    func testTheLayoutComesFromTheTemplate() throws {
        let l = try IECSheetLayout.make(workbook: IECExcel.template(), sheet: "INV 01-ก่อน")
        XCTAssertEqual(l.columns.count, 28)
        XCTAssertEqual(l.rows.count, 35)
        for m in [IECSheetLayout.Merge(c0: 3, r0: 1, c1: 26, r1: 2), .init(c0: 5, r0: 5, c1: 14, r1: 5), .init(c0: 15, r0: 5, c1: 24, r1: 5),
                  .init(c0: 5, r0: 11, c1: 24, r1: 11), .init(c0: 5, r0: 14, c1: 24, r1: 15)] {
            XCTAssertTrue(l.merges.contains(m), "\(m)")
        }
        // the string columns E…X share one width; the header row is taller than a value row
        XCTAssertEqual(Set(l.columns[4...23]).count, 1)
        XCTAssertGreaterThan(l.width, 1000)
        XCTAssertEqual(l.cells["E16"]?.text, "755")
        XCTAssertEqual(l.cells["E12"]?.text, "✓", "Wingdings P shows as a tick")
        XCTAssertEqual(l.cells["AA9"]?.text, "145920")
        XCTAssertEqual(l.images.count, 2, "the PWA and PEA logos")
        XCTAssertTrue(l.images.allSatisfy { $0.x > l.x(24) && $0.y < l.y(4) }, "at the top right")
        let header = l.cells["B5"].map { l.styles[$0.style] }
        XCTAssertNotNil(header?.fill, "the header's grey")
        XCTAssertEqual(l.cell(at: l.x(10) + 1, l.y(14) + 1)?.col, 5, "a point in E14:X15 is E14")
    }

    func testCellsMatchTheOriginalAndTheExport() throws {
        let r = try sample()
        let original = try IECSheetLayout.make(workbook: IECExcel.template(), sheet: "INV 01-ก่อน")
        let cells = IECExcel.cells(for: r, sheet: "INV 01-ก่อน")
        // the original's typed values, wherever the app has the value (the app's ticks and IR summary differ by design)
        for (ref, v) in cells where !ref.hasPrefix("Y") && !ref.hasPrefix("Z") && ref != "E14" {
            let shown: String = switch v {
            case .number(let n): IECExcel.number(n)
            case .text(let t): t == "P" ? "✓" : t == "O" ? "✗" : t
            case .empty: ""
            }
            XCTAssertEqual(original.cells[ref]?.text ?? "", shown, ref)
        }
        // the preview of an export shows the same cells
        let exported = try IECSheetLayout.make(workbook: IECExcel.export(r), sheet: "INV 02-ก่อน")
        XCTAssertEqual(exported.cells["E16"]?.text, "753")
        XCTAssertEqual(exported.cells["F16"]?.text ?? "", "", "slot 2 has no string on INV 2")
    }

    /// The after sheets (board 5b): the same layout, and the export's cells as the original's.
    func testTheAfterSheetsComeFromTheTemplateToo() throws {
        let r = try sample()
        for n in ["INV 01-หลัง", "INV 02-หลัง"] {
            let l = try IECSheetLayout.make(workbook: IECExcel.template(), sheet: n)
            XCTAssertEqual(l.columns.count, 28, n)
            XCTAssertEqual(l.rows.count, 35, n)
            XCTAssertTrue(l.merges.contains(.init(c0: 3, r0: 1, c1: 26, r1: 2)), n)
            XCTAssertEqual(l.images.count, 2, n)
        }
        let original = try IECSheetLayout.make(workbook: IECExcel.template(), sheet: "INV 01-หลัง")
        // PR, Yf, the daily energy and the efficiency are the app's own figures (IECExcelTests pins them), not the original's
        let computed: Set = ["E22", "E23", "E24", "E26"]
        for (ref, v) in IECExcel.cells(for: r, sheet: "INV 01-หลัง") where !ref.hasPrefix("Y") && !ref.hasPrefix("Z") && ref != "E14" && !computed.contains(ref) {
            let shown: String = switch v {
            case .number(let n): IECExcel.number(n)
            case .text(let t): t == "P" ? "✓" : t == "O" ? "✗" : t
            case .empty: ""
            }
            XCTAssertEqual(original.cells[ref]?.text ?? "", shown, ref)
        }
        let exported = try IECSheetLayout.make(workbook: IECExcel.export(r), sheet: "INV 01-หลัง")
        XCTAssertEqual(exported.cells["E16"]?.text, original.cells["E16"]?.text, "the before values are on the after sheet too")
    }
}

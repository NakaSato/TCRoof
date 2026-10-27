import XCTest
@testable import TCRoofCore

/// iPad A3 v3 (docs/ui/survey-a3-ipad-v3): standard values on a size pick, the low-voltage current hint, AF อัตโนมัติ
/// and the main breaker's รุ่น split from its brand.
final class A3OptionsTests: XCTestCase {
    static let sizes = ["50", "100", "160", "250", "315", "400", "500", "630", "800", "1000", "1250", "1500", "2000", "2500"]

    func testEveryStandardSizeHasValues() throws {
        for k in Self.sizes {
            let v = try XCTUnwrap(TransformerStandard.values(kva: k), k)
            XCTAssertEqual(v.voltage, "22k/230-400", k)
            XCTAssertEqual(v.vectorGroup, "Dyn11", k)
            XCTAssertEqual(v.impedance, Double(k)! <= 630 ? "4" : "6", k)
            XCTAssertTrue(A3Options.transformerVoltages.contains(v.voltage))
            XCTAssertTrue(A3Options.vectorGroups.contains(v.vectorGroup))
            XCTAssertTrue(A3Options.impedances.contains(v.impedance))
        }
    }

    func testImpedanceEdgeBetween630And800() {
        XCTAssertEqual(TransformerStandard.values(kva: "630")?.impedance, "4")
        XCTAssertEqual(TransformerStandard.values(kva: "800")?.impedance, "6")
        XCTAssertEqual(TransformerStandard.values(kva: "631")?.impedance, "6")
    }

    func testVoltageFollowsTheMeter() {
        XCTAssertEqual(TransformerStandard.values(kva: "400", meterKV: "33")?.voltage, "33k/230-400")
        XCTAssertEqual(TransformerStandard.values(kva: "400", meterKV: "22")?.voltage, "22k/230-400")
        XCTAssertEqual(TransformerStandard.values(kva: "400", meterKV: "")?.voltage, "22k/230-400")
    }

    func testNoValuesWithoutASize() {
        XCTAssertNil(TransformerStandard.values(kva: ""))
        XCTAssertNil(TransformerStandard.values(kva: "abc"))
        XCTAssertNil(TransformerStandard.values(kva: "0"))
        XCTAssertNil(TransformerStandard.lvCurrent(kva: ""))
    }

    func testLowVoltageCurrent() {
        // kVA × 1000 / (√3 × 400)
        XCTAssertEqual(TransformerStandard.lvCurrent(kva: 400), 577)
        XCTAssertEqual(TransformerStandard.lvCurrent(kva: 630), 909)
        XCTAssertEqual(TransformerStandard.lvCurrent(kva: 1000), 1443)
        XCTAssertEqual(TransformerStandard.lvCurrent(kva: 50), 72)
        XCTAssertEqual(TransformerStandard.lvCurrent(kva: " 2,500 "), 3608)
    }

    func testAutoAFIsTheSmallestFrameAtOrAboveTheTrip() {
        XCTAssertEqual(A3Options.autoAF(at: "800", frames: A3Options.mainAF), "800")
        XCTAssertEqual(A3Options.autoAF(at: "700", frames: A3Options.mainAF), "800")
        XCTAssertEqual(A3Options.autoAF(at: "200", frames: A3Options.mainAF), "250")
        XCTAssertEqual(A3Options.autoAF(at: "50", frames: A3Options.mainAF), "100")
        XCTAssertEqual(A3Options.autoAF(at: "100", frames: A3Options.subAF), "100")
        XCTAssertEqual(A3Options.autoAF(at: "40", frames: A3Options.subAF), "63")
        // above every frame, or no trip yet: nothing to suggest
        XCTAssertNil(A3Options.autoAF(at: "5000", frames: A3Options.mainAF))
        XCTAssertNil(A3Options.autoAF(at: "", frames: A3Options.mainAF))
        // frames in any order
        XCTAssertEqual(A3Options.autoAF(at: "120", frames: ["400", "125", "160"]), "125")
    }

    func testYearsCountBackFromThisBuddhistYear() {
        let d = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 27).date!
        let y = A3Options.years(now: d)
        XCTAssertEqual(y.count, 30)
        XCTAssertEqual(y.first, "2569")
        XCTAssertEqual(y.last, "2540")
    }

    func testBoardModelDecodesFromOldJSON() throws {
        let old = try JSONDecoder().decode(Board.self, from: Data(#"{"name":"MDP-1","brand":"Schneider MTZ1 08"}"#.utf8))
        XCTAssertEqual(old.model, "")
        XCTAssertEqual(old.brandModel, "Schneider MTZ1 08")

        var b = Board(name: "MDP-1")
        b.brand = "Schneider"; b.model = "MTZ1 08"
        let back = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(back.model, "MTZ1 08")
        XCTAssertEqual(back.brandModel, "Schneider MTZ1 08")
        b.brand = ""
        XCTAssertEqual(b.brandModel, "MTZ1 08")
    }

    func testSingleLinePrintsBrandAndModel() throws {
        var t = Transformer(kva: "630")
        var b = Board(name: "MDP-1", at: "800")
        b.brand = "Schneider"; b.model = "MTZ1 08"
        t.setBoards([b])
        let sl = SingleLine.build(Job(values: Values(["trafos": .transformers([t])])))
        XCTAssertEqual(sl.transformers.first?.boards.first?.main.brand.text, "Schneider MTZ1 08")
    }
}

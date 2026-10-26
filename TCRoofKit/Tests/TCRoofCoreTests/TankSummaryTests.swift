import XCTest
@testable import TCRoofCore

/// docs/specs/auto-drawing.md §5.5: the tank's size and volume summary, and the printed plan's beams, section marks
/// and cross vents.
final class TankSummaryTests: XCTestCase {
    func texts(_ s: Sketch) -> [String] { s.ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { return t }; return nil } }

    func tank(_ x: String, _ y: String, height: Double?) -> Values {
        var v = Values()
        v[Roof.Key.spansX] = .text(x); v[Roof.Key.spansY] = .text(y)
        if let height { Tank.setHeight(&v, height) }
        return v
    }

    func testSummaryOfA12By8Tank() throws {
        let s = try XCTUnwrap(Tank.summary(tank("4,4,4", "4,4", height: 4.5)))
        XCTAssertEqual(s.roofArea, 96, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.grossVolume), 432, accuracy: 1e-9)
        XCTAssertEqual(s.text, "12.00 × 8.00 × 4.50 ม. | หลังคา 96 ม² | ปริมาตรภายนอกโดยประมาณ 432 ม³")
    }

    func testSummaryWithoutHeightOrSize() throws {
        let s = try XCTUnwrap(Tank.summary(tank("4,4,4,4,4,4,4,4,4,4", "4,4,4,4,4,4,4,4,4,4", height: nil)))
        XCTAssertNil(s.grossVolume)
        XCTAssertEqual(s.text, "40.00 × 40.00 ม. | หลังคา 1,600 ม²")
        XCTAssertNil(Tank.summary(Values()))
        // a small tank keeps a decimal
        XCTAssertEqual(Tank.Summary.grouped(2.26), "2.3")
        XCTAssertEqual(Tank.Summary.grouped(12_345.4), "12,345")
    }

    func testThePrintedPlanAddsBeamsMarksAndSummary() throws {
        var v = TankDXFTests.sample()
        Tank.setHeight(&v, 4.5)
        let screen = try XCTUnwrap(TankPlan(v)), sheet = try XCTUnwrap(TankPlan(v, details: true))
        XCTAssertEqual(sheet.tags.count, sheet.sketch.ops.count)
        // 9 inner grid lines each way, two dashed lines each
        XCTAssertEqual(sheet.tags.filter { $0 == "beam" }.count, 36)
        let t = texts(sheet.sketch)
        XCTAssertEqual(t.filter { $0 == "1" }.count, 3, "two marks of 1–1 and grid bubble 1")
        XCTAssertEqual(t.filter { $0 == "2" }.count, 3, "two marks of 2–2 and grid bubble 2")
        XCTAssertTrue(t.contains("40.00 × 40.00 × 4.50 ม. | หลังคา 1,600 ม² | ปริมาตรภายนอกโดยประมาณ 7,200 ม³"))
        XCTAssertTrue(t.contains(TankDrawings.note))
        XCTAssertGreaterThan(sheet.sketch.height, screen.sketch.height)
        XCTAssertFalse(texts(screen.sketch).contains(TankDrawings.note), "the D1 page's plan is unchanged")
        // the printed plan is the PDF's and Excel's
        XCTAssertEqual(Drawings.plan(v, tank: true)?.ops.count, sheet.sketch.ops.count)
    }

    func testCrossVentsOnlyForACrossDesign() throws {
        var v = Values()
        TankDesign.apply(&v, .pwa40x40)
        let vents = v.obstacles(Roof.Key.obstacles).filter { $0.kind == TankPoints.vent && !$0.isAbsent }.count
        XCTAssertGreaterThan(vents, 0)
        func polygons(_ s: Sketch) -> Int { s.ops.filter { if case let .polygon(p, _, _, _) = $0 { return p.count == 12 }; return false }.count }
        XCTAssertEqual(polygons(try XCTUnwrap(TankPlan(v, details: true)).sketch), vents)
        XCTAssertEqual(polygons(try XCTUnwrap(TankPlan(v)).sketch), 0)
        var box = Values()
        TankDesign.apply(&box, .pwa64x40)
        XCTAssertEqual(polygons(try XCTUnwrap(TankPlan(box, details: true)).sketch), 0)
    }

    func testTheDXFHasTheBeamsAndMarks() throws {
        let out = try XCTUnwrap(TankDXF.build(TankDXFTests.sample()))
        XCTAssertTrue(out.layers.contains("S-TANK-BEAM-E"))
        XCTAssertTrue(out.layers.contains("G-ANNO-SYMB"))
    }
}

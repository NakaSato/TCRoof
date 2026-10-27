import XCTest
@testable import TCRoofCore

/// The team's north arrow block on the plan DXFs (`NorthArrow`, `Resources/north-arrow.json`).
final class NorthArrowTests: XCTestCase {
    func text(_ d: Data) -> [String] { String(data: d, encoding: .isoLatin1)!.components(separatedBy: "\r\n") }
    /// The INSERTs of the arrow: their rotation (group 50, 0 when absent) and scale (group 41, 1 when absent).
    func arrows(_ d: Data) -> [(rotation: Double, scale: Double)] {
        DXFRead().rawEntities(d).filter { $0.first?.1 == "INSERT" && $0.contains { $0.0 == "2" && $0.1 == NorthArrow.blockName } }.map { e in
            (Double(e.first { $0.0 == "50" }?.1 ?? "0") ?? 0, Double(e.first { $0.0 == "41" }?.1 ?? "1") ?? 1)
        }
    }

    func testTheResource() throws {
        let a = try XCTUnwrap(NorthArrow.shared)
        XCTAssertEqual(a.texts.map(\.text), ["N", "W", "E", "S"])
        XCTAssertEqual(a.circles.first, [0, 0, 1])
        // N above the circle, S under it, E right and W left, as drawn
        let at = Dictionary(uniqueKeysWithValues: a.texts.map { ($0.text, $0.at) })
        XCTAssertGreaterThan(at["N"]![1], 1); XCTAssertLessThan(at["S"]![1], -1)
        XCTAssertGreaterThan(at["E"]![0], 1); XCTAssertLessThan(at["W"]![0], -1)
        XCTAssertEqual(a.polylines.count, 11)
        XCTAssertEqual(a.hatches.first?.loops.count, 4)
    }

    func testRoofPlanTurnsToTheTopEdgesBearing() {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        // no bearing: no arrow (the page takes north as an assumption)
        XCTAssertTrue(arrows(RoofDXF.build(v, parts: [.plan]).data).isEmpty)
        RoofMount.setBearing(&v, 90)
        let out = RoofDXF.build(v, parts: [.plan])
        let a = arrows(out.data)
        XCTAssertEqual(a.count, 1)
        // the top edge faces east, so north is to the plan's left: turned 90° counter-clockwise
        XCTAssertEqual(a.first?.rotation, 90)
        XCTAssertTrue(out.layers.contains(CADLayers.north.name))
        XCTAssertTrue(text(out.data).contains(NorthArrow.blockName))
    }

    func testSiteTurn() {
        XCTAssertEqual(NorthArrow.turn(siteNorth: "ด้านบน"), 0)
        XCTAssertEqual(NorthArrow.turn(siteNorth: "ด้านขวา"), -90)
        XCTAssertEqual(NorthArrow.turn(siteNorth: "ด้านล่าง"), 180)
        XCTAssertEqual(NorthArrow.turn(siteNorth: "ด้านซ้าย"), 90)
        XCTAssertEqual(NorthArrow.turn(siteNorth: nil), 0)
    }

    func testTankPlanUsesTheBlock() throws {
        var v = TankDXFTests.sample()
        Tank.setAzimuth(&v, 30, source: .manual)
        let out = try XCTUnwrap(TankDXF.build(v))
        let a = arrows(out.data)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.rotation, 30)
    }
}

import XCTest
@testable import TCRoofCore

/// The team's tank mounting components, taken one by one from their section drawings, as editable blocks in the tank DXF.
final class TankComponentsTests: XCTestCase {
    let t = SketchDXFTests(name: "x", testClosure: { _ in })

    /// Every component ships, true size in metres, with something to draw.
    func testComponentsLoad() throws {
        let c = try XCTUnwrap(TankComponents.shared).components
        XCTAssertEqual(Set(c.keys), Set(TankComponents.names.keys))
        for (id, x) in c { XCTAssertFalse(x.lines.isEmpty && x.polylines.isEmpty, id) }
        func size(_ id: String) throws -> (Double, Double) { let b = try XCTUnwrap(c[id]).box; return (b[2] - b[0], b[3] - b[1]) }
        XCTAssertEqual(try size("module_side").0, TankComponents.moduleDrawn, accuracy: 0.001)
        XCTAssertEqual(try size("rail_section").0, 0.0414, accuracy: 0.0005)
        XCTAssertEqual(try size("rail_section").1, 0.0675, accuracy: 0.0005)
        XCTAssertEqual(try size("topping").0, 0.30, accuracy: 0.001)
        XCTAssertEqual(try size("topping").1, 0.15, accuracy: 0.001)
        // the concrete keeps its pattern
        XCTAssertEqual(try XCTUnwrap(c["topping"]).hatches.first?.pattern, "AR-CONC")
    }

    /// In the tank DXF each component is one block, defined once, and the row section, the front elevation, the
    /// footings and the details are built from INSERTs of them.
    func testTheTankDrawingIsBuiltFromThem() throws {
        var v = TankDXFTests.sample(layout: true); v[Tank.Key.height] = .text("4.5")
        let l = try XCTUnwrap(TankLayout.current(v)), out = try XCTUnwrap(TankDXF.build(v))
        let lines = t.lines(out.data)
        for (_, n) in TankComponents.names {
            let defs = lines.indices.filter { lines[$0] == n.block && $0 >= 2 && lines[$0 - 2] == "AcDbBlockBegin" }
            XCTAssertEqual(defs.count, 1, n.block)
        }
        let inserts = t.records(out.data).filter { $0.first?.1 == "INSERT" }
        func count(_ b: String) -> Int { inserts.filter { t.value($0, "2") == b }.count }
        // the rows' section: two rows, two posts and two modules each
        XCTAssertEqual(count("TK_MODULE_SIDE"), 4)
        XCTAssertEqual(count("TK_BASE_SIDE"), 4); XCTAssertEqual(count("TK_ANCHOR_M12"), 4)
        // the front elevation: a base and a topping at every post pair of the longest table
        let front = try XCTUnwrap(TankDrawings.tableFrontCAD(l)).posts.count
        XCTAssertEqual(count("TK_BASE_FRONT"), front)
        XCTAssertEqual(count("TK_TOPPING"), 4 + front)
        XCTAssertEqual(count("TK_TOPPING_PLAN"), 1); XCTAssertEqual(count("TK_TOPPING_DETAIL"), 1)
        // the module stretched to the layout's module along the slope, turned to the tilt
        let m = try XCTUnwrap(inserts.first { t.value($0, "2") == "TK_MODULE_SIDE" })
        XCTAssertEqual(t.double(m, "41"), l.params.moduleL / TankComponents.moduleDrawn, accuracy: 1e-5)
        XCTAssertEqual(t.double(m, "50"), l.params.tilt, accuracy: 1e-3)
        // the footing block on the mounting plan holds the team's base plate block
        let foot = try XCTUnwrap(lines.indices.first { lines[$0] == "TC_FOOTING_300" && lines[$0 - 2] == "AcDbBlockBegin" })
        let end = try XCTUnwrap(lines[foot...].firstIndex(of: "ENDBLK"))
        XCTAssertTrue(lines[foot..<end].contains("TK_BASE_PLAN"))
        // each plan module block holds the team's PV panel block, stretched to the module
        let pv = try XCTUnwrap(lines.indices.first { lines[$0].hasPrefix("PV_MODULE_") && lines[$0 - 2] == "AcDbBlockBegin" })
        let pvEnd = try XCTUnwrap(lines[pv...].firstIndex(of: "ENDBLK"))
        XCTAssertTrue(lines[pv..<pvEnd].contains("TK_MODULE_PLAN"))
        // concrete as AR-CONC, with its line families
        XCTAssertTrue(lines.contains("AR-CONC"))
        // members are closed polylines, so they stretch by their grips: the rows' posts, rafters and braces
        let recs = t.records(out.data)
        let rafters = recs.filter { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == "P-RAFT-N" && t.double($0, "20") < 0 }
        XCTAssertEqual(rafters.count, 2)
        XCTAssertTrue(rafters.allSatisfy { t.value($0, "70") == "1" })
        // as the team's section 1 measures them: three braces a row (front, back and the outer strut), the rafter
        // inside the modules, the front brace on the rafter 0.565 m up from the low post
        let braces = recs.filter { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == "P-BRAC-N" && t.double($0, "20") < 0 }
        XCTAssertEqual(braces.count, 3 * 2 + 2 * max(0, front - 1))
        let p = l.params, tilt = p.tilt * .pi / 180
        func xs(_ r: [(String, String)]) -> [Double] { r.filter { $0.0 == "10" }.map { Double($0.1)! } }
        let first = try XCTUnwrap(rafters.min { (xs($0).min() ?? 0) < (xs($1).min() ?? 0) })
        let lo = try XCTUnwrap(xs(first).min()), hi = try XCTUnwrap(xs(first).max())
        XCTAssertGreaterThanOrEqual(lo, -p.frontOver * cos(tilt) - 0.1)
        XCTAssertLessThanOrEqual(hi, (-p.frontOver + 2 * p.moduleL + p.moduleGap) * cos(tilt) + 0.1)
        XCTAssertTrue(braces.contains { b in xs(b).contains { abs($0 - TankComponents.braceFront * cos(tilt)) < 0.04 } })
    }
}

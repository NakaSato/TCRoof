import XCTest
@testable import TCRoofCore

/// C1 "ส่งออก CAD" (docs/ui/survey-c1 `cadBuild`): a DXF R12 file with the design's layers.
final class RoofDXFTests: XCTestCase {
    func roof() -> Values {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        v["obst"] = .obstacles([Obstacle(x: "6.4", y: "1", w: "0.8", h: "6.6", kind: "sky")])
        return v
    }
    func lines(_ d: Data) -> [String] {
        // TIS-620 is one byte a character; Latin-1 keeps the byte values for checking
        String(data: d, encoding: .isoLatin1)!.components(separatedBy: "\r\n")
    }

    func testHeaderLayersAndEntities() {
        let out = RoofDXF.build(roof(), parts: [.plan, .section, .table])
        let l = lines(out.data)
        XCTAssertEqual(Array(l.prefix(8)), ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009"])
        XCTAssertTrue(l.contains("ANSI_874"))
        XCTAssertEqual(l[l.firstIndex(of: "$INSUNITS")! + 2], "4", "millimetres")
        XCTAssertEqual(l.suffix(3), ["0", "EOF", ""])
        for layer in ["GRID", "OUTLINE", "RIDGE", "TRUSS", "POST", "PURLIN", "SKYLIGHT", "SECTION_MARK", "DIM", "TEXT", "SECTION", "TABLE"] {
            XCTAssertTrue(out.layers.contains(layer), layer)
        }
        XCTAssertFalse(out.layers.contains("PV"))
        // every layer is declared once in the LAYER table
        let table = l.firstIndex(of: "LAYER")!
        XCTAssertEqual(l[table + 2], String(out.layers.count))
        XCTAssertEqual(out.entities, zip(l, l.dropFirst()).filter { $0.0 == "0" && ["LINE", "CIRCLE", "TEXT"].contains($0.1) }.count)
        // 10 posts, 4 lines each, on POST
        let posts = zip(l, l.dropFirst()).filter { $0.0 == "8" && $0.1 == "POST" }.count
        XCTAssertEqual(posts, 40)
    }

    func testUnitsAndPV() {
        let mm = RoofDXF.build(roof(), parts: [.plan]), m = RoofDXF.build(roof(), parts: [.plan], millimetres: false)
        XCTAssertEqual(mm.entities, m.entities)
        XCTAssertEqual(lines(m.data)[lines(m.data).firstIndex(of: "$INSUNITS")! + 2], "6")
        // the outline's far corner: 19 m × 16 m
        XCTAssertTrue(lines(mm.data).contains("19000"))
        XCTAssertTrue(lines(m.data).contains("19"))
        let pv = RoofDXF.build(roof(), parts: [.pv])
        XCTAssertEqual(pv.layers.first, "PV")
        XCTAssertTrue(pv.layers.contains("PV_RAIL"))
        XCTAssertTrue(pv.layers.contains("PV_FOOT"))
    }

    func testThaiIsTIS620() {
        let d = RoofDXF.tis620("ก ×°")
        XCTAssertEqual(Array(d), [0xA1, 0x20, 0x78, 0x25, 0x25, 0x64])
        XCTAssertEqual(RoofDXF.num(1500), "1500")
        XCTAssertEqual(RoofDXF.num(0.25), "0.25")
        XCTAssertEqual(RoofDXF.layerSummary([.plan, .section, .table]), "GRID · POST · TRUSS · PURLIN · SECTION · DIM · TEXT · TABLE")
    }
}

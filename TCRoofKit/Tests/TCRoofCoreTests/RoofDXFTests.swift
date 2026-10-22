import XCTest
@testable import TCRoofCore

/// C1 "ส่งออก CAD" (docs/ui/survey-c1 `cadBuild`): a DXF R2000 file with the design's layers.
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
        XCTAssertEqual(Array(l.prefix(8)), ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1015"])
        XCTAssertTrue(l.contains("ANSI_874"))
        XCTAssertEqual(l[l.firstIndex(of: "$INSUNITS")! + 2], "6", "metres by default")
        XCTAssertEqual(l.suffix(3), ["0", "EOF", ""])
        for layer in ["G-GRID", "S-ROOF-OTLN-E", "S-ROOF-RIDG-E", "S-ROOF-FRAM-E", "S-COLS-E", "S-ROOF-PURL-E", "A-ROOF-SKYL-E", "G-ANNO-SYMB", "G-ANNO-DIMS", "G-ANNO-TEXT", "S-ROOF-SECT-E", "G-ANNO-SCHD"] {
            XCTAssertTrue(out.layers.contains(layer), layer)
        }
        XCTAssertFalse(out.layers.contains("E-PVMD-N"))
        // every layer is declared once in the LAYER table
        let t = SketchDXFTests()
        // layers 0 and Defpoints, and the drawing's
        XCTAssertEqual(t.tableCount(l, "LAYER"), out.layers.count + 2)
        XCTAssertEqual(out.entities, t.records(out.data).count)
        // 10 posts, each one closed LWPOLYLINE of 4 sides, on POST
        XCTAssertEqual(t.rawEntities(out.data).filter { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == "S-COLS-E" }.count, 10)
        XCTAssertEqual(t.entities(out.data).filter { t.value($0, "8") == "S-COLS-E" && $0.first?.1 == "LINE" }.count, 40)
        // the span chains: one DIMENSION per span and one per total, nothing else on DIM
        let v = roof(), spans = Roof.spans(v, .x).count + Roof.spans(v, .y).count
        // (the section's schematic dimensions stay lines: it isn't drawn to scale)
        let dim = t.rawEntities(RoofDXF.build(v, parts: [.plan]).data).filter { t.value($0, "8") == "G-ANNO-DIMS" }
        XCTAssertEqual(dim.filter { $0.first?.1 == "DIMENSION" }.count, spans + 2)
        XCTAssertTrue(dim.allSatisfy { $0.first?.1 == "DIMENSION" })
    }

    func testUnitsAndPV() {
        let mm = RoofDXF.build(roof(), parts: [.plan], millimetres: true), m = RoofDXF.build(roof(), parts: [.plan])
        XCTAssertEqual(mm.entities, m.entities)
        XCTAssertEqual(lines(m.data)[lines(m.data).firstIndex(of: "$INSUNITS")! + 2], "6")
        // the outline's far corner: 19 m × 16 m
        XCTAssertTrue(lines(mm.data).contains("19000"))
        XCTAssertTrue(lines(m.data).contains("19"))
        let pv = RoofDXF.build(roof(), parts: [.pv])
        XCTAssertEqual(pv.layers.first, "E-PVMD-N")
        XCTAssertTrue(pv.layers.contains("S-PVRL-N"))
        XCTAssertTrue(pv.layers.contains("S-PVFT-N"))
    }

    func testThaiIsTIS620() {
        let d = RoofDXF.tis620("ก ×°")
        XCTAssertEqual(Array(d), [0xA1, 0x20, 0x78, 0x25, 0x25, 0x64])
        XCTAssertEqual(RoofDXF.num(1500), "1500")
        XCTAssertEqual(RoofDXF.num(0.25), "0.25")
        XCTAssertEqual(RoofDXF.layerSummary([.plan, .section, .table]), "G-GRID | S-COLS-E | S-ROOF-FRAM-E | S-ROOF-PURL-E | S-ROOF-SECT-E | G-ANNO-DIMS | G-ANNO-TEXT | G-ANNO-SCHD")
    }
}

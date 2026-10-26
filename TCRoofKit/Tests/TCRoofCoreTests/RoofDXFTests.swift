import XCTest
@testable import TCRoofCore

/// C1 "ส่งออก CAD" (docs/ui/survey-c1 `cadBuild`): a DXF R2000 file with the design's layers.
final class RoofDXFTests: XCTestCase {
    func roof() -> Values {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        v["obst"] = .obstacles([Obstacle(x: "6.4", y: "1", w: "0.8", h: "6.6", kind: "sky")])
        // no walkway at all (a new layout has the ridge walkway), so the golden files keep the plain plan
        var c = RoofMount.choice(v); c.walkwayRidge = false; RoofMount.setChoice(&v, c)
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
        XCTAssertFalse(out.layers.contains("P-MODL-N"))
        // every layer is declared once in the LAYER table
        let t = SketchDXFTests()
        // layers 0 and Defpoints, and the drawing's
        XCTAssertEqual(t.tableCount(l, "LAYER"), out.layers.count + 2)
        XCTAssertEqual(out.entities, t.records(out.data).count)
        // the plan's 10 posts, each one closed LWPOLYLINE of 4 sides, on POST
        let plan = RoofDXF.build(roof(), parts: [.plan]).data
        XCTAssertEqual(t.rawEntities(plan).filter { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == "S-COLS-E" }.count, 10)
        XCTAssertEqual(t.entities(plan).filter { t.value($0, "8") == "S-COLS-E" && $0.first?.1 == "LINE" }.count, 40)
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
        XCTAssertEqual(pv.layers.first, "P-MODL-N")
        XCTAssertTrue(pv.layers.contains("P-RAIL-N"))
        XCTAssertTrue(pv.layers.contains("P-FOOT-N"))
    }

    func testThaiIsTIS620() {
        let d = RoofDXF.tis620("ก ×°")
        XCTAssertEqual(Array(d), [0xA1, 0x20, 0x78, 0x25, 0x25, 0x64])
        XCTAssertEqual(RoofDXF.num(1500), "1500")
        XCTAssertEqual(RoofDXF.num(0.25), "0.25")
        XCTAssertEqual(RoofDXF.layerSummary([.plan, .section, .table]), "G-GRID | S-COLS-E | S-ROOF-FRAM-E | S-ROOF-PURL-E | S-ROOF-SECT-E | G-ANNO-DIMS | G-ANNO-TEXT | G-ANNO-SCHD")
    }

    /// The mounting grid: every L-foot on a lettered line and a numbered line, with its own reference, and the plan's
    /// title moved down past the bubbles beyond the bottom eave.
    func testMountingGrid() throws {
        let v = roof(), m = RoofMount.layout(v, latitude: nil).layout, g = RoofMountGrid(m)
        XCTAssertEqual(g.faces.count, m.faces.filter(\.used).count)
        let feet = g.faces.flatMap { f in f.feet.map { (f, $0) } }
        XCTAssertFalse(feet.isEmpty)
        let refs = feet.map { g.ref($0.0, $0.1) }
        XCTAssertFalse(refs.contains(nil))
        XCTAssertEqual(Set(refs.compactMap { $0 }).count, refs.count, "one reference per foot")
        // letters run on across the faces, lower case
        let letters = g.faces.flatMap { $0.letters.map(\.name) }
        XCTAssertEqual(letters.first, "a")
        XCTAssertEqual(Set(letters).count, letters.count)
        // numbers read left to right on the plan
        for f in g.faces {
            let xs = f.numbers.map { f.face.plan($0.at, 0).x }
            XCTAssertEqual(xs, xs.sorted(), "face \(f.face.id)")
        }
        let raw = SketchDXFTests().rawEntities(RoofDXF.build(v, parts: [.plan, .pv]).data)
        func texts(_ layer: String) -> Set<String> {
            Set(raw.filter { $0.first?.1 == "TEXT" && SketchDXFTests().value($0, "8") == layer }.compactMap { SketchDXFTests().value($0, "1") })
        }
        let bubbles = texts("G-GRID")
        for name in letters { XCTAssertTrue(bubbles.contains(name), name) }
        let tags = texts("G-ANNO-TEXT")
        for r in refs.compactMap({ $0 }) { XCTAssertTrue(tags.contains(r), r) }
        // the title sits under every bubble
        let circles = raw.filter { $0.first?.1 == "CIRCLE" && SketchDXFTests().value($0, "8") == "G-GRID" }
        let lowest = circles.map { SketchDXFTests().double($0, "20") - SketchDXFTests().double($0, "40") }.min() ?? 0
        let title = try XCTUnwrap(raw.first { $0.first?.1 == "TEXT" && (SketchDXFTests().value($0, "1") ?? "").contains("Pratt") })
        XCTAssertLessThan(SketchDXFTests().double(title, "20") + 0.42, lowest)
    }

    /// Rails up the slope (รางตัดแป): portrait modules packed up the slope with only the module gap between rows, and
    /// the grid letters the purlins under the feet and numbers the rails.
    func testMountingGridRailsUpTheSlope() throws {
        var v = Values()
        v["spansX"] = .text("1.5,6,6,6,6,1.5"); v["spansY"] = .text("1.5,6,6,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        var c = RoofMount.choice(v); c.railsAcross = true
        RoofMount.setChoice(&v, c)
        let m = RoofMount.layout(v, latitude: nil).layout, g = RoofMountGrid(m)
        XCTAssertTrue(m.options.acrossPurlins)
        for f in m.faces where f.used {
            for (a, b) in zip(f.rows, f.rows.dropFirst()) { XCTAssertEqual(b.v - a.v - m.moduleUp, m.standard.moduleGap, accuracy: 1e-6) }
        }
        for f in g.faces {
            let rails = Set(m.faces.first { $0.face.id == f.face.id }!.columnRuns.flatMap(\.railsAt).map { Int(($0 * 1000).rounded()) })
            XCTAssertEqual(f.numbers.count, rails.count, "a number per rail")
            for l in f.letters { XCTAssertTrue(m.purlins.contains { abs($0 - l.at) < 0.05 }, "letter \(l.name) on a purlin") }
            XCTAssertFalse(f.feet.map { g.ref(f, $0) }.contains(nil))
        }
    }

    /// The structure drawing carries what the PDF prints: the member schedule with its counts and weights, details A / B,
    /// the plan's T1 marks and labels, and the section's member callouts with their numbers.
    /// As the team's own drawings come: every layer's lineweight Default, the display off, and concrete cut by the
    /// section hatched AR-CONC.
    func testNoLineweightsAndConcreteHatch() throws {
        let t = SketchDXFTests(), d = RoofDXF.build(roof(), parts: [.plan, .section]).data, l = lines(d)
        let layers = l.indices.filter { l[$0] == "AcDbLayerTableRecord" }
        XCTAssertFalse(layers.isEmpty)
        for i in layers { XCTAssertEqual(t.after(l, i, "370"), "-3") }
        XCTAssertEqual(l[l.firstIndex(of: "$LWDISPLAY")! + 2], "0")
        let hatches = t.rawEntities(d).filter { $0.first?.1 == "HATCH" }.compactMap { t.value($0, "2") }
        XCTAssertTrue(hatches.contains("AR-CONC"), "\(Set(hatches))")
        // the other exports keep the standard's lineweights
        var o = SketchDXF(); o.line(CADLayers.grid, (0, 0), (1, 0))
        XCTAssertTrue(lines(o.data()).contains("18"))
    }

    func testStructureScheduleDetailsAndMarks() throws {
        var v = roof()
        v["comp2"] = .text("C100x50x20x3.2")
        let t = SketchDXFTests(), raw = t.rawEntities(RoofDXF.build(v, parts: [.plan, .section, .table]).data)
        func texts(_ layer: String) -> [String] {
            raw.filter { $0.first?.1 == "TEXT" && t.value($0, "8") == layer }.compactMap { t.value($0, "1") }
        }
        let s = try XCTUnwrap(RoofTruss.schedule(v))
        // as written: TIS-620, read back byte for byte
        func enc(_ x: String) -> String { String(data: SketchDXF.tis620(x), encoding: .isoLatin1)! }
        let cells = texts("G-ANNO-SCHD")
        for r in s.rows where r.perFrameCount != nil { XCTAssertTrue(cells.contains(enc(RoofTruss.perFrameText(r))), r.name) }
        XCTAssertTrue(cells.contains(enc(RoofTruss.steelKgText(s))), "the steel total")
        XCTAssertTrue(cells.contains { $0.contains("C100x50x20x3.2") })
        // details A / B: their members on the section layer under the schedule, their labels in words
        XCTAssertNotNil(RoofTruss.details(v))
        XCTAssertTrue(texts("G-ANNO-TEXT").contains("T1"), "the plan's truss marks")
        // the section is clean like the team's CAD (the callouts ①–⑦ are the page's): only the plan's two section marks
        XCTAssertTrue(RoofSection(v, trueScale: true, callouts: false).callouts.isEmpty)
        XCTAssertEqual(raw.filter { $0.first?.1 == "CIRCLE" && t.value($0, "8") == "G-ANNO-SYMB" }.count, 2)
    }
}

import XCTest
@testable import TCRoofCore

/// docs/specs/cad-export-dxf phase 3: the D1 tank plan as DXF at real scale.
final class TankDXFTests: XCTestCase {
    let t = SketchDXFTests()
    var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures") }

    /// Preset 0 with its standard points, a level, an azimuth and a wall type.
    static func sample(layout: Bool = false) -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        TankPoints.seed(&v)
        v[Tank.Key.exposed] = .text("1.2"); v[Tank.Key.azimuth] = .text("30")
        v["tankType"] = .choice("ค.ส.ล.", other: "")
        if layout { TankLayout.save(&v, TankLayout.defaults(v), off: []) }
        return v
    }
    func spans(_ v: Values) -> (Double, Double) {
        (parseSpans(v.text(Roof.Key.spansX)).reduce(0, +), parseSpans(v.text(Roof.Key.spansY)).reduce(0, +))
    }
    func layerOf(_ e: [(String, String)]) -> String? { t.value(e, "8") }

    func testPlanUnchanged() throws {
        // recorded from TankPlan before `tags` and `frame` were added
        let before = try String(contentsOf: fixtures.appendingPathComponent("tankplan-before.svg"), encoding: .utf8)
        let plan = try XCTUnwrap(TankPlan(Self.sample()))
        XCTAssertEqual(plan.sketch.svg(), before)
        XCTAssertEqual(plan.tags.count, plan.sketch.ops.count)
        XCTAssertNil(plan.tags[0], "the background")
    }

    func testOutlineAtRealScale() throws {
        let v = Self.sample(), (TW, TH) = spans(v)
        let out = try XCTUnwrap(TankDXF.build(v))
        let l = t.lines(out.data)
        XCTAssertEqual(l[l.firstIndex(of: "$INSUNITS")! + 2], "6", "metres")
        for name in ["G-GRID", "S-TANK-OTLN-E", "G-ANNO-DIMS", "A-OPNG-E", "G-ANNO-NRTH", "G-ANNO-TEXT"] { XCTAssertTrue(out.layers.contains(name), name) }
        let outline = t.entities(out.data).filter { layerOf($0) == "S-TANK-OTLN-E" }
        let xs = outline.flatMap { [t.double($0, "10"), t.double($0, "11")] }, ys = outline.flatMap { [t.double($0, "20"), t.double($0, "21")] }
        XCTAssertEqual(xs.min()!, 0, accuracy: 1e-3)
        XCTAssertEqual(xs.max()!, TW, accuracy: 1e-3)
        XCTAssertEqual(ys.min()!, 0, accuracy: 1e-3)
        XCTAssertEqual(ys.max()!, TH, accuracy: 1e-3)
    }

    func testObstacleLinesInsideTheirBoxes() throws {
        let v = Self.sample(), (_, TH) = spans(v)
        let boxes: [Box] = v.obstacles(Roof.Key.obstacles).filter { !$0.isAbsent }.compactMap { o in
            guard let x = NumberInput.value(o.x), let y = NumberInput.value(o.y), let w = NumberInput.value(o.w), let h = NumberInput.value(o.h) else { return nil }
            return Box(x, TH - y - h, w, h)
        }
        XCTAssertFalse(boxes.isEmpty)
        let obstacle = t.entities(try XCTUnwrap(TankDXF.build(v)).data).filter { layerOf($0) == "A-OPNG-E" }
        let lines = obstacle.filter { $0.first?.1 == "LINE" }
        XCTAssertFalse(lines.isEmpty)
        // each box's hatch is one HATCH, on the obstacle layer's HATC layer
        let hatches = t.entities(try XCTUnwrap(TankDXF.build(v)).data).filter { layerOf($0) == "A-OPNG-HATC-E" && $0.first?.1 == "HATCH" }
        XCTAssertEqual(hatches.count, boxes.count)
        for e in lines {
            let a = Pt(t.double(e, "10"), t.double(e, "20")), b = Pt(t.double(e, "11"), t.double(e, "21"))
            let inside = boxes.contains { r in [a, b].allSatisfy { $0.x >= r.x - 1e-3 && $0.x <= r.maxX + 1e-3 && $0.y >= r.y - 1e-3 && $0.y <= r.maxY + 1e-3 } }
            XCTAssertTrue(inside, "\(a) \(b)")
        }
    }

    func testNoBackgroundAndNoColours() throws {
        let v = Self.sample(), (TW, _) = spans(v)
        let ents = t.entities(try XCTUnwrap(TankDXF.build(v)).data)
        // the white background rect spans the whole sketch, well outside the tank and its chains
        let far = ents.filter { e in ["10", "11"].contains { c in t.value(e, c).flatMap(Double.init).map { $0 < -30 || $0 > TW + 30 } ?? false } }
        XCTAssertTrue(far.isEmpty)
        XCTAssertNil(ents.first { t.value($0, "62") != nil }, "layer colours only")
        XCTAssertNil(TankDXF.build(Values()))
        // the north arrow is the team's block (NorthArrow), one INSERT on the north layer
        XCTAssertEqual(ents.filter { layerOf($0) == "G-ANNO-NRTH" && $0[0].1 == "INSERT" && t.value($0, "2") == NorthArrow.blockName }.count, 1)
    }

    func testPanelLayout() throws {
        let v = Self.sample(layout: true)
        let l = try XCTUnwrap(TankLayout.current(v))
        let out = try XCTUnwrap(TankDXF.build(v))
        XCTAssertTrue(out.layers.contains("P-MODL-N"))
        XCTAssertTrue(out.layers.contains("P-TABL-N"))
        // one INSERT of the module block per panel switched on
        XCTAssertEqual(t.entities(out.data).filter { layerOf($0) == "P-MODL-N" && $0.first?.1 == "INSERT" && (t.value($0, "2") ?? "").hasPrefix("PV_MODULE_") }.count, l.count)
        XCTAssertFalse(try XCTUnwrap(TankDXF.build(Self.sample())).layers.contains("P-MODL-N"))
    }

    /// Sections 1–1 and 2–2, the module rows' section and the table's front elevation sit under the plan, to scale in
    /// metres, with their measures as live DIMENSIONs.
    func testSectionsUnderThePlan() throws {
        var v = Self.sample(layout: true); v[Tank.Key.height] = .text("4.5")
        let H = try XCTUnwrap(Tank.height(v)), (TW, _) = spans(v)
        let l = try XCTUnwrap(TankLayout.current(v))
        let out = try XCTUnwrap(TankDXF.build(v))
        XCTAssertTrue(out.layers.contains("S-TANK-SECT-E"))
        let recs = t.rawEntities(out.data), dims = recs.filter { $0.first?.1 == "DIMENSION" }
        let plan = try XCTUnwrap(TankPlan(v, details: true)).dimensions.count
        let sections = [false, true].compactMap { TankDrawings.sectionCAD(v, across: $0) } + [TankDrawings.tableSectionCAD(l.params)]
            + [TankDrawings.tableFrontCAD(l)].compactMap { $0 }
        XCTAssertEqual(sections.count, 4)
        // the plan's chains twice (the module plan and the mounting plan), the mounting plan's own, the sections'
        let chains: Int = l.builtTables.map { (t: TankLayout.Table) -> Int in t.pairs + 1 }.reduce(0, +)
        let postLines: Set<Int> = Set(l.builtTables.flatMap { (t: TankLayout.Table) -> [Int] in t.posts.map { Int(($0.y * 1000).rounded()) } })
        let mounting = chains + postLines.count + 1
        // and the two footing details' (0.30 each way on the plan, 0.30 × 0.15 on DETAIL 1)
        XCTAssertEqual(dims.count, 2 * plan + mounting + sections.map(\.dimensions.count).reduce(0, +) + 4)
        // both tank sections' heights read H (metres), live
        let key = String(data: SketchDXF.tis620("สูง <>"), encoding: .isoLatin1)!
        let heights = dims.filter { t.value($0, "1") == key }
        XCTAssertEqual(heights.count, 2)
        XCTAssertTrue(heights.allSatisfy { abs(abs(t.double($0, "24") - t.double($0, "23")) - H) < 1e-3 })
        // the section lengths are the tank's: section 2–2 cuts across Σ spansX
        XCTAssertTrue(dims.contains { abs(abs(t.double($0, "14") - t.double($0, "13")) - TW) < 1e-3 && t.value($0, "50") == "0" })
        // the rows' spacings read the layout's
        XCTAssertTrue(dims.contains { abs(abs(t.double($0, "14") - t.double($0, "13")) - l.params.rowGap) < 1e-3 })
        // everything they add is below the plan: the tank's top-left corner is (0, TH), its sketch's lowest text a few m below 0
        let planBottom = try XCTUnwrap(recs.filter { $0.first?.1 == "INSERT" && (t.value($0, "2") ?? "").hasPrefix("PV_MODULE_") }.map { t.double($0, "20") }.min())
        let sectionLines = recs.filter { t.value($0, "8") == "S-TANK-SECT-E" }
        XCTAssertFalse(sectionLines.isEmpty)
        XCTAssertTrue(sectionLines.allSatisfy { e in e.filter { $0.0 == "20" }.allSatisfy { Double($0.1)! < planBottom - 2 } })
    }

    /// The mounting plan beside the module plan, as the team draws it: a footing block at every post, the rafters,
    /// rails and bracing as members on WIPEOUTs, a chain along each table and one across the post lines.
    func testMountingPlan() throws {
        let v = Self.sample(layout: true), l = try XCTUnwrap(TankLayout.current(v))
        XCTAssertEqual(l.turn % 2, 0, "rows along x in the sample")
        let out = try XCTUnwrap(TankDXF.build(v)), recs = t.rawEntities(out.data)
        let tables = l.builtTables, posts = tables.map(\.posts.count).reduce(0, +), pairs = tables.map(\.pairs).reduce(0, +)
        let footings = recs.filter { $0.first?.1 == "INSERT" && (t.value($0, "2") ?? "").hasPrefix("TC_FOOTING_") }
        XCTAssertEqual(footings.count, posts)
        XCTAssertTrue(footings.allSatisfy { t.value($0, "8") == "P-FTNG-N" })
        // the mounting plan's members (right of the module plan; the sections under it have their own)
        func members(_ layer: String) -> Int { recs.filter { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == layer && t.double($0, "10") > 40 }.count }
        XCTAssertEqual(members("P-RAFT-N"), pairs)
        XCTAssertEqual(members("P-RAIL-N"), 4 * tables.count)
        let braces = tables.map { 2 * max(0, $0.pairs - 1) }.reduce(0, +)
        XCTAssertEqual(members("P-BRAC-N"), braces)
        // each member on its own WIPEOUT
        XCTAssertEqual(recs.filter { $0.first?.1 == "WIPEOUT" }.count, pairs + 4 * tables.count + braces)
        // the footing block: the footing square (300 mm), base plate and post
        let lines = t.lines(out.data)
        XCTAssertTrue(lines.indices.contains { lines[$0] == "TC_FOOTING_300" && lines[$0 - 2] == "AcDbBlockBegin" })
        // a chain along a table measures its cantilevers and bays, summing to the table's length
        let first = try XCTUnwrap(tables.first)
        let along = recs.filter { $0.first?.1 == "DIMENSION" && t.value($0, "50") == "0" }.map { abs(t.double($0, "14") - t.double($0, "13")) }
        let fronts: [Double] = stride(from: 0, to: first.posts.count, by: 2).map { first.posts[$0].x }
        let bays: [Double] = zip(fronts, fronts.dropFirst()).map { $1 - $0 }
        for b in bays { XCTAssertTrue(along.contains { abs($0 - b) < 1e-3 }, "bay \(b)") }
        // it sits to the right of the module plan, which starts at the tank's west wall (x = 0)
        XCTAssertTrue(footings.allSatisfy { t.double($0, "10") > 40 })
    }

    /// The PDF's drawings are the same sketches the DXF places.
    func testThePDFDrawingsAreUnchanged() throws {
        var v = Self.sample(layout: true); v[Tank.Key.height] = .text("4.5")
        let l = try XCTUnwrap(TankLayout.current(v))
        for across in [false, true] {
            XCTAssertEqual(TankDrawings.section(v, across: across)?.ops.count, TankDrawings.sectionCAD(v, across: across)?.sketch.ops.count)
            // every op the DXF leaves out draws a dimension
            let c = try XCTUnwrap(TankDrawings.sectionCAD(v, across: across))
            XCTAssertTrue(c.dimensionOps.allSatisfy { i in
                if case let .line(_, _, _, col, _) = c.sketch.ops[i] { return col == TankDrawings.dim }
                if case let .text(_, _, _, _, col, _, _) = c.sketch.ops[i] { return col == TankDrawings.dim }
                return false
            })
        }
        XCTAssertEqual(TankDrawings.tableSection(l.params).ops.count, TankDrawings.tableSectionCAD(l.params).sketch.ops.count)
        XCTAssertEqual(TankDrawings.tableFront(l)?.ops.count, TankDrawings.tableFrontCAD(l)?.sketch.ops.count)
        // no height: no section in the DXF
        var w = Self.sample(); w[Tank.Key.height] = nil
        XCTAssertNotNil(TankDrawings.section(w, across: false))
        XCTAssertNil(TankDrawings.sectionCAD(w, across: false))
    }

    /// Each module is an INSERT of one PV_MODULE block; the table outlines are closed polylines.
    func testModulesAreBlocks() throws {
        let v = Self.sample(layout: true)
        let l = try XCTUnwrap(TankLayout.current(v)), out = try XCTUnwrap(TankDXF.build(v))
        let raw = t.rawEntities(out.data)
        let modules = raw.filter { $0.first?.1 == "INSERT" && (t.value($0, "2") ?? "").hasPrefix("PV_MODULE_") }
        XCTAssertEqual(modules.count, l.count)
        XCTAssertTrue(modules.allSatisfy { t.value($0, "8") == "P-MODL-N" })
        // on the plan (the sections under it draw their posts on the same layer)
        let tables = raw.filter { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == "P-TABL-N" && t.double($0, "20") >= 0 }
        XCTAssertEqual(tables.count, l.builtTables.count)
        XCTAssertTrue(tables.allSatisfy { t.value($0, "70") == "1" })
    }

    /// The mounting plan's grid: a letter on every post line, a number on every pair of a row, every footing on a
    /// crossing with its reference, and the same bubbles under the row section's and front elevation's posts.
    func testMountingGrid() throws {
        let v = Self.sample(layout: true), l = try XCTUnwrap(TankLayout.current(v)), g = TankMountGrid(l)
        let tables = l.builtTables, rows = Set(tables.map(\.row))
        XCTAssertEqual(g.rows.count, rows.count)
        XCTAssertEqual(g.letters.count, 2 * rows.count, "a front and a back line per row")
        XCTAssertEqual(g.letters.first?.name, "A")
        XCTAssertEqual(g.letters.dropFirst().first?.name, "B")
        // every post has a reference, and no two share one
        let refs = tables.flatMap(\.posts).map { g.ref($0) }
        XCTAssertFalse(refs.contains(nil))
        XCTAssertEqual(Set(refs.compactMap { $0 }).count, refs.count)
        XCTAssertEqual(TankMountGrid.letter(26), "AA")
        let out = try XCTUnwrap(TankDXF.build(v)), recs = t.rawEntities(out.data)
        let names = Set(recs.filter { $0.first?.1 == "TEXT" && t.value($0, "8") == "G-GRID" }.compactMap { t.value($0, "1") })
        for line in g.letters { XCTAssertTrue(names.contains(line.name), line.name) }
        for row in g.rows { for i in row.us.indices { XCTAssertTrue(names.contains("\(i + 1)")) } }
        // two bubbles per letter line and one per pair on the plan, plus those under the sections
        let circles = recs.filter { $0.first?.1 == "CIRCLE" && t.value($0, "8") == "G-GRID" }.count
        let pairs = g.rows.map(\.us.count).reduce(0, +)
        XCTAssertGreaterThan(circles, 2 * g.letters.count + pairs)
        let tags = Set(recs.filter { $0.first?.1 == "TEXT" && t.value($0, "8") == "G-ANNO-TEXT" }.compactMap { t.value($0, "1") })
        for r in refs.compactMap({ $0 }) { XCTAssertTrue(tags.contains(r), r) }
        // the footing schedule: a line per letter line naming its first footing, and the total
        let cells = recs.filter { $0.first?.1 == "TEXT" && t.value($0, "8") == "G-ANNO-SCHD" }.compactMap { t.value($0, "1") }
        for line in g.letters { XCTAssertTrue(cells.contains { $0.hasPrefix(line.name + "-1") }, line.name) }
        XCTAssertTrue(cells.contains("\(refs.count)"), "total")
        XCTAssertEqual(TankDXF.ranges([1, 2, 3, 5]) { "A-\($0)" }, ["A-1…A-3", "A-5"])
    }
}
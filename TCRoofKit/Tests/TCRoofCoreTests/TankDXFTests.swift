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
        XCTAssertEqual(l[l.firstIndex(of: "$INSUNITS")! + 2], "4")
        for name in ["GRID", "OUTLINE", "DIM", "OBSTACLE", "NORTH", "TEXT"] { XCTAssertTrue(out.layers.contains(name), name) }
        let outline = t.entities(out.data).filter { layerOf($0) == "OUTLINE" }
        let xs = outline.flatMap { [t.double($0, "10"), t.double($0, "11")] }, ys = outline.flatMap { [t.double($0, "20"), t.double($0, "21")] }
        XCTAssertEqual(xs.min()!, 0, accuracy: 1)
        XCTAssertEqual(xs.max()!, TW * 1000, accuracy: 1)
        XCTAssertEqual(ys.min()!, 0, accuracy: 1)
        XCTAssertEqual(ys.max()!, TH * 1000, accuracy: 1)
    }

    func testObstacleLinesInsideTheirBoxes() throws {
        let v = Self.sample(), (_, TH) = spans(v)
        let boxes: [Box] = v.obstacles(Roof.Key.obstacles).filter { !$0.isAbsent }.compactMap { o in
            guard let x = NumberInput.value(o.x), let y = NumberInput.value(o.y), let w = NumberInput.value(o.w), let h = NumberInput.value(o.h) else { return nil }
            return Box(x * 1000, (TH - y - h) * 1000, w * 1000, h * 1000)
        }
        XCTAssertFalse(boxes.isEmpty)
        let lines = t.entities(try XCTUnwrap(TankDXF.build(v)).data).filter { layerOf($0) == "OBSTACLE" }
        XCTAssertFalse(lines.isEmpty)
        for e in lines {
            let a = Pt(t.double(e, "10"), t.double(e, "20")), b = Pt(t.double(e, "11"), t.double(e, "21"))
            let inside = boxes.contains { r in [a, b].allSatisfy { $0.x >= r.x - 1 && $0.x <= r.maxX + 1 && $0.y >= r.y - 1 && $0.y <= r.maxY + 1 } }
            XCTAssertTrue(inside, "\(a) \(b)")
        }
    }

    func testNoBackgroundAndNoColours() throws {
        let v = Self.sample(), (TW, _) = spans(v)
        let ents = t.entities(try XCTUnwrap(TankDXF.build(v)).data)
        // the white background rect spans the whole sketch, well outside the tank and its chains
        let far = ents.filter { e in ["10", "11"].contains { c in t.value(e, c).flatMap(Double.init).map { $0 < -30_000 || $0 > TW * 1000 + 30_000 } ?? false } }
        XCTAssertTrue(far.isEmpty)
        XCTAssertNil(ents.first { t.value($0, "62") != nil }, "layer colours only")
        XCTAssertNil(TankDXF.build(Values()))
        // the north arrow's solid head is outlined
        XCTAssertGreaterThanOrEqual(ents.filter { layerOf($0) == "NORTH" && $0[0].1 == "LINE" }.count, 4)
    }

    func testPanelLayout() throws {
        let v = Self.sample(layout: true)
        let l = try XCTUnwrap(TankLayout.current(v))
        let out = try XCTUnwrap(TankDXF.build(v))
        XCTAssertTrue(out.layers.contains("PV"))
        XCTAssertTrue(out.layers.contains("PV_GROUP"))
        // one INSERT of the module block per panel switched on
        XCTAssertEqual(t.entities(out.data).filter { layerOf($0) == "PV" }.count, l.count)
        XCTAssertFalse(try XCTUnwrap(TankDXF.build(Self.sample())).layers.contains("PV"))
    }

    /// Each module is an INSERT of one PV_MODULE block; the table outlines are closed polylines.
    func testModulesAreBlocks() throws {
        let v = Self.sample(layout: true)
        let l = try XCTUnwrap(TankLayout.current(v)), out = try XCTUnwrap(TankDXF.build(v))
        let raw = t.rawEntities(out.data)
        let modules = raw.filter { $0.first?.1 == "INSERT" && (t.value($0, "2") ?? "").hasPrefix("PV_MODULE_") }
        XCTAssertEqual(modules.count, l.count)
        XCTAssertTrue(modules.allSatisfy { t.value($0, "8") == "PV" })
        let tables = raw.filter { $0.first?.1 == "POLYLINE" && t.value($0, "8") == "PV_GROUP" }
        XCTAssertEqual(tables.count, l.builtTables.count)
        XCTAssertTrue(tables.allSatisfy { t.value($0, "70") == "1" })
    }
}

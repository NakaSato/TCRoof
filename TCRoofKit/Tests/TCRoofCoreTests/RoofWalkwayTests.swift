import XCTest
@testable import TCRoofCore

/// C1's walkways drawn as the team's walkway detail, and the detail sheet beside the PV plan.
final class RoofWalkwayTests: XCTestCase {
    let t = SketchDXFTests(name: "x", testClosure: { _ in })
    func roof(every n: Int) -> Values {
        var v = RoofDXFTests(name: "x", testClosure: { _ in }).roof()
        var c = RoofMount.choice(v); c.walkwayEvery = n; RoofMount.setChoice(&v, c)
        return v
    }

    func roofCentre() -> Values {
        var v = RoofDXFTests(name: "x", testClosure: { _ in }).roof()
        var c = RoofMount.choice(v); c.walkwayCentre = true; RoofMount.setChoice(&v, c)
        return v
    }

    /// Most roofs have one walkway down the middle: the column nearest each face's centre along the eave.
    func testCentreWalkway() throws {
        let v = roofCentre()
        XCTAssertTrue(RoofMount.choice(v).walkwayCentre)
        XCTAssertTrue(v.text(RoofMount.Key.choice).contains("walkwayCentre"))
        let m = RoofMount.layout(v, latitude: 15).layout
        XCTAssertTrue(m.options.walkwayCentre)
        let ws = RoofWalkway.walkways(m)
        let used = m.faces.filter(\.used)
        XCTAssertFalse(ws.isEmpty)
        for f in used {
            let mine = ws.filter { $0.face.id == f.face.id && !$0.ridge }
            XCTAssertEqual(mine.count, 1, "one walkway on face \(f.face.id)")
            // in the middle: no other column's centre is nearer the face's middle
            let us = f.face.polygon.map(\.x), mid = ((us.min() ?? 0) + (us.max() ?? 0)) / 2
            let w = try XCTUnwrap(mine.first)
            XCTAssertLessThanOrEqual(abs(w.u + w.width / 2 - mid), m.moduleAlong / 2 + m.standard.moduleGap + 1e-6)
            // it starts at the first row and runs on past the last one up to the ridge
            XCTAssertFalse(w.access, "a gable roof is reached at the ridge, not the eave")
            XCTAssertEqual(w.v0, f.rows.first?.v ?? -1, accuracy: 1e-9)
            XCTAssertGreaterThan(w.v1, (f.rows.last?.v ?? 0) + m.moduleUp)
            XCTAssertEqual(w.v1, w.ridgeEnd - RoofWalkway.band / 2, accuracy: 1e-9)
            XCTAssertEqual(w.v1, f.face.slopeLength - RoofWalkway.band / 2, accuracy: 1e-6, "it meets the ridge walkway")
        }
        // older choices without it keep their digest; the DXF draws it with the detail
        XCTAssertFalse(RoofMount.choice(RoofDXFTests(name: "x", testClosure: { _ in }).roof()).walkwayCentre)
        // and one walkway along the ridge, centred on it, from the access landing at its left end (by default) to 0.50 m
        // in from the other; the modules keep clear of its band
        let ridge = try XCTUnwrap(ws.filter(\.ridge).first)
        XCTAssertEqual(ws.filter(\.ridge).count, 1)
        XCTAssertEqual(ridge.b0 + RoofWalkway.band / 2, ridge.face.slopeLength, accuracy: 1e-9)
        let (lo, hi) = try XCTUnwrap(ridge.face.span(atV: ridge.face.slopeLength))
        XCTAssertTrue(ridge.access); XCTAssertTrue(ridge.accessAtStart)
        XCTAssertEqual(ridge.wallS, lo, accuracy: 1e-9, "the ladder stands at the gable wall")
        XCTAssertEqual(ridge.v0, lo + RoofWalkway.landing, accuracy: 1e-9); XCTAssertEqual(ridge.v1, hi - RoofWalkway.ridgeInset, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(m.standard.setRidge, RoofWalkway.ridgeClear - 1e-9)
        for f in used { for row in f.rows { XCTAssertLessThanOrEqual(row.v + m.moduleUp, f.face.slopeLength - RoofWalkway.band / 2 + 1e-6) } }
        // one roof access only, on one side
        XCTAssertEqual(ws.filter(\.access).count, 1)
        let out = RoofDXF.build(v, parts: [.pv])
        XCTAssertTrue(out.layers.contains("P-LADD-N"))
        let s = String(decoding: out.data, as: UTF8.self)
        XCTAssertTrue(s.contains("TC_ROOF_ACCESS")); XCTAssertTrue(s.contains("ONE SIDE ONLY (LEFT)"))
        XCTAssertEqual(t.records(out.data).filter { r in r.first?.1 == "INSERT" && r.contains { $0.0 == "2" && $0.1 == "TC_ROOF_ACCESS" } }.count, 1)
        // the right end when picked: the landing at the ridge's other end
        var right = v; var c = RoofMount.choice(right); c.accessRight = true; RoofMount.setChoice(&right, c)
        XCTAssertEqual(RoofMount.digest(RoofMount.input(right, latitude: 15), choice: c), RoofMount.digest(RoofMount.input(v, latitude: 15), choice: RoofMount.choice(v)))
        let r2 = try XCTUnwrap(RoofWalkway.walkways(RoofMount.layout(right, latitude: 15).layout).first(where: \.ridge))
        XCTAssertFalse(r2.accessAtStart); XCTAssertEqual(r2.wallS, hi, accuracy: 1e-9)
        XCTAssertEqual(r2.v1, hi - RoofWalkway.landing, accuracy: 1e-9)
        XCTAssertTrue(String(decoding: RoofDXF.build(right, parts: [.pv]).data, as: UTF8.self).contains("ONE SIDE ONLY (RIGHT)"))
        XCTAssertTrue(out.layers.contains("P-WALK-N")); XCTAssertTrue(out.layers.contains("G-DETL"))
    }

    /// The page's plan and the PDF draw the walkways and the way up too (simplified), only when there are walkways.
    func testThePlanDrawsThem() throws {
        let v = roofCentre(), m = RoofMount.layout(v, latitude: 15).layout
        let p = RoofPlan(v, mode: .pv, mount: m)
        XCTAssertEqual(p.tags.filter { $0 == "walkway" }.count, 3 * RoofWalkway.walkways(m).count)
        XCTAssertTrue(p.tags.contains("access"))
        // the face labels stay on top of them
        let lastWalk = try XCTUnwrap(p.tags.lastIndex(of: "walkway")), firstLabel = try XCTUnwrap(p.tags.firstIndex(of: "facelabel"))
        XCTAssertLessThan(lastWalk, firstLabel)
        // without walkways: none, and the plan as before
        let plain = RoofDXFTests(name: "x", testClosure: { _ in }).roof()
        let q = RoofPlan(plain, mode: .pv, mount: RoofMount.layout(plain, latitude: 15).layout)
        XCTAssertFalse(q.tags.contains("walkway")); XCTAssertFalse(q.tags.contains("access"))
        // the CAD export draws its own, so the plan's are left out of it
        XCTAssertNil(RoofDXF.pvLayers["walkway"]); XCTAssertNil(RoofDXF.pvLayers["access"])
    }

    /// Each module of the roof's CAD plan is the team's PV panel block, fitted to the module.
    func testModulesAreThePanelBlock() throws {
        let v = roofCentre(), out = RoofDXF.build(v, parts: [.pv])
        let m = RoofMount.layout(v, latitude: 15).layout
        let inserts = t.records(out.data).filter { $0.first?.1 == "INSERT" && t.value($0, "2") == "TK_MODULE_PLAN" }
        XCTAssertEqual(inserts.count, m.quantities.modules)
        XCTAssertTrue(inserts.allSatisfy { t.value($0, "8") == "P-MODL-N" })
        // stretched from the drawn 0.992 × 1.956 to the module on plan (portrait: the short side along the eave, the
        // long side up the slope, foreshortened by the tilt)
        let first = try XCTUnwrap(inserts.first), tilt = try XCTUnwrap(m.faces.first).face.tilt
        XCTAssertEqual(abs(t.double(first, "41")) * TankComponents.modulePlanDrawn.w, m.moduleAlong, accuracy: 0.002)
        XCTAssertEqual(abs(t.double(first, "42")) * TankComponents.modulePlanDrawn.h, m.moduleUp * cos(tilt), accuracy: 0.002)
        // only the panel block of the tank components goes into a roof file
        let lines = t.lines(out.data)
        XCTAssertFalse(lines.contains("TK_TOPPING")); XCTAssertFalse(lines.contains("TK_MODULE_SIDE"))
    }

    func testWalkwaysFromTheLayout() throws {
        let m = RoofMount.layout(roof(every: 3), latitude: 15).layout
        let ws = RoofWalkway.walkways(m)
        XCTAssertFalse(ws.isEmpty)
        for w in ws {
            XCTAssertGreaterThan(w.v1, w.v0)
            XCTAssertEqual(w.width, m.moduleAlong, accuracy: 1e-9)
            // the panels cover the walkway end to end, none longer than 2.40
            let p = w.panels
            XCTAssertEqual(p.first?.0 ?? -1, w.v0, accuracy: 1e-9); XCTAssertEqual(p.last?.1 ?? -1, w.v1, accuracy: 1e-9)
            XCTAssertTrue(zip(p, p.dropFirst()).allSatisfy { abs($0.1 - $1.0) < 1e-9 })
            XCTAssertTrue(p.allSatisfy { $0.1 - $0.0 <= RoofWalkway.panel + 1e-9 })
            // lifeline supports every 2.40 from 0.65 in, inside the walkway; L-feet every 1.20 from 0.63 in
            let s = w.supports
            XCTAssertFalse(s.isEmpty)
            if w.v1 - w.v0 > 2 * RoofWalkway.supportStart { XCTAssertEqual(s[0], w.v0 + RoofWalkway.supportStart, accuracy: 1e-9) }
            XCTAssertTrue(s.allSatisfy { $0 > w.v0 && $0 < w.v1 })
            XCTAssertTrue(zip(s, s.dropFirst()).allSatisfy { abs($1 - $0 - RoofWalkway.support) < 1e-9 })
            if let f = w.feet.first { XCTAssertEqual(f, w.v0 + RoofWalkway.footStart, accuracy: 1e-9) }
            XCTAssertTrue(zip(w.feet, w.feet.dropFirst()).allSatisfy { abs($1 - $0 - RoofWalkway.foot) < 1e-9 })
            // the band sits inside its gap
            XCTAssertGreaterThanOrEqual(w.b0, w.u - 1e-9); XCTAssertLessThanOrEqual(w.b0 + RoofWalkway.band, w.u + w.width + 1e-9)
        }
        XCTAssertTrue(RoofWalkway.walkways(RoofMount.layout(roof(every: 0), latitude: 15).layout).isEmpty)
    }

    func testTheDXFDrawsThemAndTheDetail() throws {
        let v = roof(every: 3), out = RoofDXF.build(v, parts: [.pv]), recs = t.rawEntities(out.data)
        let ws = RoofWalkway.walkways(RoofMount.layout(v, latitude: nil).layout)
        for l in ["P-WALK-N", "P-LIFE-N", "P-CTRY-N", "G-DETL"] { XCTAssertTrue(out.layers.contains(l), l) }
        func count(_ type: String, _ layer: String) -> Int { recs.filter { $0.first?.1 == type && t.value($0, "8") == layer }.count }
        let panels = ws.map(\.panels.count).reduce(0, +), feet = ws.map(\.feet.count).reduce(0, +)
        // each panel's outline and inner frame; an L-foot square at both grating edges and each lifeline support on
        // their own layers (every object ByLayer)
        XCTAssertEqual(count("LWPOLYLINE", "P-WALK-N"), 2 * panels)
        XCTAssertEqual(count("LWPOLYLINE", "P-WALK-FOOT-N"), 2 * feet)
        XCTAssertEqual(count("LWPOLYLINE", "P-LIFE-SUPT-N"), ws.map(\.supports.count).reduce(0, +))
        XCTAssertFalse(recs.contains { ["P-WALK-N", "P-WALK-FOOT-N", "P-WALK-RAIL-N", "P-LIFE-N", "P-LIFE-SUPT-N"].contains(t.value($0, "8") ?? "") && t.value($0, "62") != nil })
        XCTAssertEqual(count("LWPOLYLINE", "P-CTRY-N"), ws.count)
        // a cross rail at every L-foot, under the whole band (outline and the hat section's two inner lines), drawn
        // before the tray and grating so their WIPEOUTs cover it
        XCTAssertEqual(count("LWPOLYLINE", "P-WALK-RAIL-N"), feet)
        let lines = t.lines(out.data)
        let firstRail = try XCTUnwrap(lines.indices.first { lines[$0] == "LWPOLYLINE" && lines[$0 + 8] == "P-WALK-RAIL-N" })
        let firstTray = try XCTUnwrap(lines.indices.first { lines[$0] == "WIPEOUT" && lines[$0 + 8] == "P-CTRY-N" })
        XCTAssertLessThan(firstRail, firstTray)
        // the top view's hatches, each on its layer's HATC layer: grating crossed (ANSI37), the tray dotted, the rail solid
        let hatches = recs.filter { $0.first?.1 == "HATCH" }
        XCTAssertEqual(hatches.filter { t.value($0, "2") == "ANSI37" && t.value($0, "8") == "P-WALK-HATC-N" }.count, panels)
        XCTAssertEqual(hatches.filter { t.value($0, "2") == "DOTS" && t.value($0, "8") == "P-CTRY-HATC-N" }.count, ws.count)
        XCTAssertEqual(hatches.filter { t.value($0, "2") == "SOLID" && t.value($0, "8") == "P-LIFE-RAIL-HATC-N" }.count, ws.count)
        // the grating and the tray hide what is under them
        XCTAssertEqual(count("WIPEOUT", "P-WALK-N"), panels)
        // the detail sheet, once, to the right of the plan
        let detail = recs.filter { $0.first?.1 == "INSERT" && t.value($0, "2") == "TC_DETAIL_WALKWAY" }
        XCTAssertEqual(detail.count, 1)
        // no walkway: none of it
        let none = RoofDXF.build(roof(every: 0), parts: [.pv])
        XCTAssertFalse(none.layers.contains("P-WALK-N")); XCTAssertFalse(none.layers.contains("G-DETL"))
    }

    func testTheDetailIsTheTeamsSheet() throws {
        let d = try XCTUnwrap(CADDetail.walkway)
        XCTAssertEqual(d.source, "Walkway.dxf")
        XCTAssertEqual(d.size[0], 326.5, accuracy: 1); XCTAssertEqual(d.size[1], 186.7, accuracy: 1)
        let words = Set(d.texts.map(\.text))
        for w in ["TOP VIEW", "ELEVATION 1", "DETAIL 1", "WIRE ROPE STEEL 6 mm.", "WALKWAY 0.30x2.40x0.03 m."] { XCTAssertTrue(words.contains(w), w) }
        // as a block, every primitive kept
        var x = SketchDXF()
        x.detailBlock(d, name: "D")
        let l = t.lines(x.data())
        let b = try XCTUnwrap(l.indices.first { l[$0] == "D" && l[$0 - 2] == "AcDbBlockBegin" })
        let body = l[b..<l[b...].firstIndex(of: "ENDBLK")!]
        // nearly every primitive kept (zero-length pieces and repeated points are dropped)
        let written = body.filter { $0 == "AcDbLine" || $0 == "AcDbPolyline" }.count
        XCTAssertGreaterThan(Double(written), 0.95 * Double(d.lines.count + d.polylines.count))
        XCTAssertLessThanOrEqual(written, d.lines.count + d.polylines.count)
        XCTAssertTrue(body.contains("G-DETL"))
    }
}

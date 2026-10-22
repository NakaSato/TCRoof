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
            let mine = ws.filter { $0.face.id == f.face.id }
            XCTAssertEqual(mine.count, 1, "one walkway on face \(f.face.id)")
            // in the middle: no other column's centre is nearer the face's middle
            let us = f.face.polygon.map(\.x), mid = ((us.min() ?? 0) + (us.max() ?? 0)) / 2
            let w = try XCTUnwrap(mine.first)
            XCTAssertLessThanOrEqual(abs(w.u + w.width / 2 - mid), m.moduleAlong / 2 + m.standard.moduleGap + 1e-6)
            // it runs the face's whole array, first row to last
            XCTAssertEqual(w.v0, f.rows.first?.v ?? -1, accuracy: 1e-9)
            XCTAssertEqual(w.v1, (f.rows.last?.v ?? 0) + m.moduleUp, accuracy: 1e-9)
        }
        // older choices without it keep their digest; the DXF draws it with the detail
        XCTAssertFalse(RoofMount.choice(RoofDXFTests(name: "x", testClosure: { _ in }).roof()).walkwayCentre)
        let out = RoofDXF.build(v, parts: [.pv])
        XCTAssertTrue(out.layers.contains("TC-PV-WALKWAY")); XCTAssertTrue(out.layers.contains("TC-DETAIL"))
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
            // lifeline supports at both ends, never more than 2.40 apart; L-feet every 1.20
            let s = w.supports
            XCTAssertEqual(s.first ?? -1, w.v0, accuracy: 1e-9); XCTAssertEqual(s.last ?? -1, w.v1, accuracy: 1e-9)
            XCTAssertTrue(zip(s, s.dropFirst()).allSatisfy { $1 - $0 <= RoofWalkway.support + 1e-9 })
            XCTAssertTrue(zip(w.feet, w.feet.dropFirst()).allSatisfy { abs($1 - $0 - RoofWalkway.foot) < 1e-9 })
            // the band sits inside its gap
            XCTAssertGreaterThanOrEqual(w.b0, w.u - 1e-9); XCTAssertLessThanOrEqual(w.b0 + RoofWalkway.band, w.u + w.width + 1e-9)
        }
        XCTAssertTrue(RoofWalkway.walkways(RoofMount.layout(roof(every: 0), latitude: 15).layout).isEmpty)
    }

    func testTheDXFDrawsThemAndTheDetail() throws {
        let v = roof(every: 3), out = RoofDXF.build(v, parts: [.pv]), recs = t.rawEntities(out.data)
        let ws = RoofWalkway.walkways(RoofMount.layout(v, latitude: nil).layout)
        for l in ["TC-PV-WALKWAY", "TC-PV-LIFELINE", "TC-PV-CABLETRAY", "TC-DETAIL"] { XCTAssertTrue(out.layers.contains(l), l) }
        func count(_ type: String, _ layer: String) -> Int { recs.filter { $0.first?.1 == type && t.value($0, "8") == layer }.count }
        let panels = ws.map(\.panels.count).reduce(0, +), feet = ws.map(\.feet.count).reduce(0, +)
        XCTAssertEqual(count("LWPOLYLINE", "TC-PV-WALKWAY"), panels + 2 * feet)
        XCTAssertEqual(count("CIRCLE", "TC-PV-LIFELINE"), ws.map(\.supports.count).reduce(0, +))
        XCTAssertEqual(count("LWPOLYLINE", "TC-PV-CABLETRAY"), ws.count)
        // the grating and the tray hide what is under them
        XCTAssertEqual(count("WIPEOUT", "TC-PV-WALKWAY"), panels)
        // the detail sheet, once, to the right of the plan
        let detail = recs.filter { $0.first?.1 == "INSERT" && t.value($0, "2") == "TC_DETAIL_WALKWAY" }
        XCTAssertEqual(detail.count, 1)
        // no walkway: none of it
        let none = RoofDXF.build(roof(every: 0), parts: [.pv])
        XCTAssertFalse(none.layers.contains("TC-PV-WALKWAY")); XCTAssertFalse(none.layers.contains("TC-DETAIL"))
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
        XCTAssertTrue(body.contains("TC-DETAIL"))
    }
}

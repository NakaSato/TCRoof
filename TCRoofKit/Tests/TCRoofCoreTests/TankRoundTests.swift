import XCTest
@testable import TCRoofCore

/// Round tanks (`tankShape` = round, `tankDiameter`): the size and its summary, the plan, the openings kept inside the
/// circle, the sections, the panel layout clipped to the circle less its setback, the shade and the DXF.
final class TankRoundTests: XCTestCase {
    func texts(_ s: Sketch) -> [String] { s.ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { return t }; return nil } }

    func round(_ d: Double, height: Double? = 5, points: Bool = false) -> Values {
        var v = Values()
        Tank.setShape(&v, .round)
        Tank.setDiameter(&v, d)
        if let height { Tank.setHeight(&v, height) }
        if points { TankPoints.seed(&v) }
        return v
    }

    // MARK: size

    func testShapeAndDiameterWriteTheLegacySpans() {
        var v = round(30)
        XCTAssertTrue(Tank.isRound(v))
        XCTAssertEqual(Tank.diameter(v), 30)
        XCTAssertEqual(v.text(Roof.Key.spansX), "30"); XCTAssertEqual(v.text(Roof.Key.spansY), "30")
        XCTAssertEqual(Tank.spans(v).x, [30]); XCTAssertEqual(Tank.spans(v).y, [30])
        XCTAssertEqual(TankPoints.tankSize(v)?.w, 30)
        XCTAssertEqual(Tank.sizeLabel(v)?.name, "Ø 30 ม."); XCTAssertEqual(Tank.sizeLabel(v)?.sub, "ถังกลม")
        XCTAssertEqual(Tank.sizeText(v), "Ø 30 ม.")
        XCTAssertNil(Tank.preset(v), "presets are rectangular")
        // the diameter has a floor; clearing it clears the size
        Tank.setDiameter(&v, 0.5)
        XCTAssertEqual(Tank.diameter(v), Tank.minDiameter)
        Tank.setDiameter(&v, nil)
        XCTAssertNil(Tank.diameter(v)); XCTAssertFalse(Tank.hasSize(v)); XCTAssertNil(v[Roof.Key.spansX])
        XCTAssertTrue(TankDesign.ranked(v).isEmpty, "the standard designs are rectangular")
    }

    func testSwitchingShapeTakesTheNarrowSideAndBack() {
        var v = Values()
        Tank.apply(&v, Tank.presets[1])          // 64 × 40
        TankPoints.seed(&v)
        Tank.setShape(&v, .round)
        XCTAssertEqual(Tank.diameter(v), 40)
        XCTAssertTrue(TankPoints.points(v).isEmpty, "points only seeded are cleared for the round layout")
        XCTAssertTrue(TankPoints.seed(&v))
        XCTAssertEqual(TankPoints.points(v).count, TankPoints.roundLayout.count)
        // a checked point stays when going back
        TankPoints.setStatus(&v, TankPoints.points(v)[0].id, TankPoints.ok)
        Tank.setShape(&v, .rect)
        XCTAssertFalse(Tank.isRound(v))
        XCTAssertEqual(Tank.sizeLabel(v)?.name, "40 × 40 ม.")
        XCTAssertEqual(TankPoints.points(v).count, TankPoints.roundLayout.count)
    }

    func testSummaryOfACircle() throws {
        // docs/specs/auto-drawing.md §11: circle D = 10, H = 5 → 392.7 m³
        let s = try XCTUnwrap(Tank.summary(round(10)))
        XCTAssertEqual(s.roofArea, Double.pi * 25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.grossVolume), 392.699, accuracy: 0.001)
        XCTAssertEqual(s.text, "Ø 10.00 × 5.00 ม. | หลังคา 79 ม² | ปริมาตรภายนอกโดยประมาณ 393 ม³")
        XCTAssertEqual(try XCTUnwrap(Tank.summary(round(30, height: nil))).text, "Ø 30.00 ม. | หลังคา 707 ม²")
    }

    func testSizeDoneAndCompletionCountTheDiameter() throws {
        var v = round(20)
        v["tankType"] = .choice("ค.ส.ล.", other: ""); Tank.setPosition(&v, Tank.above); v["surface"] = .text("คอนกรีต")
        XCTAssertTrue(Tank.sizeDone(v))
        var rect = Values()
        Tank.apply(&rect, Tank.presets[3])
        rect["tankType"] = v["tankType"]; Tank.setHeight(&rect, 5); Tank.setPosition(&rect, Tank.above); rect["surface"] = v["surface"]
        let m = SurveyModule(type: .tank, values: v), r = SurveyModule(type: .tank, values: rect)
        XCTAssertEqual(m.completion, r.completion, "a diameter fills the plan group as the spans do")
    }

    func testOldAndRoundJSONDecode() throws {
        // a tank saved before round tanks: no tankShape, so a rectangle as before
        let old = #"""
        {"id":"6F1C3B8E-1D0A-4B8C-9E61-0D7A0D9E1A11","type":"tank","name":"1",
         "values":{"storage":{"spansX":{"text":{"_0":"4,4,4,4"}},"spansY":{"text":{"_0":"4,4"}}}}}
        """#
        let a = try JSONDecoder().decode(SurveyModule.self, from: Data(old.utf8))
        XCTAssertFalse(Tank.isRound(a.values)); XCTAssertNil(Tank.diameter(a.values))
        XCTAssertEqual(Tank.sizeLabel(a.values)?.name, "16 × 8 ม.")
        // a stray diameter on a rectangle is ignored
        var b = a
        b.values[Tank.Key.diameter] = .text("12")
        XCTAssertEqual(Tank.spans(b.values).x, [4, 4, 4, 4])
        // a round one round-trips
        let m = SurveyModule(type: .tank, values: round(18))
        let back = try JSONDecoder().decode(SurveyModule.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
        XCTAssertEqual(Tank.diameter(back.values), 18)
    }

    // MARK: points

    func testSeededPointsAreInsideTheCircle() {
        for d in [6.0, 12, 30, 50] {
            let v = round(d, points: true), c = TankPoints.Circle(diameter: d)
            for o in TankPoints.points(v) {
                let r = TankPoints.rect(o)!
                XCTAssertTrue(c.contains(r), "\(o.label) of Ø \(d)")
                XCTAssertFalse(TankPoints.check(v, o.id)!.outside)
            }
        }
    }

    func testMovesAndDropsStayInsideAndWallPointsOnTheRim() throws {
        var v = round(20, points: true)
        let c = TankPoints.Circle(diameter: 20), id = TankPoints.points(v)[1].id
        // a corner of the bounding square is outside the circle: the point is pulled in along its radius
        TankPoints.move(&v, id, x: 0, y: 0)
        let r = try XCTUnwrap(TankPoints.rect(TankPoints.points(v).first { $0.id == id }!))
        XCTAssertTrue(c.contains(r))
        XCTAssertLessThan(c.clearance(r), 0.1, "pulled in only as far as needed")
        XCTAssertLessThan(r.cx, 10); XCTAssertLessThan(r.cy, 10)
        for (x, y) in [(19.0, 0.0), (19, 19), (0, 19), (10, -5), (25, 10)] {
            let d = try XCTUnwrap(TankPoints.drop(v, id, x: x, y: y))
            XCTAssertTrue(c.contains(TankPoints.Rect(x: d.x, y: d.y, w: r.w, h: r.h)), "drop at \(x), \(y)")
        }
        // a ladder added on site goes to the rim and slides along it
        let ladder = try XCTUnwrap(TankPoints.add(&v, kind: TankPoints.ladder))
        let l0 = try XCTUnwrap(TankPoints.rect(TankPoints.points(v).first { $0.id == ladder }!))
        XCTAssertTrue(c.contains(l0)); XCTAssertLessThan(c.clearance(l0), 0.1)
        let d = try XCTUnwrap(TankPoints.drop(v, ladder, x: 18, y: 9.7))
        let l1 = TankPoints.Rect(x: d.x, y: d.y, w: l0.w, h: l0.h)
        XCTAssertTrue(c.contains(l1)); XCTAssertLessThan(c.clearance(l1), 0.1)
        XCTAssertGreaterThan(l1.cx, 15, "on the right of the rim")
        XCTAssertEqual(TankPoints.outward(l1, in: v).x, 1, accuracy: 0.05)
        // a point typed outside is flagged by the live check
        var list = TankPoints.points(v)
        list[0].x = "0"; list[0].y = "0"
        v[Roof.Key.obstacles] = .obstacles(list)
        XCTAssertTrue(TankPoints.check(v, list[0].id)!.outside)
        // a row of copies stops at the rim
        let ids = TankPoints.repeatRow(&v, TankPoints.points(v)[2].id, count: 10, spacing: 4)
        for i in ids { XCTAssertTrue(c.contains(TankPoints.rect(TankPoints.points(v).first { $0.id == i }!)!)) }
        XCTAssertLessThan(ids.count, 10)
    }

    // MARK: drawings

    func testPlanDrawsTheCircleCentreLinesAndDiameter() throws {
        var v = round(30, points: true)
        v["tankType"] = .choice("ค.ส.ล.", other: "")
        Tank.setAzimuth(&v, 12, source: .manual)
        let ladder = try XCTUnwrap(TankPoints.add(&v, kind: TankPoints.ladder))
        _ = ladder
        let screen = try XCTUnwrap(TankPlan(v, chips: true, hints: true)), sheet = try XCTUnwrap(TankPlan(v, details: true))
        XCTAssertTrue(screen.chips.isEmpty, "no spans to tap on a round tank")
        XCTAssertEqual(sheet.tags.count, sheet.sketch.ops.count)
        let rims = sheet.sketch.ops.enumerated().filter { i, op in if case .circle = op { return sheet.tags[i] == "out" }; return false }
        XCTAssertEqual(rims.count, 2, "a double rim")
        XCTAssertEqual(sheet.tags.filter { $0 == "grid" }.count, 2, "two centre lines")
        XCTAssertEqual(sheet.tags.filter { $0 == "beam" }.count, 0)
        let t = texts(sheet.sketch)
        XCTAssertTrue(t.contains("Ø 30.00"))
        XCTAssertTrue(t.contains("แปลนหลังคาถังน้ำใสทรงกลม Ø 30 ม."))
        XCTAssertTrue(t.contains("Ø 30.00 × 5.00 ม. | หลังคา 707 ม² | ปริมาตรภายนอกโดยประมาณ 3,534 ม³"))
        XCTAssertEqual(t.filter { $0 == "1" }.count, 2); XCTAssertEqual(t.filter { $0 == "2" }.count, 2)
        // the frame is the bounding square, and the PDF / Excel picture is the printed plan
        XCTAssertEqual(sheet.frame.k * 30, sheet.sketch.ops.compactMap { op -> Double? in if case let .circle(_, r, _, _, w) = op, w == 1.4 { return 2 * r }; return nil }.first!, accuracy: 1e-9)
        XCTAssertEqual(Drawings.plan(v, tank: true)?.ops.count, sheet.sketch.ops.count)
        XCTAssertNotNil(TankPlan.compact(v))
        XCTAssertNil(TankPlan(round(30, height: nil).removingDiameter))
    }

    func testSectionsAcrossTheDiameter() throws {
        let v = round(24)
        for across in [false, true] {
            let s = try XCTUnwrap(TankDrawings.section(v, across: across))
            let t = texts(s)
            XCTAssertTrue(t.contains { $0.contains("ตัดผ่านศูนย์กลาง") && $0.contains("Ø 24 ม.") })
            XCTAssertTrue(t.contains("Ø 24"))
            XCTAssertTrue(t.contains { $0.contains("ปริมาตรภายนอกโดยประมาณ 2,262 ม³") })
        }
    }

    func testDXFHasTheRimAndLayout() throws {
        var v = round(30, points: true)
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        let out = try XCTUnwrap(TankDXF.build(v))
        XCTAssertTrue(String(decoding: out.data, as: UTF8.self).contains("CIRCLE"))
        XCTAssertTrue(out.layers.contains("TC-TANK-OUTLINE")); XCTAssertTrue(out.layers.contains("TC-PV-TABLE"))
    }

    // MARK: layout

    func assertInside(_ l: TankLayout, _ d: Double, file: StaticString = #filePath, line: UInt = #line) {
        let c = TankPoints.Circle(diameter: d)
        XCTAssertGreaterThan(l.count, 0, file: file, line: line)
        for p in l.tables.flatMap(\.panels) {
            XCTAssertTrue(c.contains(TankPoints.Rect(x: p.x, y: p.y, w: p.w, h: p.h), margin: l.params.clearance), "panel \(p.key)", file: file, line: line)
        }
        for t in l.builtTables { for q in t.posts { XCTAssertTrue(c.contains(q.x, q.y, margin: l.params.footing / 2), file: file, line: line) } }
        XCTAssertTrue(l.checks.edgeOK, file: file, line: line)
        XCTAssertGreaterThanOrEqual(l.checks.edge ?? 0, l.params.clearance - 1e-6, file: file, line: line)
    }

    func testLayoutIsClippedToTheCircle() throws {
        let v = round(30, points: true)
        let l = try XCTUnwrap(TankLayout(v, params: TankLayout.auto(v)))
        XCTAssertNotNil(l.circle)
        assertInside(l, 30)
        XCTAssertTrue(l.checks.allOK)
        // fewer modules than the 30 × 30 square, and the rows get shorter towards the rim
        var square = Values()
        Tank.apply(&square, Tank.presets[2])
        let s = try XCTUnwrap(TankLayout(square, params: TankLayout.auto(square)))
        XCTAssertNil(s.circle)
        XCTAssertLessThan(l.count, s.count)
        let widths = Dictionary(grouping: l.builtTables, by: \.row).mapValues { $0.reduce(0) { $0 + $1.columns } }
        XCTAssertGreaterThan(widths.values.max()!, widths.values.min()!)
        // the max search keeps it inside and never does worse than the automatic layout
        let best = try XCTUnwrap(TankLayout.best(v))
        let b = try XCTUnwrap(TankLayout(v, params: best))
        assertInside(b, 30)
        XCTAssertGreaterThanOrEqual(b.count, l.count)
        // every quarter turn of the facing wall
        for az in [0, 90, 180, 270] {
            var t = v
            Tank.setAzimuth(&t, az, source: .manual)
            assertInside(try XCTUnwrap(TankLayout(t, params: TankLayout.auto(t))), 30)
        }
    }

    func testAHatchStillRemovesColumnsInACircle() throws {
        var v = round(30)
        let open = try XCTUnwrap(TankLayout(v, params: TankLayout.auto(v))).count
        v[Roof.Key.obstacles] = .obstacles([Obstacle(label: "H1", x: "14", y: "14", w: "1.15", h: "1.15", kind: TankPoints.hatch, origin: TankPoints.standard)])
        let l = try XCTUnwrap(TankLayout(v, params: TankLayout.auto(v)))
        XCTAssertLessThan(l.count, open)
        assertInside(l, 30)
    }

    func testShadeAndTrueSouthOnARoundTank() throws {
        var v = round(20, points: true)
        Tank.setAzimuth(&v, 12, source: .manual)
        v["shade"] = .choice("มี", other: ""); v["shadeFrom"] = .multi(["ต้นไม้"]); v["shadeDir"] = .multi(["S"])
        v[TankShade.Key.height] = .text("12"); v[TankShade.Key.distance] = .text("3")
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        let shade = try XCTUnwrap(TankShade(v, latitude: 14))
        XCTAssertGreaterThan(shade.energy, 0)
        XCTAssertGreaterThan(shade.objectLoss, 0, "trees beside the rim shade the south rows")
        // (the energy search is `best` per row gap, covered above; the true-south search keeps to the rim)
        let south = try XCTUnwrap(TankLayout.trueSouth(v, latitude: 14))
        let c = TankPoints.Circle(diameter: 20)
        XCTAssertGreaterThan(south.count, 0)
        for m in south.modules { for p in m.corners { XCTAssertTrue(c.contains(p.x, p.y, margin: 1 - 1e-6)) } }
    }
}

private extension Values {
    var removingDiameter: Values { var v = self; v[Tank.Key.diameter] = nil; return v }
}

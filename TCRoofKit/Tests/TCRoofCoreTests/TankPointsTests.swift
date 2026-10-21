import XCTest
@testable import TCRoofCore

/// D1 sub-step 2 "สิ่งกีดขวาง" (docs/ui/survey-d1-obstacles-iphone).
final class TankPointsTests: XCTestCase {
    func tank(_ p: Int = 0) -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[p])
        return v
    }
    func centre(_ o: Obstacle) -> (Double, Double) { let r = TankPoints.rect(o)!; return (r.cx, r.cy) }

    func testStandardLayoutOf40x40MatchesTheBoard() {
        let list = TankPoints.standardPoints(width: 40, height: 40)
        XCTAssertEqual(list.map(\.label), ["V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "H1", "H2", "H3", "H4", "H5"])
        XCTAssertEqual(list.filter { $0.kind == TankPoints.vent }.count, 10)
        XCTAssertEqual(list.filter { $0.kind == TankPoints.hatch }.count, 5)
        // centres as on the board (6 pt per metre from 30, 30)
        let expected: [(Double, Double)] = [(2, 2), (38, 2), (2, 20), (38, 20), (2, 38), (18, 38), (22, 38), (38, 38), (18, 20), (22, 20),
                                            (10, 1.2), (30, 1.2), (10, 38.8), (30, 38.8), (1.2, 24)]
        for (o, e) in zip(list, expected) {
            let c = centre(o)
            XCTAssertEqual(c.0, e.0, accuracy: 1e-9, o.label); XCTAssertEqual(c.1, e.1, accuracy: 1e-9, o.label)
        }
        // the กปภ. sheets' sizes: vents 1.45 m, hatches 1.15 m
        XCTAssertEqual(list[0].x, "1.275"); XCTAssertEqual(list[0].w, "1.45")
        XCTAssertEqual(list[10].x, "9.425"); XCTAssertEqual(list[10].y, "0.625"); XCTAssertEqual(list[10].w, "1.15")
        XCTAssertTrue(list.allSatisfy { $0.origin == TankPoints.standard && $0.status.isEmpty && $0.stdX == $0.x && $0.stdY == $0.y })
        XCTAssertFalse(list.contains(where: TankPoints.moved))
    }

    func testEveryPresetGetsFifteenPointsInsideTheTank() {
        for (i, p) in Tank.presets.enumerated() {
            var v = tank(i)
            XCTAssertTrue(TankPoints.seed(&v), p.name)
            let list = TankPoints.points(v), t = TankPoints.tankSize(v)!
            XCTAssertEqual(list.count, 15, p.name)
            for o in list {
                let r = TankPoints.rect(o)!
                XCTAssertTrue(r.x >= 0 && r.y >= 0 && r.x + r.w <= t.w && r.y + r.h <= t.h, "\(p.name) \(o.label)")
                XCTAssertEqual(TankPoints.check(v, o.id)?.overlaps, [], "\(p.name) \(o.label)")
            }
        }
    }

    func testSeedOnlyWithASizeAndNoObstacles() {
        var v = Values()
        XCTAssertFalse(TankPoints.seed(&v))
        v = tank()
        v[Roof.Key.obstacles] = .obstacles([Obstacle(label: "ท่อ", x: "1", y: "1", w: "1", h: "1")])
        XCTAssertFalse(TankPoints.seed(&v))
        XCTAssertEqual(TankPoints.points(v).count, 1)
        v = tank()
        XCTAssertTrue(TankPoints.seed(&v))
        XCTAssertFalse(TankPoints.seed(&v))
    }

    func testDoneWhenEveryStandardPointHasAStatus() {
        var v = tank()
        XCTAssertFalse(TankPoints.done(v))
        TankPoints.seed(&v)
        let ids = TankPoints.points(v).map(\.id)
        XCTAssertEqual(TankPoints.checked(v).n, 0); XCTAssertEqual(TankPoints.checked(v).total, 15)
        for id in ids.dropLast() { TankPoints.setStatus(&v, id, TankPoints.ok) }
        XCTAssertFalse(TankPoints.done(v))
        XCTAssertEqual(TankPoints.pending(v).map(\.label), ["H5"])
        TankPoints.setStatus(&v, ids.last!, TankPoints.absent)
        XCTAssertTrue(TankPoints.done(v))
        XCTAssertEqual(TankPoints.checked(v).n, 15)
        // an added point is found on site: already checked
        TankPoints.add(&v, kind: TankPoints.vent)
        XCTAssertTrue(TankPoints.done(v))
        XCTAssertEqual(TankPoints.checked(v).n, 16); XCTAssertEqual(TankPoints.checked(v).total, 16)
        // older obstacles alone never complete the sub-step
        var old = tank()
        old[Roof.Key.obstacles] = .obstacles([Obstacle(label: "ท่อ", x: "1", y: "1", w: "1", h: "1", status: TankPoints.ok)])
        XCTAssertFalse(TankPoints.done(old))
    }

    func testMoveSnapsClampsAndMarksMoved() {
        var v = tank()
        TankPoints.seed(&v)
        let v9 = TankPoints.points(v)[8]
        TankPoints.move(&v, v9.id, x: 16.81, y: nil)
        var o = TankPoints.points(v)[8]
        XCTAssertEqual(o.x, "16.8"); XCTAssertEqual(o.y, v9.y)
        XCTAssertTrue(TankPoints.moved(o))
        TankPoints.move(&v, v9.id, x: 50, y: -3)
        o = TankPoints.points(v)[8]
        XCTAssertEqual(o.x, "38.55"); XCTAssertEqual(o.y, "0")
        TankPoints.move(&v, v9.id, x: 17.275, y: 19.275)
        XCTAssertFalse(TankPoints.moved(TankPoints.points(v)[8]))
    }

    func testDropTakesAnotherPointsRowAndColumn() {
        var v = tank()
        TankPoints.seed(&v)
        let list = TankPoints.points(v), v9 = list[8]
        // near V6's column (centre 18) and V10's row (centre 20): both taken, with guides
        let d = TankPoints.drop(v, v9.id, x: 17.4, y: 19.45)!
        XCTAssertEqual(d.x, 17.275, accuracy: 1e-9); XCTAssertEqual(d.y, 19.275, accuracy: 1e-9)
        XCTAssertEqual(d.guideX!, 18, accuracy: 1e-9); XCTAssertEqual(d.guideY!, 20, accuracy: 1e-9)
        // far from any line: only the 2.5 cm grid
        let e = TankPoints.drop(v, v9.id, x: 14.123, y: 12.41)!
        XCTAssertEqual(e.x, 14.125, accuracy: 1e-9); XCTAssertEqual(e.y, 12.4, accuracy: 1e-9)
        XCTAssertNil(e.guideX); XCTAssertNil(e.guideY)
        // kept inside
        let f = TankPoints.drop(v, v9.id, x: -5, y: 45)!
        XCTAssertEqual(f.x, 0); XCTAssertEqual(f.y, 38.55, accuracy: 1e-9)
    }

    func testCheckLine() {
        var v = tank()
        TankPoints.seed(&v)
        let list = TankPoints.points(v)
        var c = TankPoints.check(v, list[8].id)!
        XCTAssertEqual(c.aligned.first, "V10")
        XCTAssertEqual(c.text, "แนวเดียวกับ V10, V3 | ไม่ทับจุดอื่น")
        XCTAssertFalse(c.warning)
        TankPoints.move(&v, list[8].id, x: list[9].x.isEmpty ? 0 : Double(list[9].x)! - 0.3, y: Double(list[9].y)!)
        c = TankPoints.check(v, list[8].id)!
        XCTAssertEqual(c.overlaps, ["V10"])
        XCTAssertTrue(c.warning)
        XCTAssertTrue(c.text.hasSuffix("ทับ V10"))
        // absent points don't count
        TankPoints.setStatus(&v, list[9].id, TankPoints.absent)
        XCTAssertEqual(TankPoints.check(v, list[8].id)?.overlaps, [])
        // shrinking the tank leaves a point outside
        Tank.apply(&v, Tank.presets[3])
        XCTAssertTrue(TankPoints.check(v, list[1].id)!.outside)
        XCTAssertTrue(TankPoints.check(v, list[1].id)!.text.hasPrefix("อยู่นอกถัง"))
    }

    func testAddRepeatAndDelete() {
        var v = tank()
        TankPoints.seed(&v)
        let a = TankPoints.add(&v, kind: TankPoints.vent)!
        var o = TankPoints.points(v).last!
        XCTAssertEqual(o.id, a); XCTAssertEqual(o.label, "V11"); XCTAssertEqual(o.origin, TankPoints.added); XCTAssertEqual(o.status, TankPoints.ok)
        // the centre is between V9 and V10: it moves down clear of them and their labels
        XCTAssertEqual(centre(o).0, 20, accuracy: 1e-9); XCTAssertEqual(centre(o).1, 23, accuracy: 1e-9)
        // a second one moves down clear of the first
        TankPoints.add(&v, kind: TankPoints.vent)
        o = TankPoints.points(v).last!
        XCTAssertEqual(o.label, "V12"); XCTAssertEqual(centre(o).1, 26, accuracy: 1e-9)
        // an empty tank: right at the centre
        var e = tank()
        TankPoints.add(&e, kind: TankPoints.vent)
        XCTAssertEqual(centre(TankPoints.points(e)[0]).1, 20, accuracy: 1e-9)
        let h = TankPoints.add(&v, kind: TankPoints.hatch)!
        XCTAssertEqual(TankPoints.points(v).first { $0.id == h }?.label, "H6")
        XCTAssertEqual(TankPoints.points(v).first { $0.id == h }?.w, "1.15")

        // repeat V8 (centre 38, 38) along its row: no room to the right
        XCTAssertEqual(TankPoints.repeatRow(&v, TankPoints.points(v)[7].id, count: 3, spacing: 4), [])
        // V5 (centre 2, 38): three copies 4 m apart
        let ids = TankPoints.repeatRow(&v, TankPoints.points(v)[4].id, count: 3, spacing: TankPoints.rowSpacing(v))
        XCTAssertEqual(ids.count, 3)
        let row = TankPoints.points(v).filter { ids.contains($0.id) }
        XCTAssertEqual(row.map(\.label), ["V13", "V14", "V15"])
        XCTAssertEqual(row.map(\.x), ["5.275", "9.275", "13.275"])
        XCTAssertTrue(row.allSatisfy { $0.y == "37.275" && $0.origin == TankPoints.added })

        // standard points can't be deleted, added ones can
        XCTAssertFalse(TankPoints.delete(&v, TankPoints.points(v)[0].id))
        XCTAssertTrue(TankPoints.delete(&v, a))
        XCTAssertNil(TankPoints.points(v).first { $0.id == a })
        XCTAssertEqual(TankPoints.points(v).count, 15 + 3 + 3 - 1)
    }

    func testAbsentPointsLeaveTheDrawingsButStayInTheList() {
        var v = tank()
        v["tankType"] = .choice("ค.ส.ล.", other: "")
        TankPoints.seed(&v)
        func hatches(_ s: Sketch) -> Int { s.ops.filter { if case .hatch = $0 { return true }; return false }.count }
        let all = hatches(TankPlan(v)!.sketch)
        XCTAssertEqual(all, 15)
        TankPoints.setStatus(&v, TankPoints.points(v)[0].id, TankPoints.absent)
        XCTAssertEqual(hatches(TankPlan(v)!.sketch), 14)
        XCTAssertEqual(hatches(Drawings.plan(v, tank: false)!), 14)
        XCTAssertEqual(TankPoints.points(v).count, 15)
        let spec = Schema.spec(.tank).fields.first { $0.id == "obst" }!
        XCTAssertTrue(spec.displayText(v).hasPrefix("V1 (ไม่มีจริง); V2 (1.45x1.45 ม. @37.275,1.275)"))
    }

    func testOldObstaclesDecodeAndRoundTrip() throws {
        let json = #"[{"id":"6F1C3B8E-1D0A-4B8C-9E61-0D7A0D9E1A11","label":"ช่องเซอร์วิส","x":"2","y":"3","w":"1","h":"1"},{"label":"แผ่นใส","kind":"sky","canCover":true}]"#
        let old = try JSONDecoder().decode([Obstacle].self, from: Data(json.utf8))
        XCTAssertEqual(old.count, 2)
        XCTAssertEqual(old[0].status, ""); XCTAssertEqual(old[0].origin, ""); XCTAssertEqual(old[0].stdX, ""); XCTAssertEqual(old[0].stdY, "")
        XCTAssertFalse(old[0].isAbsent); XCTAssertFalse(TankPoints.moved(old[0])); XCTAssertTrue(TankPoints.canDelete(old[0]))
        XCTAssertEqual(old[1].kind, "sky"); XCTAssertTrue(old[1].canCover)
        // a point without a size is drawn as a vent
        XCTAssertEqual(TankPoints.rect(Obstacle(x: "1", y: "1"))?.w, TankPoints.ventSize)

        var p = TankPoints.standardPoints(width: 40, height: 40)[8]
        p.status = TankPoints.absent
        let back = try JSONDecoder().decode(Obstacle.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)

        // the section counts as before: obstacles stay optional
        var v = tank()
        v["tankType"] = .choice("ค.ส.ล.", other: "")
        let m0 = SurveyModule(type: .tank, values: v)
        var m1 = m0
        TankPoints.seed(&m1.values)
        XCTAssertEqual(m1.completion.total, m0.completion.total)
    }
}

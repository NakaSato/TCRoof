import XCTest
@testable import TCRoofCore

/// The กปภ. standard tank designs (docs/specs/standard-designs.md, docs/specs/img/tank_plan.py).
final class TankDesignTests: XCTestCase {
    func sized(_ w: Int, _ h: Int) -> Values {
        var v = Values()
        Roof.setSpans(&v, .x, Array(repeating: 4, count: w / 4))
        Roof.setSpans(&v, .y, Array(repeating: 4, count: h / 4))
        return v
    }
    func centre(_ o: Obstacle) -> (Double, Double) { let r = TankPoints.rect(o)!; return (r.cx, r.cy) }

    func testTheSheetsCounts() {
        let big = TankDesign.pwa64x40.points(), small = TankDesign.pwa40x40.points()
        func count(_ l: [Obstacle], _ k: String) -> Int { l.filter { $0.kind == k }.count }
        XCTAssertEqual([count(big, "vent"), count(big, "hatch"), count(big, "ladder"), count(big, "pipe")], [20, 8, 6, 6])
        XCTAssertEqual([count(small, "vent"), count(small, "hatch"), count(small, "ladder"), count(small, "pipe")], [12, 6, 3, 0])
        XCTAssertEqual(big.map(\.label).prefix(3), ["V1", "V2", "V3"])
        XCTAssertEqual(big.last?.label, "P6")
        XCTAssertEqual(big.last?.note, "ท่อน้ำล้น Ø500 มม.")
        XCTAssertTrue((big + small).allSatisfy { $0.origin == TankPoints.standard && $0.status.isEmpty && !TankPoints.moved($0) })
    }

    func testPositionsAsOnTheSheet() {
        let l = TankDesign.pwa40x40.points()
        // vents in the middle of bays (row 0, columns 0, 4, 5, 9)
        XCTAssertEqual(centre(l[0]).0, 2, accuracy: 1e-9); XCTAssertEqual(centre(l[0]).1, 2, accuracy: 1e-9)
        XCTAssertEqual(centre(l[2]).0, 22, accuracy: 1e-9)
        XCTAssertEqual(centre(l[11]).1, 38, accuracy: 1e-9)
        // hatch H1 on the top wall 10.20 along, 0.15 in
        let h1 = l.first { $0.label == "H1" }!, r = TankPoints.rect(h1)!
        XCTAssertEqual(r.cx, 10.2, accuracy: 0.03); XCTAssertEqual(r.y, 0.15, accuracy: 0.03)
        // ladders stand on their wall
        for o in l where o.kind == TankPoints.ladder {
            let q = TankPoints.rect(o)!
            XCTAssertTrue(q.x == 0 || abs(q.x + q.w - 40) < 1e-6, o.label)
        }
    }

    func testEveryPointInsideTheTankBothWays() {
        for d in TankDesign.all {
            for turned in [false, true] {
                let (W, H) = turned ? (d.height, d.width) : (d.width, d.height)
                for o in d.points(turned: turned) {
                    let r = TankPoints.rect(o)!
                    XCTAssertTrue(r.x >= -1e-6 && r.y >= -1e-6 && r.x + r.w <= W + 1e-6 && r.y + r.h <= H + 1e-6, "\(d.id) \(turned) \(o.label)")
                }
            }
        }
    }

    func testRankingByMeasuredSizeAndTurn() {
        var m = TankDesign.ranked(sized(40, 40))
        XCTAssertEqual(m.first?.design.id, "pwa-40x40")
        XCTAssertEqual(m.first?.line, "ตรงกับขนาดที่วัด")
        XCTAssertEqual(m.last?.line, "ต่างจากที่วัด 24 ม.")
        m = TankDesign.ranked(sized(40, 64))
        XCTAssertEqual(m.first?.design.id, "pwa-64x40")
        XCTAssertEqual(m.first?.turned, true)
        XCTAssertTrue(m.first?.matches == true)
        // within 0.50 m in all
        var v = Values()
        Roof.setSpans(&v, .x, Array(repeating: 4, count: 9) + [4.3])
        Roof.setSpans(&v, .y, Array(repeating: 4, count: 9) + [3.9])
        XCTAssertTrue(TankDesign.ranked(v).first!.matches)
        Roof.setSpans(&v, .y, Array(repeating: 4, count: 9) + [3.7])
        XCTAssertFalse(TankDesign.ranked(v).first!.matches)
        // no size: listed, no line
        XCTAssertNil(TankDesign.ranked(Values()).first?.line)
    }

    func testApplyWritesBaysPointsAndDesign() {
        var v = Values()
        TankDesign.apply(&v, .pwa64x40, turned: true)
        let t = TankPoints.tankSize(v)!
        XCTAssertEqual(t.w, 40); XCTAssertEqual(t.h, 64)
        XCTAssertEqual(TankPoints.points(v).count, 40)
        XCTAssertEqual(TankDesign.current(v)?.design.id, "pwa-64x40")
        XCTAssertEqual(TankDesign.current(v)?.turned, true)
        // the generic seed forgets the design
        v[Roof.Key.obstacles] = nil
        XCTAssertTrue(TankPoints.seed(&v))
        XCTAssertNil(TankDesign.current(v))
    }

    func testWallItemsSlideAlongTheirWallAndOverlapNothing() {
        var v = Values()
        TankDesign.apply(&v, .pwa64x40)
        let list = TankPoints.points(v), l1 = list.first { $0.label == "L1" }!   // top wall, 14.30 along, on hatch H1
        XCTAssertEqual(TankPoints.check(v, l1.id)?.overlaps, [])
        let d = TankPoints.drop(v, l1.id, x: 20, y: 9)!
        XCTAssertEqual(d.y, 0); XCTAssertEqual(d.x, 20, accuracy: 1e-9)
        XCTAssertNil(d.guideY)
        let p1 = list.first { $0.label == "P1" }!                                // left wall
        XCTAssertEqual(TankPoints.drop(v, p1.id, x: 7, y: 10.03)!.x, 0)
    }

    func testWallItemsTakeNoRoomFromThePanels() {
        var v = Values()
        TankDesign.apply(&v, .pwa40x40)
        XCTAssertEqual(TankLayout.openings(v).count, 18)
    }

    func testSummaryOfTheDemo() {
        var v = Values()
        TankDesign.apply(&v, .pwa40x40)
        var list = TankPoints.points(v)
        TankPoints.setStatus(&v, list[0].id, TankPoints.ok)
        TankPoints.setStatus(&v, list[5].id, TankPoints.absent)
        TankPoints.move(&v, list[2].id, x: 17.7, y: nil)
        TankPoints.setStatus(&v, list[2].id, TankPoints.ok)
        let id = TankPoints.add(&v, kind: TankPoints.ladder)!
        list = TankPoints.points(v)
        let s = TankDesign.summary(v)!
        XCTAssertEqual(s.design, "ถังน้ำใส 40×40 (ช่องระบายแบบเห็ด)")
        XCTAssertEqual([s.matches, s.moved, s.absent, s.added, s.open], [1, 1, 1, 1, 18])
        XCTAssertEqual(s.counts, "ตรงแบบ 1 · ย้าย 1 · ไม่มีจริง 1 · เพิ่มหน้างาน 1 · ยังไม่ตรวจ 18")
        XCTAssertEqual(s.differences[0], "V3 ย้าย 4.00 ม. (21.70, 1.70 → 17.70, 1.70)")
        XCTAssertEqual(s.differences[1], "V6 ไม่มีจริง")
        XCTAssertTrue(s.differences[2].hasPrefix("L4 เพิ่มหน้างาน"), s.differences[2])
        XCTAssertEqual(list.last?.id, id)
    }

    func testOldObstaclesHaveNoSummaryAndNoteDecodes() throws {
        var v = Values()
        v[Roof.Key.obstacles] = .obstacles([Obstacle(label: "ท่อ", x: "1", y: "1", w: "1", h: "1")])
        XCTAssertNil(TankDesign.summary(v))
        let old = try JSONDecoder().decode(Obstacle.self, from: Data(#"{"label":"V1","x":"1","y":"2"}"#.utf8))
        XCTAssertEqual(old.note, "")
    }
}

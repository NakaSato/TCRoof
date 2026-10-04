import XCTest
@testable import TCRoofCore

/// D1 sub-step 3 "จัดแผง" (docs/ui/survey-d1-layout-iphone) after the tank-roof standard (docs/specs/tank-mounting-layout.md).
final class TankLayoutTests: XCTestCase {
    func tank(_ p: Int = 0, points: Bool = true) -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[p])
        if points { TankPoints.seed(&v) }
        return v
    }
    func params(x: Double = 0, y: Double = 0) -> TankLayout.Params {
        var p = TankLayout.defaults(); p.offX = x; p.offY = y
        return p
    }
    func with(_ obstacles: [Obstacle]) -> Values {
        var v = tank(points: false)
        v[Roof.Key.obstacles] = .obstacles(obstacles)
        return v
    }

    func testStandardGeometry() {
        let p = TankLayout.Params()
        XCTAssertEqual(p.tilt, 19.65, accuracy: 0.01)
        XCTAssertEqual(p.depth, 4.31, accuracy: 0.01)
        XCTAssertEqual(p.rowPitch, 5.5, accuracy: 1e-9)
        XCTAssertEqual(p.frontIn, 0.433, accuracy: 0.001)
    }

    func testEmptyFortyByForty() {
        // 32 columns across 38 m, 7 rows from the south setback, one table per row
        let v = tank(points: false), l = TankLayout(v, params: TankLayout.auto(v))!
        XCTAssertEqual(l.rows, 7)
        XCTAssertEqual(l.builtTables.map(\.columns), Array(repeating: 32, count: 7))
        XCTAssertEqual(l.count, 448)
        XCTAssertEqual(l.kWp, 448 * l.params.moduleKW, accuracy: 1e-9)
        XCTAssertTrue(l.checks.allOK)
        XCTAssertEqual(l.cuts.count, 0)
        // the lowest row's lower edge is on the south setback; the columns are centred
        let low = l.tables.flatMap(\.panels).map { $0.y + $0.h }.max()!
        XCTAssertEqual(low, 39, accuracy: 1e-6)
        let xs = l.tables.flatMap(\.panels).map(\.x), xe = l.tables.flatMap(\.panels).map { $0.x + $0.w }
        XCTAssertEqual(xs.min()!, 40 - xe.max()!, accuracy: 0.05)
        XCTAssertNil(TankLayout(Values(), params: params()))
    }

    func testClearanceKeptAtEveryOffset() {
        let v = tank()
        let r = TankLayout.offsetRange(v, params())
        for (x, y) in [(0.0, 0.0), (r.x, r.y), (r.x / 2, r.y / 3)] {
            let l = TankLayout(v, params: params(x: x, y: y))!
            for p in l.tables.flatMap(\.panels) {
                XCTAssertGreaterThanOrEqual(p.x, 1 - 1e-6); XCTAssertGreaterThanOrEqual(p.y, 1 - 1e-6)
                XCTAssertLessThanOrEqual(p.x + p.w, 39 + 1e-6); XCTAssertLessThanOrEqual(p.y + p.h, 39 + 1e-6)
            }
            XCTAssertTrue(l.checks.edgeOK)
        }
    }

    func testAHatchRemovesTheColumnsItCovers() {
        // a 0.8 m hatch in the lowest row (y 34.69…39): grown by 0.5 m it spans x 19.5…21.3
        let v = with([Obstacle(label: "H1", x: "20", y: "36", w: "0.8", h: "0.8", kind: TankPoints.hatch)])
        let p = TankLayout.auto(v), l = TankLayout(v, params: p)!
        let row0 = l.tables.filter { $0.row == 0 }
        XCTAssertEqual(row0.count, 2)
        let x0 = 1 + p.offX
        let blocked = (0..<32).filter { c in
            let cx = x0 + Double(c) * (p.cellW + p.moduleGap)
            return cx < 21.3 && cx + p.cellW > 19.5
        }
        XCTAssertEqual(row0.map(\.columns).reduce(0, +) + l.cuts.count, 32 - blocked.count)
        XCTAssertTrue(l.tables.filter { $0.row > 0 }.allSatisfy { $0.columns == 32 })
    }

    func testVentUnderTheBackHalfStaysUnderTheFrontEdgeRemovesColumns() {
        // lowest row: upper edge 34.69, front posts at 38.57, lower edge 39
        let back = with([Obstacle(label: "V1", x: "20", y: "35", w: "0.6", h: "0.6", kind: TankPoints.vent)])
        let lb = TankLayout(back, params: TankLayout.auto(back))!
        XCTAssertEqual(lb.checks.ventsUnder, 1)
        XCTAssertGreaterThanOrEqual(lb.checks.ventHeadroom!, 0.1)
        XCTAssertTrue(lb.checks.ventsOK)
        let front = with([Obstacle(label: "V1", x: "20", y: "38.2", w: "0.6", h: "0.6", kind: TankPoints.vent)])
        let lf = TankLayout(front, params: TankLayout.auto(front))!
        XCTAssertEqual(lf.checks.ventsUnder, 0)
        XCTAssertLessThan(lf.tables.filter { $0.row == 0 }.map(\.columns).reduce(0, +), 32)
    }

    func testPostsNeverOnAnOpeningAndBaysWithinTheStandard() {
        for i in Tank.presets.indices {
            let v = tank(i), l = TankLayout(v, params: TankLayout.auto(v))!
            let open = TankPoints.points(v).compactMap(TankPoints.rect)
            for tb in l.builtTables {
                XCTAssertGreaterThanOrEqual(tb.pairs, 2)
                for pt in tb.posts {
                    for r in open {
                        let d = max(r.x - pt.x, 0, pt.x - (r.x + r.w), r.y - pt.y, pt.y - (r.y + r.h))
                        XCTAssertGreaterThanOrEqual(d, 0.45 - 1e-6, "\(Tank.presets[i].name) post on an opening")
                    }
                }
                // pairs at most postDX apart, the end ones within maxCantilever of the table's ends
                // a pair's front and back posts share the coordinate along the row
                let alongX = abs(tb.posts[0].x - tb.posts[1].x) < 1e-6
                let along = alongX ? tb.posts.map(\.x) : tb.posts.map(\.y)
                let xs = Array(Set(along.map { ($0 * 1000).rounded() / 1000 })).sorted()
                for (a, b) in zip(xs, xs.dropFirst()) { XCTAssertLessThanOrEqual(b - a, l.params.postDX + 1e-6) }
                let a0 = alongX ? tb.x : tb.y, a1 = a0 + (alongX ? tb.w : tb.h)
                XCTAssertLessThanOrEqual(xs.first! - a0, l.params.maxCantilever + 1e-6)
                XCTAssertLessThanOrEqual(a1 - xs.last!, l.params.maxCantilever + 1e-6)
            }
            XCTAssertTrue(l.checks.allOK, "\(Tank.presets[i].name) \(l.checks)")
        }
    }

    func testStandardPointsOfFortyByForty() {
        // the spec's prototype on its own 40 × 40 fixture: 7 rows, 13 tables, 394–404 modules
        let v = tank(), l = TankLayout(v, params: TankLayout.auto(v))!
        XCTAssertEqual(l.rows, 7)
        XCTAssertEqual(l.builtTables.count, 13)
        XCTAssertEqual(l.count, 410)
        XCTAssertEqual(l.checks.ventsUnder, 6)
        XCTAssertEqual(l.checks.cutColumns, 2)
        XCTAssertEqual(l.cuts.count, 2)
    }

    func testBOMRulesPerTable() {
        let q = TankLayout.TableBOM(columns: 6, length: 6.904, pairs: 4)
        XCTAssertEqual(q.modules, 12); XCTAssertEqual(q.posts, 8); XCTAssertEqual(q.footings, 8); XCTAssertEqual(q.rafters, 4)
        XCTAssertEqual(q.railLength, 4 * 6.904, accuracy: 1e-9); XCTAssertEqual(q.railClamps, 16)
        XCTAssertEqual(q.midClamps, 20); XCTAssertEqual(q.endClamps, 8); XCTAssertEqual(q.braces, 6); XCTAssertEqual(q.groundLugs, 1)
        let none = TankLayout.TableBOM(columns: 0, length: 0, pairs: 0)
        XCTAssertEqual(none.posts, 0); XCTAssertEqual(none.endClamps, 0); XCTAssertEqual(none.groundLugs, 0); XCTAssertEqual(none.braces, 0)
        let v = tank(), l = TankLayout(v, params: TankLayout.auto(v))!
        let sum = l.builtTables.map { TankLayout.TableBOM(columns: $0.columns, length: l.params.width($0.columns), pairs: $0.pairs) }
        XCTAssertEqual(l.bom.posts, sum.map(\.posts).reduce(0, +))
        XCTAssertEqual(l.bom.midClamps, sum.map(\.midClamps).reduce(0, +))
        XCTAssertEqual(l.bom.braces, sum.map(\.braces).reduce(0, +))
        XCTAssertEqual(l.bom.groundLugs, l.builtTables.count)
        XCTAssertEqual(l.bom.railLength, sum.map(\.railLength).reduce(0, +), accuracy: 1e-6)
    }

    func testMaxSearch() {
        let v = tank(), best = TankLayout.best(v)!, n = TankLayout(v, params: best)!.count
        XCTAssertGreaterThanOrEqual(n, TankLayout(v, params: TankLayout.auto(v))!.count)
        let r = TankLayout.offsetRange(v, params())
        for (x, y) in [(0.0, 0.0), (r.x, 0), (0, r.y), (r.x / 2, r.y / 2)] {
            XCTAssertGreaterThanOrEqual(n, TankLayout(v, params: params(x: TankLayout.snap(x), y: TankLayout.snap(y)))!.count)
        }
        XCTAssertEqual(best.offX, TankLayout.snap(best.offX)); XCTAssertEqual(best.offY, TankLayout.snap(best.offY))
    }

    func testMeasuredVentHeight() {
        var v = tank()
        XCTAssertNil(Tank.ventHeight(v))
        let before = TankLayout(v, params: TankLayout.auto(v))!
        XCTAssertEqual(before.params.ventH, 1)
        // vents 3 m high: none fits under the panels (the underside is at most 2 m), their columns go
        Tank.setVentHeight(&v, 3)
        XCTAssertEqual(Tank.ventHeight(v), 3)
        let tall = TankLayout(v, params: TankLayout.auto(v))!
        XCTAssertEqual(tall.params.ventH, 3)
        XCTAssertEqual(tall.checks.ventsUnder, 0)
        XCTAssertLessThan(tall.count, before.count)
        // a stored layout reads the height too
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        XCTAssertEqual(TankLayout.current(v)!.count, tall.count)
        // low vents: no fewer modules than the default
        Tank.setVentHeight(&v, 0.4)
        XCTAssertGreaterThanOrEqual(TankLayout(v, params: TankLayout.auto(v))!.count, before.count)
        Tank.setVentHeight(&v, -1); XCTAssertEqual(Tank.ventHeight(v), 0)
        Tank.setVentHeight(&v, nil); XCTAssertNil(Tank.ventHeight(v))
    }

    func testRowsFaceTheWallNearestSouth() {
        var v = tank(points: false)
        XCTAssertEqual(TankLayout.turn(v), 0)
        Tank.setAzimuth(&v, 12, source: .manual)
        XCTAssertEqual(TankLayout.turn(v), 0)
        // the top wall faces east: the right wall faces south, rows run north–south
        Tank.setAzimuth(&v, 90, source: .manual)
        XCTAssertEqual(TankLayout.turn(v), 1)
        Tank.apply(&v, Tank.presets[1])
        let l = TankLayout(v, params: TankLayout.auto(v))!
        XCTAssertTrue(l.builtTables.allSatisfy { $0.h > $0.w })
        XCTAssertEqual(l.tables.flatMap(\.panels).map { $0.x + $0.w }.max()!, 63, accuracy: 1e-6)
        Tank.setAzimuth(&v, 180, source: .manual)
        XCTAssertEqual(TankLayout.turn(v), 2)
        Tank.setAzimuth(&v, 270, source: .manual)
        XCTAssertEqual(TankLayout.turn(v), 3)
    }

    func testSaveToggleRemoveAndCompletion() {
        var v = tank()
        XCTAssertNil(TankLayout.current(v))
        XCTAssertFalse(TankLayout.done(v))
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        let l = TankLayout.current(v)!
        XCTAssertEqual(v.text("panelsBefore"), String(l.count))
        XCTAssertTrue(TankLayout.done(v))
        let key = l.tables[0].panels[0].key
        TankLayout.toggle(&v, key)
        XCTAssertEqual(TankLayout.off(v), [key])
        XCTAssertEqual(v.text("panelsBefore"), String(l.count - 1))
        TankLayout.toggle(&v, key)
        XCTAssertEqual(TankLayout.off(v), [])
        let t = l.tables[1]
        TankLayout.removeTable(&v, row: t.row, index: t.index)
        let after = TankLayout.current(v)!
        XCTAssertEqual(after.count, l.count - t.count)
        XCTAssertEqual(after.builtTables.count, l.builtTables.count - 1)
        XCTAssertEqual(after.bom.groundLugs, l.bom.groundLugs - 1)
        // every table removed: nothing to build, the legs check fails
        for tb in after.builtTables { TankLayout.removeTable(&v, row: tb.row, index: tb.index) }
        XCTAssertFalse(TankLayout.done(v))
        XCTAssertEqual(v.text("panelsBefore"), "0")
        XCTAssertEqual(TankLayout.params(v)!.offX, TankLayout.auto(tank()).offX)
    }

    func testCompletionCountsAsBefore() {
        var v = tank()
        v["tankType"] = .choice("ค.ส.ล.", other: "")
        let m0 = SurveyModule(type: .tank, values: v)
        var m1 = m0
        TankLayout.save(&m1.values, TankLayout.auto(v), off: ["0.0.0.0"])
        // only panelsBefore changes the count, as when typed on the form
        m1.values["panelsBefore"] = nil
        XCTAssertEqual(m1.completion, m0.completion)
    }
}

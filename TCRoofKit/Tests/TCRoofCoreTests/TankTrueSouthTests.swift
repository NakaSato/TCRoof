import XCTest
@testable import TCRoofCore

/// The true-south comparison (docs/specs/tank-mounting-layout.md §3a, comparison only).
final class TankTrueSouthTests: XCTestCase {
    func tank(points: Bool = true, azimuth: Int?) -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        if points { TankPoints.seed(&v) }
        if let a = azimuth { v[Tank.Key.azimuth] = .text(String(a)) }
        return v
    }

    func testOnlyComparedWhenTheWallIsOffSouth() {
        XCTAssertFalse(TankLayout.comparesSouth(tank(azimuth: nil)))
        XCTAssertFalse(TankLayout.comparesSouth(tank(azimuth: 0)))
        XCTAssertFalse(TankLayout.comparesSouth(tank(azimuth: 90)))
        XCTAssertTrue(TankLayout.comparesSouth(tank(azimuth: 12)))
        XCTAssertEqual(TankLayout.wallOffset(tank(azimuth: 12))!, 12, accuracy: 1e-9)
        XCTAssertEqual(TankLayout.wallOffset(tank(azimuth: 200))!, 20, accuracy: 1e-9)
        XCTAssertNil(TankLayout.trueSouth(tank(azimuth: nil), latitude: 17))
    }

    /// Unturned, the turned frame's engine gives the wall layout's modules and posts.
    func testUnturnedItMatchesTheWallLayout() throws {
        for points in [false, true] {
            let v = tank(points: points, azimuth: 0)
            let p = TankLayout.auto(v)
            let wall = try XCTUnwrap(TankLayout(v, params: p))
            let g = TankLayout.SouthGeometry(size: TankPoints.tankSize(v)!, azimuth: 0, openings: TankLayout.openings(v), params: p)
            let (s, _) = g.layout(gap: p.rowGap, offX: p.clearance + p.offX, offY: p.clearance + p.offY, wallOffset: 0)
            XCTAssertEqual(s.count, wall.count, "points \(points)")
            XCTAssertEqual(s.posts.count, wall.bom.posts, "points \(points)")
            XCTAssertEqual(s.cutColumns, wall.checks.cutColumns)
            XCTAssertEqual(s.tables, wall.builtTables.count)
        }
    }

    /// The prototype on the กปภ. 40 × 40 tank at 17° N, top wall facing 12°: the turned layout keeps the setback and its
    /// legs clear of the openings, and it loses modules to the turned fit and makes less energy than following the walls.
    /// One test, so the true-south search runs once.
    func testTheTurnedLayoutAndFollowingTheWalls() throws {
        let v = tank(azimuth: 12), p = TankLayout.defaults(v)
        let s = try XCTUnwrap(TankLayout.trueSouth(v, latitude: 17))
        let t = TankPoints.tankSize(v)!
        XCTAssertGreaterThan(s.count, 0)
        for m in s.modules { for c in m.corners {
            XCTAssertTrue(c.x >= p.clearance - 1e-6 && c.x <= t.w - p.clearance + 1e-6 && c.y >= p.clearance - 1e-6 && c.y <= t.h - p.clearance + 1e-6)
        } }
        let rects = TankLayout.openings(v).map(\.rect)
        for pt in s.posts { for r in rects {
            XCTAssertGreaterThanOrEqual(max(r.x - pt.x, 0, pt.x - (r.x + r.w), r.y - pt.y, pt.y - (r.y + r.h)), p.legClear + p.footing / 2 - 1e-6)
        } }
        XCTAssertGreaterThanOrEqual(s.gap, 2.7 - 1e-9)
        XCTAssertGreaterThan(s.yield, 1000)

        // compareSouth is this comparison with the same search
        XCTAssertTrue(TankLayout.comparesSouth(v))
        let wall = try XCTUnwrap(TankLayout.bestEnergy(v, latitude: 17))
        let c = TankLayout.SouthComparison(wall: wall.chosen, south: s)
        XCTAssertLessThan(c.south.count, c.wall.modules)
        XCTAssertLessThan(c.south.mwh, c.wall.mwh)
        XCTAssertLessThan(c.change, 0)
        XCTAssertTrue(c.line.hasPrefix("หันทิศใต้จริง (หมุนแถว 12°): \(c.south.count) แผง"), c.line)
        XCTAssertTrue(c.line.contains("น้อยกว่า"))
    }
}

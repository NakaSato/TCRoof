import XCTest
@testable import TCRoofCore

/// D1 sub-step 2 on iPad (docs/ui/survey-d1-obstacles-ipad A4–A5): row / column groups, group moves, respacing, repeat.
final class TankPointsGroupTests: XCTestCase {
    /// A 40 × 40 m tank with the standard points.
    func tank() -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        TankPoints.seed(&v)
        return v
    }
    func id(_ v: Values, _ label: String) -> UUID { TankPoints.points(v).first { $0.label == label }!.id }
    func rect(_ v: Values, _ label: String) -> TankPoints.Rect { TankPoints.rect(TankPoints.points(v).first { $0.label == label }!)! }

    func testRowAndColumnMembership() {
        let v = tank()
        XCTAssertEqual(TankPoints.group(v, of: id(v, "V9"), mode: .row).map(\.label), ["V3", "V9", "V10", "V4"])
        XCTAssertEqual(TankPoints.group(v, of: id(v, "V9"), mode: .column).map(\.label), ["V9", "V6"])
        XCTAssertEqual(TankPoints.group(v, of: id(v, "V9"), mode: .single).map(\.label), ["V9"])
        // hatches aren't in a vent's row, and a point marked absent leaves it
        var w = v
        TankPoints.setStatus(&w, id(w, "V4"), TankPoints.absent)
        XCTAssertEqual(TankPoints.group(w, of: id(w, "V9"), mode: .row).map(\.label), ["V3", "V9", "V10"])
    }

    func testAGroupMoveKeepsRelativePositions() {
        var v = tank()
        let row = TankPoints.group(v, of: id(v, "V9"), mode: .row).map(\.id)
        let before = ["V3", "V9", "V10", "V4"].map { rect(v, $0) }
        let r = TankPoints.move(&v, group: row, dx: 0, dy: 1.5)
        XCTAssertFalse(r.clamped)
        for (label, b) in zip(["V3", "V9", "V10", "V4"], before) {
            XCTAssertEqual(rect(v, label).y, b.y + 1.5, accuracy: 1e-9, label)
            XCTAssertEqual(rect(v, label).x, b.x, accuracy: 1e-9, label)
        }
        XCTAssertEqual(rect(v, "V1").y, 1.275, accuracy: 1e-9, "points outside the group stay")
    }

    func testAGroupMoveStopsAtTheWall() {
        var v = tank()
        let row = TankPoints.group(v, of: id(v, "V9"), mode: .row).map(\.id)
        // V3 is 1.275 m from the left wall: a 3 m move left is cut to 1.275
        let r = TankPoints.move(&v, group: row, dx: -3, dy: 0)
        XCTAssertTrue(r.clamped)
        XCTAssertEqual(r.dx, -1.275, accuracy: 1e-9)
        XCTAssertEqual(rect(v, "V3").x, 0, accuracy: 1e-9)
        XCTAssertEqual(rect(v, "V9").x, 17.275 - 1.275, accuracy: 1e-9)
    }

    func testRespacingFromTheSelectedPoint() {
        var v = tank()
        let row = TankPoints.group(v, of: id(v, "V9"), mode: .row)
        XCTAssertEqual(TankPoints.spacing(v, group: row, mode: .row), 16, "gaps 16, 4, 16: the most common, then the larger")
        let clamped = TankPoints.respace(&v, group: row, from: id(v, "V9"), spacing: 4, mode: .row)
        XCTAssertEqual(clamped, 0)
        XCTAssertEqual(["V3", "V9", "V10", "V4"].map { rect(v, $0).cx }, [14, 18, 22, 26])
        XCTAssertEqual(TankPoints.spacing(v, group: TankPoints.group(v, of: id(v, "V9"), mode: .row), mode: .row), 4)
    }

    func testRespacingKeepsEveryPointInside() {
        var v = tank()
        let row = TankPoints.group(v, of: id(v, "V9"), mode: .row)
        // 12 m apart from V9 at 18: V3 would sit at 6, V10 at 30, V4 at 42 (outside), pulled back to the wall
        let clamped = TankPoints.respace(&v, group: row, from: id(v, "V9"), spacing: 12, mode: .row)
        XCTAssertEqual(clamped, 1)
        XCTAssertEqual(rect(v, "V4").x + rect(v, "V4").w, 40, accuracy: 1e-9)
    }

    func testRepeatDownSkipsCopiesOutsideTheTank() {
        var v = tank()
        // V9's centre is at 20 m: copies at 28 and 36 fit, 44 doesn't
        let ids = TankPoints.repeatPoint(&v, id(v, "V9"), count: 3, spacing: 8, down: true)
        XCTAssertEqual(ids.count, 2)
        let copies = TankPoints.points(v).filter { ids.contains($0.id) }
        XCTAssertEqual(copies.map(\.label), ["V11", "V12"])
        XCTAssertEqual(copies.compactMap(TankPoints.rect).map(\.cy), [28, 36])
        XCTAssertTrue(copies.allSatisfy { $0.origin == TankPoints.added && $0.status == TankPoints.ok })
        XCTAssertEqual(TankPoints.repeatPoint(&v, id(v, "V9"), count: 2, spacing: 4, down: false).count, 2, "to the right as before")
    }

    func testRestorePutsAMovedPointBack() {
        var v = tank()
        TankPoints.move(&v, id(v, "V9"), x: 15, y: 15)
        XCTAssertTrue(TankPoints.moved(TankPoints.points(v).first { $0.label == "V9" }!))
        TankPoints.restore(&v, id(v, "V9"))
        XCTAssertFalse(TankPoints.moved(TankPoints.points(v).first { $0.label == "V9" }!))
    }
}

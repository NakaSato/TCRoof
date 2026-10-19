import XCTest
@testable import TCRoofCore

/// D1's shade simulation (docs/specs/tank-drawing-swift.md, old step 4; tank-mounting-layout.md §3a step 4).
final class TankShadeTests: XCTestCase {
    func layout(points: Bool = false) -> TankLayout {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        if points { TankPoints.seed(&v) }
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        return TankLayout.current(v)!
    }

    func testRowsShadeALittleAndTheFrontRowNever() {
        let l = layout()
        let s = TankShade(layout: l, objects: [], azimuth: nil, exposed: 1.2, latitude: 17)
        // the standard 2.70 m gap costs about 2 % at 17° N (the prototype: 1.9 %)
        XCTAssertEqual(s.rowLoss, 0.019, accuracy: 0.012)
        XCTAssertEqual(s.objectLoss, 0)
        let spots = TankShade.spots(l)
        XCTAssertFalse(spots.filter { $0.key.hasPrefix("0.") }.contains(where: \.behindRow))
        XCTAssertTrue(spots.filter { $0.key.hasPrefix("1.") }.allSatisfy(\.behindRow))
        // the lower module's centre sits lower than the upper one's
        let lower = spots.first { $0.lower }!, upper = spots.first { !$0.lower }!
        XCTAssertLessThan(lower.z, upper.z)
        XCTAssertEqual(s.snapshots.count, 6)
        XCTAssertNil(s.heat[0][2])            // night
        XCTAssertNotNil(s.heat[11][9])
    }

    func testAnObjectSouthShadesMoreThanOneNorth() {
        let l = layout()
        func loss(_ dir: String) -> Double {
            TankShade(layout: l, objects: [.init(direction: dir, height: 12, distance: 3)], azimuth: 0, exposed: 1.2, latitude: 17).objectLoss
        }
        let south = loss("S"), north = loss("N")
        XCTAssertGreaterThan(south, 0.01)
        XCTAssertLessThan(north, south)
        // lower than the panels: nothing
        XCTAssertEqual(TankShade(layout: l, objects: [.init(direction: "S", height: 2, distance: 3)], azimuth: 0, exposed: 1.2, latitude: 17).objectLoss, 0)
    }

    func testItSuggestsAHeightToCutTo() throws {
        let s = TankShade(layout: layout(), objects: [.init(direction: "S", height: 12, distance: 3)], azimuth: 0, exposed: 1.2, latitude: 17)
        let h = try XCTUnwrap(s.cutTo)
        XCTAssertLessThan(h, 12)
        XCTAssertGreaterThan(s.objectMWh, 0)
    }

    func testTheSurveyAnswersBecomeObjects() {
        var v = Values()
        XCTAssertTrue(TankShade.objects(v).isEmpty)
        v["shade"] = .choice("มี", other: "")
        v["shadeDir"] = .multi(["S", "SW"])
        XCTAssertTrue(TankShade.objects(v).isEmpty)        // no height yet
        v[TankShade.Key.height] = .text("8"); v[TankShade.Key.distance] = .text("5")
        XCTAssertEqual(TankShade.objects(v), [.init(direction: "S", height: 8, distance: 5), .init(direction: "SW", height: 8, distance: 5)])
        XCTAssertEqual(Schema.shadeText(v), "เงาบัง ทิศ S, SW สูง 8 ม. ห่าง 5 ม.")
        XCTAssertEqual(TankShade.month(1), 0); XCTAssertEqual(TankShade.month(32), 1); XCTAssertEqual(TankShade.month(365), 11)
    }
}

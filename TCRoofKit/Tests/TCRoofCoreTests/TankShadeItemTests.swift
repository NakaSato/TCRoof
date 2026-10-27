import XCTest
@testable import TCRoofCore

/// D1's shade objects placed one by one (docs/ui/survey-d1-obstacles-ipad Part B, `TankShade.Item`).
final class TankShadeItemTests: XCTestCase {
    typealias Item = TankShade.Item

    /// A 40 × 40 m tank, its plan's top facing north, with the automatic layout.
    func tank(_ items: [Item] = []) -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        v[Tank.Key.azimuth] = .text("0")
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        if !items.isEmpty { TankShade.setItems(&v, items) }
        return v
    }
    /// A building just south of the tank's middle (the plan's y grows southwards).
    let south = Item(id: "B1", kind: .building, x: 20, y: 40 + 3 + 5, height: 14, width: 10)

    func testAnItemSouthShadesTheSouthRowsInDecemberNotAtNoonInJune() throws {
        let v = tank([south])
        let dec = try XCTUnwrap(TankShade.moment(v, latitude: 17, month: 11, time: 12))
        let jun = try XCTUnwrap(TankShade.moment(v, latitude: 17, month: 5, time: 12))
        XCTAssertFalse(dec.itemShaded["B1", default: []].isEmpty, "a low winter sun from the south casts it over the south rows")
        XCTAssertTrue(jun.itemShaded["B1", default: []].isEmpty, "the June noon sun is almost overhead, a little to the north")
        // the shaded panels are the southern ones
        let l = try XCTUnwrap(TankLayout.current(v))
        let ys = l.builtTables.flatMap(\.panels).filter { dec.itemShaded["B1"]!.contains($0.key) }.map { $0.y + $0.h / 2 }
        XCTAssertGreaterThan(try XCTUnwrap(ys.min()), 25)
    }

    func testALowItemNorthLosesNothing() throws {
        let north = Item(id: "B1", kind: .building, x: 20, y: -3 - 3, height: 3, width: 6)
        let s = try XCTUnwrap(TankShade(tank([north]), latitude: 17))
        XCTAssertLessThan(s.objectLoss, 0.001)
        XCTAssertLessThan(s.itemLoss["B1"] ?? 1, 0.001)
    }

    func testItemLossesAddUpToTheTotal() throws {
        let tree = Item(id: "T1", kind: .tree, x: -6, y: 30, height: 14, width: 8)
        let tower = Item(id: "W1", kind: .tower, x: 46, y: 42, height: 18, width: 6)
        let s = try XCTUnwrap(TankShade(tank([south, tree, tower]), latitude: 17))
        XCTAssertGreaterThan(s.objectLoss, 0)
        XCTAssertEqual(s.itemLoss.values.reduce(0, +), s.objectLoss, accuracy: 1e-9)
        XCTAssertTrue(s.objects.isEmpty, "with items the long walls aren't simulated as well")
    }

    func testTheFormAnswersAreWrittenFromTheItems() {
        let tree = Item(id: "T1", kind: .tree, x: -6, y: 20, height: 9, width: 6)
        let v = tank([south, tree])
        XCTAssertEqual(v.choice("shade"), "มี")
        XCTAssertEqual(v.multi("shadeFrom"), ["ต้นไม้", "อาคาร"])
        XCTAssertEqual(v.multi("shadeDir"), ["S", "W"])
        XCTAssertEqual(v.number(TankShade.Key.height), 14)
        XCTAssertEqual(v.number(TankShade.Key.distance), 3, "the tree's gap is 6 − 3 = 3, the building's 3")
        XCTAssertEqual(TankShade.items(v), [south, tree])
        XCTAssertEqual(TankShade.nextID(.tree, in: [south, tree]), "T2")
        var w = v
        TankShade.setItems(&w, [])
        XCTAssertNil(w[TankShade.ItemKey.items])
        XCTAssertEqual(w.choice("shade"), "มี", "removing the last item leaves the answers as they were")
    }

    func testAnOldJobGivesTheSameResultAsBefore() throws {
        var v = tank()
        v["shade"] = .choice("มี", other: ""); v["shadeDir"] = .multi(["S"])
        v[TankShade.Key.height] = .text("12"); v[TankShade.Key.distance] = .text("3")
        let s = try XCTUnwrap(TankShade(v, latitude: 17))
        let l = try XCTUnwrap(TankLayout.current(v))
        let before = TankShade(layout: l, objects: [.init(direction: "S", height: 12, distance: 3)], azimuth: 0, exposed: Tank.exposed(v) ?? 0, latitude: 17)
        XCTAssertEqual(s.objectLoss, before.objectLoss)
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertGreaterThan(s.objectLoss, 0)
    }

    func testTheShadowFallsAwayFromTheSun() {
        // December noon: the sun is south, so the shadow reaches north (smaller y) of the building
        let alt = TankShade.sun(latitude: 17, month: 11, time: 12)!
        let outline = TankShade.shadow(south, altitude: alt.altitude, azimuth: alt.azimuth, planAzimuth: 0, onPlane: 0)
        XCTAssertGreaterThan(outline.count, 3)
        XCTAssertLessThan(outline.map(\.y).min()!, south.y - south.width / 2 - 5)
        XCTAssertEqual(TankShade.gap(south, in: tank()), 3, accuracy: 1e-9)
        XCTAssertEqual(TankShade.direction(of: south, size: (40, 40), azimuth: 0), "S")
    }
}

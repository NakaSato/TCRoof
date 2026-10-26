import XCTest
@testable import TCRoofCore

/// D1 sub-step 4 on iPad (docs/ui/survey-d1-photo-ipad): the tiles over the `ภาพถ่าย` group's fields.
final class TankPhotosTests: XCTestCase {
    func photo(_ tag: String? = nil) -> Photo { var p = Photo(fileName: UUID().uuidString + ".jpg", width: 4, height: 3); p.tag = tag; return p }
    var group: GroupSpec { Schema.spec(.tank).groups.first { $0.title == "ภาพถ่าย" }! }

    func testEveryFieldOfTheGroupHasItsTiles() {
        let tiles = TankPhotos.tiles(Values())
        // every field once, the roof list twice (its two slots); obstacles have one empty tile while there's none
        var count: [String: Int] = [:]
        for t in tiles { count[t.field, default: 0] += 1 }
        XCTAssertEqual(Set(count.keys), Set(group.fields.map(\.id)))
        XCTAssertEqual(count[Tank.Key.roofPhotos], 2)
        for f in group.fields where f.id != Tank.Key.roofPhotos { XCTAssertEqual(count[f.id], 1, f.id) }
        XCTAssertEqual(Set(tiles.map(\.id)).count, tiles.count)
        // each obstacle photo is a tile, named after its tag
        var v = Values()
        v["obstPhotos"] = .photos([photo("V9"), photo()])
        XCTAssertEqual(TankPhotos.tiles(v).filter { $0.field == "obstPhotos" }.map(\.name), ["V9", "สิ่งกีดขวาง 2"])
    }

    func testRequiredTilesAreTheCompletionsFields() {
        let required = Set(TankPhotos.tiles(Values()).filter(\.required).map(\.field))
        XCTAssertEqual(required, Set(group.fields.filter { !$0.optional }.map(\.id)))
        XCTAssertEqual(required.count, Tank.photoCompletion(Values()).total)
        // filling every required tile completes the group
        var v = Values()
        for t in TankPhotos.tiles(v) where t.required { TankPhotos.set(&v, t, photo(), wall: 0) }
        let c = Tank.photoCompletion(v)
        XCTAssertEqual(c.filled, c.total)
        XCTAssertNil(TankPhotos.nextMissing(v, after: nil))
        XCTAssertTrue(TankPhotos.summary(v).hasPrefix("ภาพบังคับครบแล้ว"))
    }

    func testRoofSlotsWallsAndObstacles() throws {
        var v = Values()
        let tiles = TankPhotos.tiles(v)
        let roof = try XCTUnwrap(tiles.first { $0.id == "roof" }), surface = try XCTUnwrap(tiles.first { $0.id == "surface" })
        // the surface first: it stays the surface
        TankPhotos.set(&v, surface, photo())
        XCTAssertNil(TankPhotos.photo(v, roof))
        XCTAssertEqual(TankPhotos.photo(v, surface)?.tag, TankPhotos.roofSurface)
        TankPhotos.set(&v, roof, photo())
        XCTAssertEqual(v.photos(Tank.Key.roofPhotos).map(\.tag), [TankPhotos.roofOverview, TankPhotos.roofSurface])
        TankPhotos.set(&v, surface, nil)
        XCTAssertEqual(v.photos(Tank.Key.roofPhotos).count, 1)
        // an older job's untagged roof photos: first is the overview, second the surface
        v[Tank.Key.roofPhotos] = .photos([photo(), photo()])
        XCTAssertNotNil(TankPhotos.photo(v, roof)); XCTAssertNotNil(TankPhotos.photo(v, surface))
        XCTAssertNotEqual(TankPhotos.photo(v, roof)?.id, TankPhotos.photo(v, surface)?.id)
        // walls: four slots in order
        let walls = try XCTUnwrap(tiles.first { $0.id == "walls" })
        for i in 0..<5 { TankPhotos.set(&v, walls, photo(), wall: i) }
        XCTAssertEqual(TankPhotos.walls(v).count, 4)
        // obstacles: up to five
        for _ in 0..<6 { TankPhotos.addObstacle(&v, photo()) }
        XCTAssertEqual(v.photos("obstPhotos").count, TankPhotos.obstacleMax)
        // a note edited in place
        let first = try XCTUnwrap(TankPhotos.tiles(v).first { $0.id == "obst.0" })
        TankPhotos.edit(&v, first) { $0.note = "ฝาแตก" }
        XCTAssertEqual(v.photos("obstPhotos")[0].note, "ฝาแตก")
    }

    func testFilterNextMissingAndShotPoint() {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        let aerial = TankPhotos.tiles(v)[0]
        XCTAssertEqual(TankPhotos.nextMissing(v, after: nil)?.id, "aerial")
        var p = photo(); p.lat = 17.0; p.lon = 99.0
        TankPhotos.set(&v, aerial, p)
        XCTAssertEqual(TankPhotos.filtered(v, .done).map(\.id), ["aerial"])
        XCTAssertFalse(TankPhotos.filtered(v, .missing).contains { $0.id == "aerial" })
        XCTAssertEqual(TankPhotos.nextMissing(v, after: "aerial")?.id, "walls")
        // A1's position is the tank's centre: a photo there is in the middle of the 40 × 40 plan
        let c = TankPhotos.shotPoint(p, tank: v, site: "17.0, 99.0")
        XCTAssertEqual(c?.x ?? 0, 20, accuracy: 1e-6); XCTAssertEqual(c?.y ?? 0, 20, accuracy: 1e-6)
        // 20 m north of it, with the plan's top facing north: the top edge
        p.lat = 17.0 + 20 / 110_540
        XCTAssertEqual(TankPhotos.shotPoint(p, tank: v, site: "17.0, 99.0")?.y ?? 99, 0, accuracy: 1e-6)
        XCTAssertNil(TankPhotos.shotPoint(p, tank: v, site: ""))
        XCTAssertNotNil(TankPhotos.shotPlan(v, site: "17.0, 99.0", selected: "aerial"))
        XCTAssertNil(TankPhotos.shotPlan(v, site: "17.0, 99.0", selected: "walls"))
    }
}

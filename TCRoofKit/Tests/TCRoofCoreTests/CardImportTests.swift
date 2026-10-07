import XCTest
@testable import TCRoofCore

final class CardImportTests: XCTestCase {
    func testAerialIsTheHighestClearlyAboveTheRest() {
        let ground = CardImport.Shot(altitude: 52), drone = CardImport.Shot(altitude: 110), mid = CardImport.Shot(altitude: 60)
        XCTAssertEqual(CardImport.aerial([ground, drone, mid, CardImport.Shot()])?.id, drone.id)
        XCTAssertNil(CardImport.aerial([ground, mid]), "8 m higher is someone on a roof, not a drone")
        XCTAssertEqual(CardImport.aerial([drone, CardImport.Shot()])?.id, drone.id, "the only one with an altitude")
        XCTAssertNil(CardImport.aerial([CardImport.Shot()]))
    }

    func testSiteGeoFromAFetchedMap() throws {
        var v = Values()
        v[SiteShapes.sourceKey] = .text("google")
        v[SiteShapes.scaleKey] = .text("48.6")
        v[MapCrop.key] = .text("22,16,54,64")
        let geo = try XCTUnwrap(SiteGeo(values: v, lat: 17, lon: 100))
        XCTAssertEqual(geo.mapMeters, 90, accuracy: 0.01, "48.6 m is 54 % of the map")
        // the crop's centre (49 %, 48 %) is 1 % left and 2 % up of the map's centre
        let c = geo.coordinate(x: 0.5, y: 0.5)
        XCTAssertEqual(CardImport.distance(17, 100, c.lat, c.lon), (0.9 * 0.9 + 1.125 * 1.125).squareRoot(), accuracy: 0.01)
        XCTAssertLessThan(c.lon, 100)
        XCTAssertGreaterThan(c.lat, 17)
        v[SiteShapes.sourceKey] = .text("drone")
        XCTAssertNil(SiteGeo(values: v, lat: 17, lon: 100), "a drone photo has no known position")
    }

    func testPhotoNearATransformerGoesToItsSlots() throws {
        var job = Job.new(template: JobTemplate.all[0])
        let tx = Transformer(kva: "630")
        job.values["trafos"] = .transformers([Transformer(kva: "250"), tx])
        let mark = MapMark(kind: .trafo, x: 0.75, y: 0.5, link: "tr:\(tx.id)")
        let geo = SiteGeo(lat: 17, lon: 100, mapMeters: 100, crop: .full)
        let at = geo.coordinate(x: 0.75, y: 0.5)
        // 25 m east of the centre; a photo 5 m north of the symbol
        let shot = CardImport.Shot(lat: at.lat + 5 / 111_320, lon: at.lon)
        let near = try XCTUnwrap(CardImport.nearest(shot, marks: [mark, MapMark(kind: .meter, x: 0.2, y: 0.5)], geo: geo))
        XCTAssertEqual(near.mark.id, mark.id)
        XCTAssertEqual(near.meters, 5, accuracy: 0.01)
        XCTAssertNil(CardImport.nearest(CardImport.Shot(lat: 17, lon: 100), marks: [mark], geo: geo), "25 m away")

        job.values["tr1_front"] = .photo(Photo(fileName: "f.jpg", width: 1, height: 1))
        let slots = job.photoTargets(for: mark).map(\.field)
        XCTAssertEqual(slots, ["tr1_back", "tr1_left", "tr1_right", "tr1_plate", "tr1_wide"], "TX 2's empty photos, in order")
        XCTAssertTrue(job.emptyPhotoTargets.contains { $0.field == "tr0_front" })
        XCTAssertFalse(job.emptyPhotoTargets.contains { $0.field == "siteMap" }, "the site picture has its own offer")
    }
}

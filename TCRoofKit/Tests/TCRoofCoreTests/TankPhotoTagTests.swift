import XCTest
@testable import TCRoofCore

/// D1 sub-step 4: a photo's note and opening tag (docs/specs/tank-drawing-swift.md).
final class TankPhotoTagTests: XCTestCase {
    func testOldPhotosDecodeAndCaptions() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","fileName":"a.jpg","width":10,"height":10,"takenAt":0}"#
        var p = try JSONDecoder().decode(Photo.self, from: Data(old.utf8))
        XCTAssertNil(p.note); XCTAssertNil(p.tag); XCTAssertNil(p.caption)
        p.tag = "V3"; p.note = " ฝาปล่องแตก "
        XCTAssertEqual(p.caption, "V3 · ฝาปล่องแตก")
        let back = try JSONDecoder().decode(Photo.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.caption, "V3 · ฝาปล่องแตก")
    }

    func testTagsComeFromTheTanksPoints() {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        TankPoints.seed(&v)
        let options = TankPoints.tagOptions(v)
        XCTAssertTrue(options.contains("V1") && options.contains("H1"))
        XCTAssertEqual(TankPoints.tag("v1", in: v), "V1")
        XCTAssertEqual(TankPoints.tag("V1-V10", in: v), "V1–V10")
        XCTAssertNil(TankPoints.tag("V1–H2", in: v))       // one kind per range
        XCTAssertNil(TankPoints.tag("X9", in: v))
        // a point marked absent can't be tagged
        let v1 = TankPoints.points(v).first { $0.label == "V1" }!
        TankPoints.setStatus(&v, v1.id, TankPoints.absent)
        XCTAssertFalse(TankPoints.tagOptions(v).contains("V1"))
    }
}

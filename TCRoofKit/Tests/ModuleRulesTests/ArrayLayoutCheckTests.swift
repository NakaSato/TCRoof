import XCTest
@testable import ModuleRules

/// The layout's stored checks (docs/specs/module-install-rules.md §7.2) against a drawn layout's geometry.
final class ArrayLayoutCheckTests: XCTestCase {
    /// Portrait 570 W modules on rails along the eave, 15° pitch at Bangkok, rails 640 mm from the ends.
    func geometry(offsets: [Double] = [570], side: ClampSide = .long) -> ArrayLayoutCheck.LayoutGeometry {
        .init(tiltDeg: 15, latitude: 13.7, landscape: false, clampSide: side, clampOffsetsMm: offsets, gapMm: 20,
              tiltsByFace: [15, 15], azimuthsByFace: [180, 0])
    }
    var check: ArrayLayoutCheck { var c = ArrayLayoutCheck(); c.moduleID = "ZXM7-UHLDD144-570"; return c }
    func ids(_ c: ArrayLayoutCheck, _ g: ArrayLayoutCheck.LayoutGeometry) -> Set<String> { Set(c.validation(g).results.map(\.id)) }

    func testALayoutInsideTheRulesRaisesNothing() {
        XCTAssertTrue(check.validation(geometry()).results.isEmpty)
    }

    func testTheClampZoneComesFromTheLayout() {
        // 2278 mm long: L/4 ± 50 = 519.5–619.5
        XCTAssertFalse(ids(check, geometry(offsets: [520, 600])).contains("S553-zone"))
        XCTAssertTrue(ids(check, geometry(offsets: [520, 640])).contains("S553-zone"), "one rail outside is enough")
        XCTAssertEqual(check.checkedOffset(geometry(offsets: [520, 640])), 640)
        // a big module held on its short side
        XCTAssertTrue(ids(check, geometry(side: .short)).contains("S553-short"))
    }

    func testTheStringBuilder() throws {
        var c = check
        c.tMinC = 15; c.inverterMaxDcV = 1100
        let s = try XCTUnwrap(c.stringLimit)
        // 51.1 V × (1 − 0.0025 × −10) = 52.38 V → ⌊1100 / 52.38⌋ = 21
        XCTAssertEqual(s.nmax, 21); XCTAssertEqual(s.coldVoc, 52.3775, accuracy: 1e-4); XCTAssertEqual(s.limitV, 1100)
        c.modulesPerString = 21
        XCTAssertFalse(ids(c, geometry()).contains("ZN-106"))
        c.modulesPerString = 22
        XCTAssertTrue(ids(c, geometry()).contains("ZN-106"))
        // over two faces: their tilt and azimuth differ in one string
        c.modulesPerString = 20; c.stringAcrossFaces = true
        XCTAssertTrue(ids(c, geometry()).contains("ZN-79"))
        XCTAssertNil(ArrayLayoutCheck().stringLimit, "no module, no limit")
    }

    func testCableAndGrounding() {
        var c = check
        c.cableMm2 = 4; c.cableAmpacityA = 17.79
        XCTAssertFalse(ids(c, geometry()).contains("ZN-112"), "1.25 × 14.23 = 17.79 A")
        c.parallelCount = 2
        XCTAssertTrue(ids(c, geometry()).contains("ZN-112"))
        c.cableMm2 = 2.5; c.groundingSeries = 9
        XCTAssertTrue(ids(c, geometry()).isSuperset(of: ["ZN-107", "ZN-122"]))
    }

    func testTheTiltComesFromTheLayout() {
        var g = geometry(); g.tiltDeg = 5
        XCTAssertTrue(ids(check, g).isSuperset(of: ["ZN-81", "ZN-82"]))
    }

    func testMatchingAndStoring() {
        XCTAssertEqual(ArrayLayoutCheck.match(wp: 570, lengthMm: 2279, widthMm: 1134)?.id, "ZXM7-UHLDD144-570")
        XCTAssertNil(ArrayLayoutCheck.match(wp: 600, lengthMm: 2280, widthMm: 1130), "the old 600 W default isn't in the catalog")
        var c = check; c.tMinC = 15; c.reasons = ["ZN-90": "x"]
        XCTAssertEqual(ArrayLayoutCheck.decode(c.json), c)
        XCTAssertEqual(ArrayLayoutCheck.decode("{\"tMinC\":12}").tMinC, 12)
        XCTAssertEqual(ArrayLayoutCheck.decode(""), ArrayLayoutCheck())
    }
}

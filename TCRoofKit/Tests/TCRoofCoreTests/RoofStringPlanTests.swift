import XCTest
@testable import TCRoofCore

/// C1's `สตริง` tile (`RoofMountYield.stringPlan`).
final class RoofStringPlanTests: XCTestCase {
    func testTheLengthLeavingFewestOver() throws {
        // 75 modules, 8–16 allowed: 15 × 5 leaves none
        let a = try XCTUnwrap(RoofMountYield.plan(modules: 75, range: 8...16, inputs: 12, inverter: "x", assumed: nil))
        XCTAssertEqual([a.perString, a.strings, a.leftover], [15, 5, 0])
        // 77: no length divides it; 11 × 7 does (longest wins a tie, so fewer strings)
        let b = try XCTUnwrap(RoofMountYield.plan(modules: 77, range: 8...16, inputs: 12, inverter: "x", assumed: nil))
        XCTAssertEqual([b.perString, b.strings, b.leftover], [11, 7, 0])
        // 79 is prime: 13 × 6 leaves 1, the fewest any length leaves
        let c = try XCTUnwrap(RoofMountYield.plan(modules: 79, range: 8...16, inputs: 4, inverter: "x", assumed: nil))
        XCTAssertEqual([c.perString, c.strings, c.leftover], [13, 6, 1])
        XCTAssertFalse(c.fits, "7 strings on 4 inputs")
        XCTAssertNil(RoofMountYield.plan(modules: 5, range: 8...16, inputs: 4, inverter: "x", assumed: nil))
    }

    func testTheEngineGivesARangeForTheDefaultModule() throws {
        let i = RoofMountYield.Inputs(faces: [.init(id: "S", modules: 96, tiltDeg: 15, azimuthDeg: 180, clearSkyYield: 1400)],
                                      moduleWp: 570, moduleLength: 2.278, moduleWidth: 1.134, inverterSizes: [60], roofSections: 1,
                                      latitude: 13.75, longitude: 100.5)
        let p = try XCTUnwrap(RoofMountYield.stringPlan(i))
        XCTAssertTrue(p.range.contains(p.perString))
        XCTAssertGreaterThan(p.range.lowerBound, 5)
        XCTAssertLessThan(p.range.upperBound, 30)
        XCTAssertEqual(p.perString * p.strings + p.leftover, 96)
        XCTAssertTrue(p.inverter.contains("Growatt"))
        XCTAssertNil(p.assumed)
        // a module the engine has no model for
        var other = i
        other.moduleWp = 455
        XCTAssertNil(RoofMountYield.stringPlan(other))
    }
}

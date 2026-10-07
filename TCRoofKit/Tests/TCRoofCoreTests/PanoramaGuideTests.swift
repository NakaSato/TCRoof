import XCTest
@testable import TCRoofCore

final class PanoramaGuideTests: XCTestCase {
    /// Turns `degrees` to the right while held upright in portrait (gravity along −y), in 0.1 s steps.
    private func turn(_ g: inout PanoramaGuide, _ degrees: Double) {
        let steps = 10, rate = -degrees * .pi / 180 // about +y, turning right is negative
        for _ in 0..<steps { g.turn(rate: SIMD3(0, rate, 0), gravity: SIMD3(0, -1, 0), dt: 1.0 / Double(steps)) }
    }

    func testThreeShotsLeftToRight() {
        var g = PanoramaGuide(horizontalFOV: 60)
        XCTAssertEqual(g.step, 42, accuracy: 0.001, "30 % overlap")
        XCTAssertTrue(g.ready)
        XCTAssertTrue(g.cue.contains("ภาพซ้าย (1/3)"))
        turn(&g, 20)
        XCTAssertEqual(g.turned, 0, "nothing counts before the first shot")
        g.shot()
        XCTAssertFalse(g.ready)
        turn(&g, 30)
        XCTAssertEqual(g.offset, -12, accuracy: 0.001)
        XCTAssertEqual(g.cue, "หมุนไปทางขวาอีก 12° เพื่อถ่ายภาพกลาง (2/3)")
        turn(&g, 14)
        XCTAssertTrue(g.ready, "within 3° of 42°")
        g.shot()
        turn(&g, 50)
        XCTAssertEqual(g.cue, "เลยมา 10° หมุนกลับทางซ้าย", "44° + 50° is 10° past 84°")
        turn(&g, -10)
        XCTAssertTrue(g.ready)
        g.shot()
        XCTAssertTrue(g.done)
        XCTAssertFalse(g.ready)
        XCTAssertEqual(g.cue, "ครบ 3 ภาพ")
    }

    func testLandscapeTurnUsesGravity() {
        var g = PanoramaGuide(horizontalFOV: 60)
        g.shot()
        // landscape, home button right: gravity along −x; turning right is a negative rotation about +x
        g.turn(rate: SIMD3(-1, 0, 0), gravity: SIMD3(-1, 0, 0), dt: 0.5)
        XCTAssertEqual(g.turned, 0.5 * 180 / .pi, accuracy: 0.001)
    }

    func testPortraitFieldOfView() {
        XCTAssertEqual(PanoramaGuide.horizontalFOV(sensorFOV: 70, portrait: false), 70)
        XCTAssertEqual(PanoramaGuide.horizontalFOV(sensorFOV: 70, portrait: true), 55.4, accuracy: 0.1)
    }
}

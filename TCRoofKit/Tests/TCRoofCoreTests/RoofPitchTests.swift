import XCTest
@testable import TCRoofCore

/// docs/specs/auto-drawing.md §4.4: C1's pitch from the measured heights, and the "n@d" span shorthand.
final class RoofPitchTests: XCTestCase {
    /// The spec's C1 example with B = 16 across the ridge (four 4 m bays: the code sums every span, so the spec's
    /// "1.5,4,4,4,4,1.5" would give 19, open question 1), eave 4.0, heel 0.5.
    func roof(ridge: Double?) -> Values {
        var v = Values()
        Roof.setSpans(&v, .x, [4, 4, 4, 4]); Roof.setSpans(&v, .y, [4, 4, 4])
        Roof.setRidge(&v, .v); Roof.setFrame(&v, .pratt)
        Roof.setLength(&v, Roof.Key.clearHeight, 4.0)
        if let ridge { v[Roof.Key.ridgeHeight] = .text(fmt(ridge, digits: 6)) }
        return v
    }

    func testWithoutARidgeHeightThePitchIsTheFrames() {
        let v = roof(ridge: nil)
        XCTAssertEqual(Roof.pitch(v), Roof.Pitch(degrees: 15, measured: false, warning: nil))
        XCTAssertEqual(Roof.slopeText(v), "15°")
        // the implied ridge height is what the frame's slope gives
        XCTAssertEqual(Roof.ridgeHeight(v), 4.0 + 0.5 + 8 * tan(15 * Double.pi / 180), accuracy: 1e-9)
    }

    func testTheSpecExampleGives15Degrees() {
        // ridge 6.643594 − eave 4.0 − heel 0.5 = R 2.1436 over 8 m
        let v = roof(ridge: 6.643594), p = Roof.pitch(v)
        XCTAssertTrue(p.measured)
        XCTAssertNil(p.warning)
        XCTAssertEqual(p.degrees, 15, accuracy: 1e-4)
    }

    func testAMeasuredPitchDrivesTheSectionPlanAndPV() {
        let v = roof(ridge: 7.0), p = Roof.pitch(v)
        let expected = atan(2.5 / 8) * 180 / .pi
        XCTAssertEqual(p.degrees, expected, accuracy: 1e-9)
        XCTAssertEqual(Roof.slopeText(v), "17.4°")
        let sec = RoofSection(v)
        XCTAssertEqual(sec.rise, 2.5, accuracy: 1e-9)
        let texts = sec.sketch.ops.compactMap { op -> String? in if case let .text(t, _, _, _, _, _, _) = op { return t }; return nil }
        XCTAssertTrue(texts.contains("17.4°"))
        XCTAssertTrue(texts.contains("R 2.50"))
        // purlin lines step by spacing · cos(pitch)
        let lines = Roof.purlinLines(v).filter { $0 < 8 }.sorted(by: >)
        XCTAssertEqual(lines[0] - lines[1], cos(expected * .pi / 180), accuracy: 1e-9)
        XCTAssertEqual(RoofMount.input(v, latitude: nil).ridgeHeight, 2.5, accuracy: 1e-9)
    }

    func testChecks() {
        let low = Roof.pitch(roof(ridge: 4.4))
        XCTAssertFalse(low.measured)
        XCTAssertEqual(low.degrees, 15)
        XCTAssertEqual(low.warning, "ความสูงสันต้องมากกว่าชายคา")
        let flat = Roof.pitch(roof(ridge: 4.7))
        XCTAssertTrue(flat.measured)
        XCTAssertEqual(flat.warning, "ตรวจความสูงอีกครั้ง (มุมประมาณ 1.4°)")
        let steep = Roof.pitch(roof(ridge: 30))
        XCTAssertFalse(steep.measured)
        XCTAssertEqual(steep.degrees, 15)
        XCTAssertNotNil(steep.warning)
    }

    func testTheFieldIsHiddenAndOptional() throws {
        let f = try XCTUnwrap(Schema.spec(.roof).groups.flatMap(\.fields).first { $0.id == Roof.Key.ridgeHeight })
        XCTAssertTrue(f.optional)
        XCTAssertFalse(f.isVisible(Values()))
        XCTAssertTrue(RoofDesign.keys.contains(Roof.Key.ridgeHeight))
    }

    // MARK: spans

    func testSpanShorthand() {
        XCTAssertEqual(parseSpans("16@4"), Array(repeating: 4, count: 16))
        XCTAssertEqual(parseSpans("1.5, 3@4, 1.5"), [1.5, 4, 4, 4, 1.5])
        XCTAssertEqual(parseSpans("1.5, 3 @ 4.00, 1.5"), [1.5, 4, 4, 4, 1.5])
        XCTAssertEqual(parseSpans("4ม., ๔"), [4, 4])
        XCTAssertEqual(parseSpans("1.5,4,4,4,4,1.5"), [1.5, 4, 4, 4, 4, 1.5], "the plain list is unchanged")
        // not a count: dropped rather than read as 164
        XCTAssertEqual(parseSpans("2.5@4"), [])
        XCTAssertEqual(parseSpans("501@4"), [])
        XCTAssertEqual(parseSpans("0@4, 5"), [5])
        // the tank presets read the same either way
        var v = Values()
        v[Roof.Key.spansX] = .text("10@4"); v[Roof.Key.spansY] = .text("10@4")
        XCTAssertEqual(Tank.preset(v), Tank.presets[0])
    }
}

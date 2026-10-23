import XCTest
@testable import TCRoofCore

/// C1's section drawn to scale for the DXF (`RoofSection(trueScale:)`): the ground at the clear height, and every
/// measure a live DIMENSION.
final class RoofSectionScaleTests: XCTestCase {
    func roof(_ f: RoofFrame, clear: Double = 5.5) -> Values {
        var v = RoofDXFTests().roof()
        Roof.setFrame(&v, f); v[Roof.Key.clearHeight] = .text(String(clear))
        return v
    }
    func length(_ d: SketchDXF.Dimension) -> Double { d.vertical ? abs(d.b.y - d.a.y) : abs(d.b.x - d.a.x) }

    func testEveryDimensionMeasuresItsValue() throws {
        for f in RoofFrame.allCases {
            let v = roof(f), s = RoofSection(v, trueScale: true)
            let clear = try XCTUnwrap(s.dimensions.first { $0.text.hasPrefix(f.isRafter ? "สูงถึงหัวเสา" : "สูงใต้ขื่อ") }, "\(f)")
            XCTAssertEqual(length(clear) / s.scale, 5.5, accuracy: 1e-6, "\(f)")
            let span = try XCTUnwrap(s.dimensions.first { $0.text.hasSuffix("(จากแปลน)") })
            XCTAssertEqual(length(span) / s.scale, s.span, accuracy: 1e-6)
            let rise = try XCTUnwrap(s.dimensions.first { $0.text.hasPrefix("R ") })
            XCTAssertEqual(length(rise) / s.scale, s.rise, accuracy: 1e-6)
            let halves = s.dimensions.filter { $0.at.y == s.dimensions[0].at.y && $0.text == s.dimensions[0].text }
            XCTAssertEqual(halves.count, 2)
            XCTAssertTrue(halves.allSatisfy { abs(length($0) / s.scale - s.half) < 1e-6 })
            // overhangs and the heel, where the frame has them
            for d in s.dimensions where d.text.hasPrefix("ชายคา") { XCTAssertEqual(length(d) / s.scale, Roof.overhang(v), accuracy: 1e-6) }
            if !f.isRafter, f.heel > 0 { XCTAssertTrue(s.dimensions.contains { abs(length($0) / s.scale - f.heel) < 1e-6 && $0.vertical }) }
            // every label carries its measured value, so CAD keeps it live
            for d in s.dimensions {
                XCTAssertTrue(d.text.contains(String(format: "%.2f", length(d) / s.scale)), "\(f) \(d.text)")
            }
            // the sketch grows to hold the ground; the lines it drew for the dimensions are marked
            XCTAssertGreaterThan(s.sketch.height, RoofSection.height)
            XCTAssertFalse(s.dimensionOps.isEmpty)
            XCTAssertTrue(s.dimensionOps.allSatisfy { s.tags[$0] == "DIM" })
        }
    }

    func testThePageKeepsItsDiagram() {
        let v = roof(.pratt), s = RoofSection(v)
        XCTAssertEqual(s.sketch.height, RoofSection.height)
        XCTAssertTrue(s.dimensions.isEmpty)
        // a taller clear height doesn't move the page's ground
        XCTAssertEqual(RoofSection(roof(.pratt, clear: 9)).sketch.ops.count, s.sketch.ops.count)
    }

    func testTheDXFWritesTheSectionsDimensions() throws {
        let t = SketchDXFTests()
        let out = RoofDXF.build(roof(.pratt), parts: [.section])
        let dims = t.rawEntities(out.data).filter { $0.first?.1 == "DIMENSION" }
        XCTAssertEqual(dims.count, RoofSection(roof(.pratt), trueScale: true).dimensions.count)
        // the clear height reads 5.50 m live (the drawing is in metres)
        let key = String(data: SketchDXF.tis620("สูงใต้ขื่อ <>"), encoding: .isoLatin1)!
        let clear = try XCTUnwrap(dims.first { t.value($0, "1") == key && t.value($0, "50") == "90" })
        XCTAssertEqual(abs(t.double(clear, "24") - t.double(clear, "23")), 5.5, accuracy: 1e-3)
        // no loose dimension lines left on the section's DIM layer apart from the slope arc and the callouts
        XCTAssertLessThan(t.rawEntities(out.data).filter { t.value($0, "8") == "G-ANNO-DIMS" && $0.first?.1 == "LINE" }.count, 12)
    }
}

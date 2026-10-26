import XCTest
@testable import TCRoofCore

/// C1's section drawn to scale for the DXF (`RoofSection(trueScale:)`): the roof structure with the clear height on its
/// level marks, and every measure a live DIMENSION.
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
            let clear = try XCTUnwrap(s.model.levels.first { abs($0.y - 5.5) < 1e-9 }, "\(f)")
            XCTAssertEqual(clear.value(), "+5.50")
            XCTAssertEqual(clear.label, f.isTruss ? "ระดับใต้ขื่อ" : "ระดับหัวเสา")
            let span = try XCTUnwrap(s.dimensions.first { $0.text.hasSuffix("(จากแปลน)") })
            XCTAssertEqual(length(span) / s.scale, s.span, accuracy: 1e-6)
            if f.isTruss {
                let rise = try XCTUnwrap(s.dimensions.first { $0.text.hasPrefix("R ") })
                XCTAssertEqual(length(rise) / s.scale, s.rise, accuracy: 1e-6)
            }
            // the level chain: one dimension between each pair of levels, measuring their difference
            let chain = s.dimensions.filter(\.vertical)
            XCTAssertEqual(chain.count, s.model.levels.count - 1)
            for (d, (a, b)) in zip(chain, zip(s.model.levels, s.model.levels.dropFirst())) {
                XCTAssertEqual(length(d) / s.scale, b.y - a.y, accuracy: 1e-6, "\(f) \(b.label)")
            }
            let first = try XCTUnwrap(s.dimensions.first { !$0.vertical })
            let halves = s.dimensions.filter { $0.at.y == first.at.y && $0.text == first.text }
            XCTAssertEqual(halves.count, 2)
            XCTAssertTrue(halves.allSatisfy { abs(length($0) / s.scale - s.half) < 1e-6 })
            // overhangs and the heel, where the frame has them
            for d in s.dimensions where d.text.hasPrefix("ชายคา") { XCTAssertEqual(length(d) / s.scale, Roof.overhang(v), accuracy: 1e-6) }
            if f.isTruss { XCTAssertTrue(s.dimensions.contains { abs(length($0) / s.scale - f.heel) < 1e-6 && $0.vertical }) }
            // every label carries its measured value, so CAD keeps it live
            for d in s.dimensions {
                XCTAssertTrue(d.text.contains(String(format: "%.2f", length(d) / s.scale)), "\(f) \(d.text)")
            }
            // the roof structure only, the posts cut as on the page; the lines it drew for the dimensions are marked
            XCTAssertEqual(s.sketch.height, RoofSection.height)
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
        // the rise reads live (the drawing is in metres), and the clear height is a level mark
        let key = String(data: SketchDXF.tis620("R <>"), encoding: .isoLatin1)!
        let rise = try XCTUnwrap(dims.first { t.value($0, "1") == key && t.value($0, "50") == "90" })
        XCTAssertEqual(abs(t.double(rise, "24") - t.double(rise, "23")), RoofSection(roof(.pratt)).rise, accuracy: 1e-3)
        let texts = t.rawEntities(out.data).filter { $0.first?.1 == "TEXT" && t.value($0, "8") == "G-ANNO-DIMS" }.compactMap { t.value($0, "1") }
        XCTAssertTrue(texts.contains("+5.50"))
        // no loose dimension lines on the DIM layer: only the level marks' two lines each
        let levels = RoofSection(roof(.pratt)).model.levels.count
        XCTAssertEqual(t.rawEntities(out.data).filter { t.value($0, "8") == "G-ANNO-DIMS" && $0.first?.1 == "LINE" }.count, 2 * levels)
    }
}

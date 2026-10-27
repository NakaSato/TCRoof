import XCTest
@testable import TCRoofCore

/// C1's section drawn to scale for the DXF (`RoofSection(trueScale:)`): the roof structure only (no level marks, no
/// boxed eave or beam at the post heads), every measure a live DIMENSION. The page's section keeps its level marks.
final class RoofSectionScaleTests: XCTestCase {
    func roof(_ f: RoofFrame, clear: Double = 5.5) -> Values {
        var v = RoofDXFTests.roof()
        Roof.setFrame(&v, f); v[Roof.Key.clearHeight] = .text(String(clear))
        return v
    }
    func length(_ d: SketchDXF.Dimension) -> Double { d.vertical ? abs(d.b.y - d.a.y) : abs(d.b.x - d.a.x) }

    func testEveryDimensionMeasuresItsValue() throws {
        for f in RoofFrame.allCases {
            let v = roof(f), s = RoofSection(v, trueScale: true), page = RoofSection(v)
            // the page's level marks: the clear height, and a chain between each pair of levels
            let clear = try XCTUnwrap(page.model.levels.first { abs($0.y - 5.5) < 1e-9 }, "\(f)")
            XCTAssertEqual(clear.value(), "+5.50")
            XCTAssertEqual(clear.label, f.isTruss ? "ระดับใต้ขื่อ" : "ระดับหัวเสา")
            // the CAD file: no level marks, so no vertical chain
            XCTAssertTrue(s.model.levels.isEmpty)
            XCTAssertFalse(s.dimensions.contains(where: \.vertical))
            let span = try XCTUnwrap(s.dimensions.first { $0.text.hasSuffix("(จากแปลน)") })
            XCTAssertEqual(length(span) / s.scale, s.span, accuracy: 1e-6)
            let first = try XCTUnwrap(s.dimensions.first { !$0.vertical })
            let halves = s.dimensions.filter { $0.at.y == first.at.y && $0.text == first.text }
            XCTAssertEqual(halves.count, 2)
            XCTAssertTrue(halves.allSatisfy { abs(length($0) / s.scale - s.half) < 1e-6 })
            // overhangs and the heel, where the frame has them
            for d in s.dimensions where d.text.hasPrefix("ชายคา") { XCTAssertEqual(length(d) / s.scale, Roof.overhang(v), accuracy: 1e-6) }
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
        let t = DXFRead()
        let out = RoofDXF.build(roof(.pratt), parts: [.section])
        let dims = t.rawEntities(out.data).filter { $0.first?.1 == "DIMENSION" }
        XCTAssertEqual(dims.count, RoofSection(roof(.pratt), trueScale: true).dimensions.count)
        // the span reads live (the drawing is in metres)
        let key = String(data: SketchDXF.tis620("<> (จากแปลน)"), encoding: .isoLatin1)!
        let span = try XCTUnwrap(dims.first { t.value($0, "1") == key })
        XCTAssertEqual(abs(t.double(span, "13") - t.double(span, "14")), 16, accuracy: 1e-3)
        // the roof structure only: no level marks, no loose lines or texts on the DIM layer, and no title
        XCTAssertFalse(t.rawEntities(out.data).contains { t.value($0, "8") == "G-ANNO-DIMS" && ["LINE", "TEXT"].contains($0.first?.1 ?? "") })
        XCTAssertFalse(t.rawEntities(out.data).contains { $0.first?.1 == "TEXT" && t.value($0, "8") == "G-ANNO-TEXT" })
    }
}

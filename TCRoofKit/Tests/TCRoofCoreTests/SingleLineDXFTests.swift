import XCTest
@testable import TCRoofCore

/// docs/specs/cad-export-dxf phase 2: the SLD as DXF at A3 paper scale.
final class SingleLineDXFTests: XCTestCase {
    let t = SketchDXFTests()

    func testLayersAndPaperScale() {
        let out = SingleLineDXF.build(SingleLineTests.fixture())
        XCTAssertTrue(out.layers.contains("SLD_LINE"))
        XCTAssertTrue(out.layers.contains("SLD_TEXT"))
        XCTAssertTrue(out.layers.contains("SLD_NEW"))
        XCTAssertTrue(out.layers.contains("SLD_POLE"))
        let ents = t.entities(out.data)
        XCTAssertEqual(ents.count, out.entities)
        for e in ents {
            for code in ["10", "11"] {
                guard let x = t.value(e, code).flatMap(Double.init) else { continue }
                XCTAssertTrue(x >= -0.001 && x <= SingleLineDXF.paperWidth + 0.001, "\(e)")
            }
        }
        let l = t.lines(out.data)
        XCTAssertEqual(l[l.firstIndex(of: "$INSUNITS")! + 2], "4")
        XCTAssertTrue(l.contains("DASHED"), "control lines")
        XCTAssertTrue(l.contains { $0.hasPrefix("SINGLE LINE DIAGRAM") })
    }

    func testMissingValueLayer() {
        // the fixture's CB3 has no IC / AF / brand, and TX2…5 no %Z
        XCTAssertFalse(SingleLine.build(SingleLineTests.fixture()).missing.isEmpty)
        XCTAssertTrue(SingleLineDXF.build(SingleLineTests.fixture()).layers.contains("SLD_MISSING"))
    }

    func testHVAndLVDiffer() {
        let job = SingleLineTests.fixture()
        let hv = SingleLineDXF.build(job, hv: true), lv = SingleLineDXF.build(job, hv: false)
        let pdfHV = SingleLineLayout.draw(SingleLine.build(job, hvOverride: true)).sketch.ops.count
        let pdfLV = SingleLineLayout.draw(SingleLine.build(job, hvOverride: false)).sketch.ops.count
        XCTAssertNotEqual(pdfHV, pdfLV)
        XCTAssertNotEqual(hv.entities, lv.entities)
    }

    func testLayerByColour() {
        XCTAssertEqual(SingleLineDXF.layer(.line(Pt(0, 0), Pt(1, 1), width: 1, color: SingleLineLayout.red)).name, "SLD_MISSING")
        XCTAssertEqual(SingleLineDXF.layer(.line(Pt(0, 0), Pt(1, 1), width: 1, color: SingleLineLayout.grey)).name, "SLD_ASSUMED")
        XCTAssertEqual(SingleLineDXF.layer(SLSymbols.pole(x: 0, y: 0)).name, "SLD_POLE")
        XCTAssertEqual(SingleLineDXF.layer(.text("x", at: Pt(0, 0), size: 9, color: SingleLineLayout.red)).name, "SLD_TEXT")
        XCTAssertEqual(SingleLineDXF.layer(.rect(Box(0, 0, 1, 1), stroke: .black, fill: nil)).name, "SLD_OTHER")
    }
}

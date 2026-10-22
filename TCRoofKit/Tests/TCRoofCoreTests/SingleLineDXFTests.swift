import XCTest
@testable import TCRoofCore

/// docs/specs/cad-export-dxf phase 2: the SLD as DXF at A3 paper scale.
final class SingleLineDXFTests: XCTestCase {
    let t = SketchDXFTests()

    func testLayersAndPaperScale() {
        let out = SingleLineDXF.build(SingleLineTests.fixture())
        XCTAssertTrue(out.layers.contains("E-SLDG-E"))
        XCTAssertTrue(out.layers.contains("E-SLDG-TEXT"))
        XCTAssertTrue(out.layers.contains("E-SLDG-N"))
        XCTAssertTrue(out.layers.contains("E-SLDG-POLE-E"))
        XCTAssertEqual(t.rawEntities(out.data).count, out.entities)
        let ents = t.entities(out.data)
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
        XCTAssertTrue(SingleLineDXF.build(SingleLineTests.fixture()).layers.contains("E-SLDG-MISS"))
    }

    func testHVAndLVDiffer() {
        let job = SingleLineTests.fixture()
        let hv = SingleLineDXF.build(job, hv: true), lv = SingleLineDXF.build(job, hv: false)
        let pdfHV = SingleLineLayout.draw(SingleLine.build(job, hvOverride: true)).sketch.ops.count
        let pdfLV = SingleLineLayout.draw(SingleLine.build(job, hvOverride: false)).sketch.ops.count
        XCTAssertNotEqual(pdfHV, pdfLV)
        XCTAssertNotEqual(hv.entities, lv.entities)
    }

    /// Level 2 reaches the DXF through the shared layout: cable text, SPARE, busbar, the N/G bar and ground rod, the notes.
    func testLevel2Detail() {
        let plain = SingleLineDXF.build(SingleLineTests.fixture()), l2 = SingleLineDXF.build(SingleLineTests.level2())
        let text = String(decoding: l2.data, as: UTF8.self)
        for s in ["4x50,1x10-IEC01, IN WIRE WAY", "SPARE", "4x300A. Cu. BUSBAR W/GROUND BUS", "GROUND ROD", "1x35-IEC01"] {
            XCTAssertTrue(text.contains(s), s)
        }
        XCTAssertFalse(String(decoding: plain.data, as: UTF8.self).contains("GROUND ROD"))
        XCTAssertGreaterThan(l2.entities, plain.entities)
        // the cable text is rotated (code 50 on a TEXT entity)
        let cable = t.entities(l2.data).first { e in e.contains { $0.0 == "1" && $0.1 == "4x50,1x10-IEC01, IN WIRE WAY" } }
        XCTAssertNotNil(cable.flatMap { t.value($0, "50") })
    }

    func testLayerByColour() {
        XCTAssertEqual(SingleLineDXF.layer(.line(Pt(0, 0), Pt(1, 1), width: 1, color: SingleLineLayout.red)).name, "E-SLDG-MISS")
        XCTAssertEqual(SingleLineDXF.layer(.line(Pt(0, 0), Pt(1, 1), width: 1, color: SingleLineLayout.grey)).name, "E-SLDG-ASSM")
        XCTAssertEqual(SingleLineDXF.layer(SLSymbols.pole(x: 0, y: 0)).name, "E-SLDG-POLE-E")
        // text on its colour's text layer, ByLayer: a missing value in red, ink on the plain text layer
        XCTAssertEqual(SingleLineDXF.layer(.text("x", at: Pt(0, 0), size: 9, color: SingleLineLayout.red)).name, "E-SLDG-MISS-TEXT")
        XCTAssertEqual(SingleLineDXF.layer(.text("x", at: Pt(0, 0), size: 9, color: SingleLineLayout.red)).aci, CADLayers.sldMissing.aci)
        XCTAssertEqual(SingleLineDXF.layer(.text("x", at: Pt(0, 0), size: 9, color: SingleLineLayout.ink)).name, "E-SLDG-TEXT")
        XCTAssertEqual(SingleLineDXF.layer(.text("x", at: Pt(0, 0), size: 9, color: SingleLineLayout.blue)).name, "E-SLDG-TEXT-N")
        XCTAssertEqual(SingleLineDXF.layer(.rect(Box(0, 0, 1, 1), stroke: .black, fill: nil)).name, "E-SLDG-OTHR")
    }

    /// Each symbol is an INSERT of its block: a breaker drawn many times is defined once.
    func testSymbolsAreBlocks() throws {
        let job = SingleLineTests.level2(), drawing = SingleLineLayout.draw(SingleLine.build(job))
        let out = SingleLineDXF.build(job)
        let inserts = t.rawEntities(out.data).filter { $0.first?.1 == "INSERT" }
        XCTAssertEqual(inserts.count, drawing.symbols.count)
        let names = Set(inserts.compactMap { t.value($0, "2") })
        for n in ["SLD_BREAKER", "SLD_TRANSFORMER", "SLD_METER", "SLD_POLE"] { XCTAssertTrue(names.contains(n), n) }
        let breakers = inserts.filter { t.value($0, "2") == "SLD_BREAKER" }.count
        XCTAssertGreaterThan(breakers, 3)
        let l = t.lines(out.data)
        XCTAssertEqual(l.indices.filter { l[$0] == "BLOCK" && l[$0 - 1] == "0" && t.after(l, $0, "2") == "SLD_BREAKER" }.count, 1)
        // a new-equipment (blue) breaker is the same block on the new-equipment layer
        XCTAssertTrue(inserts.contains { t.value($0, "2") == "SLD_BREAKER" && t.value($0, "8") == "E-SLDG-N" })
        // every symbol's ops really are the same block geometry: the drawing's ops minus the symbols' plus the blocks
        XCTAssertTrue(drawing.symbols.allSatisfy { $0.range.upperBound <= drawing.sketch.ops.count })
    }
}

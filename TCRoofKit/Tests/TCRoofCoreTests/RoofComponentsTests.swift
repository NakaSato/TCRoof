import XCTest
@testable import TCRoofCore

/// The quality check against the team's roof section (`Roof section eave ceiling.dxf`, `roof-components.json`): the
/// same roof drawn by the app keeps the drawing's measures, and the CAD export draws its purlins and ridge cap with the
/// team's own blocks.
final class RoofComponentsTests: XCTestCase {
    /// The reference roof: ชายคาฝ้า, 7.00 m between the posts, 15°, the head at +5.25, the eave 2.28 m, C-150 rafters
    /// and tie, C-100 purlins @1.00.
    func roof() -> Values {
        var v = Values()
        Roof.setSpans(&v, .x, [4, 4, 4]); Roof.setSpans(&v, .y, [7]); Roof.setRidge(&v, .h); Roof.setFrame(&v, .eaveCeiling)
        Roof.setLength(&v, Roof.Key.clearHeight, 5.25); Roof.setLength(&v, Roof.Key.overhang, 2.28)
        Roof.setMember(&v, 1, size: "C-100x50x20x3.2"); Roof.setMember(&v, 2, size: "C-150x50x20x3.2"); Roof.setMember(&v, 3, size: "C-150x50x20x3.2")
        return v
    }

    func testTheComponentsShip() throws {
        let c = try XCTUnwrap(RoofComponents.shared)
        XCTAssertEqual(c.components["purlin_c"]?.lines.count, 12)
        XCTAssertEqual(c.components["purlin_c"]?.size ?? [], [0.1, 0.05])
        XCTAssertFalse(c.components["ridge_cap"]?.lines.isEmpty ?? true)
    }

    func testTheSectionKeepsTheDrawingsMeasures() throws {
        let k = try XCTUnwrap(RoofComponents.shared?.checks), v = roof(), m = RoofSection.structure(v), base = 5.25
        func check(_ key: String, _ value: Double, accuracy: Double = 0.001, file: StaticString = #filePath, line: UInt = #line) {
            guard let want = k[key] else { return XCTFail("no \(key)", file: file, line: line) }
            XCTAssertEqual(value, want, accuracy: accuracy, key, file: file, line: line)
        }
        XCTAssertEqual(Roof.slope(v), k["pitch"] ?? 0, accuracy: 1e-9)
        let rafter = try XCTUnwrap(m.members.first { $0.row == 2 }), tie = try XCTUnwrap(m.members.first { $0.row == 3 })
        check("rafterDepth", rafter.depth); check("rafterLip", rafter.lip ?? 0); check("rafterLipBottom", rafter.lip ?? 0)
        XCTAssertEqual(rafter.lipLines.count, 2, "a lip line inside each face")
        check("tieDepth", tie.depth); check("tieLip", tie.lip ?? 0)
        // purlins: their depth, their spacing along the slope, and the sheet resting on them
        let purlins = m.cuts.filter { $0.row == 1 && $0.at.x < 3.5 }.sorted { $0.at.x < $1.at.x }
        check("purlinDepth", try XCTUnwrap(purlins.first).profile.h)
        let gaps = zip(purlins, purlins.dropFirst()).map { hypot($1.at.x - $0.at.x, $1.at.y - $0.at.y) }
        for g in gaps { check("purlinSpacing", g) }
        check("sheetThickness", StructureSection.sheetThickness)
        // the sheet's underside over the rafter's top face, square to the slope, at the first purlin
        let p = purlins[0], sheetTop = m.sheet[0], n = p.up
        let overFace = (sheetTop.x - p.at.x) * n.x + (sheetTop.y - p.at.y) * n.y - StructureSection.sheetThickness
        check("sheetOverRafter", overFace)
        // the eave strut: the rafter's section, its top 0.167 m under the head
        let strut = try XCTUnwrap(m.members.first { $0.row == nil && $0.path.count == 2 && abs($0.path[0].y - $0.path[1].y) < 1e-9 && $0.path[1].x <= 0 && $0.depth > 0.1 })
        // (the head as the drawing measures it: where the rafter's underside crosses the post's outer face)
        let post = try XCTUnwrap(m.posts.first), head = base - post.width / 2 * tan(15 * Double.pi / 180)
        check("strutDepth", strut.depth); check("strutTopUnderHead", head - (strut.path[0].y + strut.depth / 2))
        // its end cut along the rafter's underside: the top and bottom corners on that line
        let o = strut.outline, under: (Pt) -> Double = { base + $0.x * tan(15 * Double.pi / 180) }
        XCTAssertEqual(o[0].y, under(o[0]), accuracy: 1e-9); XCTAssertEqual(o[o.count - 1].y, under(o[o.count - 1]), accuracy: 1e-9)
        // the post and the beam on it, and the soffit under the head (from the eave's own depth: 0.05 m tolerance)
        check("postWidth", try XCTUnwrap(m.posts.first).width)
        let beam = try XCTUnwrap(m.cuts.first { $0.row == 4 })
        check("beamDepth", beam.profile.h); check("beamWidth", beam.profile.b)
        check("soffitUnderHead", base - beam.at.y, accuracy: 0.05)
    }

    func testTheExportUsesTheTeamsBlocks() throws {
        let t = DXFRead(), v = roof(), d = RoofDXF.build(v, parts: [.section]).data, raw = t.rawEntities(d)
        let purlins = raw.filter { $0.first?.1 == "INSERT" && t.value($0, "2") == "RF_PURLIN_C" }
        XCTAssertEqual(purlins.count, RoofSection.structure(v).cuts.filter { $0.row == 1 }.count)
        XCTAssertTrue(purlins.allSatisfy { t.value($0, "8") == "S-ROOF-PURL-E" })
        // the left slope's as drawn, the right's mirrored
        func xScale(_ e: [(String, String)]) -> Double { Double(t.value(e, "41") ?? "1") ?? 1 }
        XCTAssertTrue(purlins.contains { xScale($0) > 0 } && purlins.contains { xScale($0) < 0 })
        XCTAssertEqual(raw.filter { $0.first?.1 == "INSERT" && t.value($0, "2") == "RF_RIDGE_CAP" }.count, 1)
        // no loose purlin outlines left on the purlin layer
        XCTAssertFalse(raw.contains { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == "S-ROOF-PURL-E" })
        // a steep roof keeps its own cap: the team's is drawn at 15°
        var steep = v; Roof.setFrame(&steep, .rafterTie)
        XCTAssertFalse(t.rawEntities(RoofDXF.build(steep, parts: [.section]).data).contains { t.value($0, "2") == "RF_RIDGE_CAP" })
    }
}

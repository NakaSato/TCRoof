import XCTest
@testable import TCRoofCore

/// docs/specs/cad-export-dxf phase 3: the A2 site plan as DXF.
final class SiteDXFTests: XCTestCase {
    let t = SketchDXFTests()
    func layerOf(_ e: [(String, String)]) -> String? { t.value(e, "8") }

    /// A 2000 × 1000 px picture 100 m across, with a 40 × 20 m tank model in the middle, a cable route, a measure line,
    /// a crane entry, a shaded area and two symbols.
    static func sample(scaled: Bool = true) -> Job {
        var tank = SurveyModule(type: .tank, name: "1")
        tank.values["spansX"] = .text("10,10,10,10")
        tank.values["spansY"] = .text("10,10")
        var j = Job(modules: [tank])
        j.values["docNo"] = .text("6901"); j.values["projectName"] = .text("สถานีทดสอบ")
        j.values["siteMap"] = .photo(Photo(fileName: "site.jpg", width: 2000, height: 1000))
        if scaled { j.values[SiteShapes.scaleKey] = .text("100") }
        SiteModels.setModels([SiteModel(id: tank.id.uuidString, x: 0.5, y: 0.5)], in: &j.values)
        j.values[SiteShapes.key] = .shapes([
            SiteShape(kind: .cableRoute, points: [ShapePoint(0.1, 0.9), ShapePoint(0.3, 0.9), ShapePoint(0.3, 0.6)]),
            SiteShape(kind: .measure, points: [ShapePoint(0, 0.1), ShapePoint(0.5, 0.1)]),
            SiteShape(kind: .craneEntry, points: [ShapePoint(0.9, 0.9), ShapePoint(0.8, 0.7)]),
            SiteShape(kind: .shade, points: [ShapePoint(0.7, 0.1), ShapePoint(0.9, 0.1), ShapePoint(0.9, 0.3)], label: "ร่มเงาต้นไม้"),
        ])
        j.values[ModuleMarks.key] = .marks([MapMark(kind: .meter, x: 0.05, y: 0.5), MapMark(kind: .trafo, x: 0.2, y: 0.5, value: "500")])
        return j
    }

    func testNilWithoutPicture() {
        var j = Self.sample(); j.values["siteMap"] = nil
        XCTAssertNil(SiteDXF.build(j))
    }

    func testFrameAndModelAtRealScale() throws {
        let out = try XCTUnwrap(SiteDXF.build(Self.sample()))
        let l = t.lines(out.data)
        XCTAssertEqual(l[l.firstIndex(of: "$INSUNITS")! + 2], "4")
        XCTAssertEqual(l.suffix(2), ["EOF", ""])
        XCTAssertEqual(l.count % 2, 1, "group-code pairs plus the final line end")
        for name in ["FRAME", "PV_AREA", "CABLE", "MEASURE", "CRANE", "SHADE", "SYMBOL", "NORTH", "TEXT"] {
            XCTAssertTrue(out.layers.contains(name), name)
        }
        let ents = t.entities(out.data)
        // the picture is 100 m × 50 m, from (0, 0)
        let frame = ents.filter { layerOf($0) == "FRAME" }
        XCTAssertEqual(frame.count, 4)
        XCTAssertEqual(frame.flatMap { [t.double($0, "10"), t.double($0, "11")] }.max()!, 100_000, accuracy: 0.01)
        XCTAssertEqual(frame.flatMap { [t.double($0, "20"), t.double($0, "21")] }.max()!, 50_000, accuracy: 0.01)
        // the 40 × 20 m tank centred on the picture: one outline (its tint is not written), name tag above
        let pv = ents.filter { layerOf($0) == "PV_AREA" && $0.first?.1 == "LINE" }
        // its corners are (30, 15) and (70, 35) m
        func corner(_ e: [(String, String)]) -> Bool {
            [t.double(e, "10"), t.double(e, "11")].allSatisfy { abs($0 - 30_000) < 0.5 || abs($0 - 70_000) < 0.5 }
                && [t.double(e, "20"), t.double(e, "21")].allSatisfy { abs($0 - 15_000) < 0.5 || abs($0 - 35_000) < 0.5 }
        }
        XCTAssertEqual(pv.filter(corner).count, 4, "each edge once")
        XCTAssertTrue(ents.contains { layerOf($0) == "PV_AREA" && $0.first?.1 == "TEXT" })
    }

    func testYUpAndMeasureLabel() throws {
        let ents = t.entities(try XCTUnwrap(SiteDXF.build(Self.sample())).data)
        // the cable route's first point is 10% across, 90% down the picture: 10 m, 5 m up
        let cable = ents.filter { layerOf($0) == "CABLE" }
        XCTAssertEqual(cable.count, 2)
        XCTAssertTrue(cable.contains { abs(t.double($0, "10") - 10_000) < 1 && abs(t.double($0, "20") - 5_000) < 1 })
        // the measure line is 50 m and labelled so ("ม" is TIS-620 0xC1)
        XCTAssertTrue(ents.contains { layerOf($0) == "MEASURE" && t.value($0, "1") == "50.0 \u{C1}." })
        // the crane entry is dashed
        XCTAssertTrue(ents.contains { layerOf($0) == "CRANE" && t.value($0, "6") == "DASHED" })
        XCTAssertTrue(ents.contains { layerOf($0) == "TEXT" && (t.value($0, "1") ?? "").hasPrefix("SITE PLAN - 6901 - ") })
    }

    func testWithoutScaleIsPaperSizedAndHasNoModels() throws {
        let out = try XCTUnwrap(SiteDXF.build(Self.sample(scaled: false)))
        XCTAssertFalse(out.layers.contains("PV_AREA"))
        let frame = t.entities(out.data).filter { layerOf($0) == "FRAME" }
        XCTAssertEqual(frame.flatMap { [t.double($0, "10"), t.double($0, "11")] }.max()!, SiteDXF.paperWidth, accuracy: 0.01)
        XCTAssertTrue(t.entities(out.data).contains { layerOf($0) == "MEASURE" && $0.first?.1 == "LINE" })
        XCTAssertFalse(t.entities(out.data).contains { layerOf($0) == "MEASURE" && $0.first?.1 == "TEXT" }, "no length without a scale")
    }
}

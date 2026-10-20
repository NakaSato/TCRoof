import XCTest
@testable import TCRoofCore

/// docs/specs/auto-drawing.md §4.4: the C2 and C3 roof sections from the measured sizes and heights.
final class MeasuredRoofSectionTests: XCTestCase {
    func texts(_ s: Sketch) -> [String] { s.ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { return t }; return nil } }

    /// C3: 8 m wide, ground → ridge 5.00, ground → eave tip 3.00, tips 0.50 out, purlins @ 1.00.
    func house(shape: String = "หลังคาทรงจั่ว", i1: Double? = 500, i2: Double? = 300, angle: Double? = nil) -> SurveyModule {
        var v = Values()
        v["buildingWidth"] = .text("800"); v["buildingLength"] = .text("1200")
        v["roofShape"] = .choice(shape, other: "")
        if let i1 { v["measI1"] = .text(fmt(i1)) }
        if let i2 { v["measI2"] = .text(fmt(i2)) }
        if let angle { v["roofAngle"] = .text(fmt(angle)) }
        v["measH"] = .text("50"); v["measC"] = .text("100"); v["measA"] = .text("120")
        v["structMaterial"] = .choice("โครงสร้างไม้", other: "")
        v["woodRafterF"] = .text("5"); v["woodRafterG"] = .text("15")
        return SurveyModule(type: .house, values: v)
    }

    func testHouseHeightsGiveThePitch() throws {
        let i = try XCTUnwrap(MeasuredRoofSection.input(house()).input)
        // rise 2.00 from the eave tip over 4.00 + 0.50
        let t = atan(2.0 / 4.5)
        XCTAssertEqual(i.span, 8)
        XCTAssertEqual(i.pitch, t * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(i.eave), 3 + 0.5 * tan(t), accuracy: 1e-9)
        XCTAssertEqual(i.rise, 4 * tan(t), accuracy: 1e-9)
        XCTAssertEqual(i.members, [.init(name: "แป", size: ""), .init(name: "จันทัน", size: "ไม้ 5x15 ซม. @120 ซม.")])
        XCTAssertTrue(i.warnings.isEmpty)
        let s = MeasuredRoofSection.sketch(i)
        let tx = texts(s)
        XCTAssertTrue(tx.contains("รูปตัดโครงหลังคา — บ้าน / อาคาร"))
        XCTAssertTrue(tx.contains("1 แป · — ไม่ได้ระบุ —"))
        XCTAssertTrue(tx.contains(TankDrawings.note))
        XCTAssertTrue(tx.contains("ช่วงกว้าง 8.00"))
    }

    func testHouseFallsBackToTheAngle() throws {
        let i = try XCTUnwrap(MeasuredRoofSection.input(house(i1: nil, i2: nil, angle: 20)).input)
        XCTAssertEqual(i.pitch, 20, accuracy: 1e-9)
        XCTAssertNil(i.eave)
        XCTAssertTrue(i.assumed.contains("ไม่ทราบความสูงชายคา"))
        XCTAssertTrue(texts(MeasuredRoofSection.sketch(i)).contains("ไม่ทราบความสูงชายคา"))
        // heights win over an angle more than 10 % off, with a warning
        let both = try XCTUnwrap(MeasuredRoofSection.input(house(angle: 35)).input)
        XCTAssertEqual(both.pitch, atan(2.0 / 4.5) * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(both.warnings.count, 1)
        // nothing to go on
        let none = MeasuredRoofSection.input(house(i1: nil, i2: nil))
        XCTAssertNil(none.input)
        XCTAssertFalse(none.missing.isEmpty)
    }

    func testShapes() throws {
        let shed = try XCTUnwrap(MeasuredRoofSection.input(house(shape: "หลังคาเพิงหมาแหงน")).input)
        XCTAssertEqual(shed.shape, .shed)
        XCTAssertEqual(shed.run, 8)
        XCTAssertEqual(shed.pitch, atan(2.0 / 8.5) * 180 / .pi, accuracy: 1e-9)
        let flat = try XCTUnwrap(MeasuredRoofSection.input(house(shape: "หลังคาคอนกรีต (ดาดฟ้า)", i1: 300, i2: 300)).input)
        XCTAssertEqual(flat.shape, .flat)
        XCTAssertEqual(flat.rise, 0)
        XCTAssertTrue(MeasuredRoofSection.purlins(flat, eave: 3).isEmpty)
        let hip = try XCTUnwrap(MeasuredRoofSection.input(house(shape: "หลังคาทรงปั้นหยา")).input)
        XCTAssertEqual(hip.shape, .hip)
        let curved = try XCTUnwrap(MeasuredRoofSection.input(house(shape: "หลังคาทรงโค้ง")).input)
        let line = MeasuredRoofSection.roofLine(curved, eave: 3)
        XCTAssertEqual(line.first!.x, 0, accuracy: 1e-6); XCTAssertEqual(line.first!.y, 3, accuracy: 1e-6)
        XCTAssertEqual(line[12].y, 3 + curved.rise, accuracy: 1e-6)
        XCTAssertEqual(line.last!.x, 8, accuracy: 1e-6)
        // a ridge below the eave can't be drawn from heights
        XCTAssertNil(MeasuredRoofSection.input(house(i1: 200, i2: 300)).input)
    }

    func testPurlinsSitOnTheSlope() throws {
        // the spec's numbers: B = 16, θ = 15°, s = 1.0 → L = 8.282, 9 purlins plus the ridge (last gap 0.28 > 0.25)
        let i = MeasuredRoofSection.Input(title: "", shape: .gable, span: 16, eave: 4, rise: 8 * tan(15 * Double.pi / 180), overhang: 0,
                                          purlinSpacing: 1, members: [])
        XCTAssertEqual(i.slopeLength, 8.282, accuracy: 1e-3)
        let p = MeasuredRoofSection.purlins(i, eave: 4)
        XCTAssertEqual(p.count, 10 + 9, "10 on the left slope, the ridge shared")
        for q in p { XCTAssertEqual(q.y, 4 + min(q.x, 16 - q.x) * tan(15 * Double.pi / 180), accuracy: 1e-9) }
    }

    func testRoofFormUsesItsHeights() throws {
        var v = Values()
        v["buildingWidth"] = .text("1000")
        v["roofShape"] = .choice("หลังคาทรงจั่ว", other: "")
        var m = SurveyModule(type: .roofForm, values: v)
        XCTAssertEqual(MeasuredRoofSection.input(m).missing, ["ความสูงชายคา", "ความสูงสันหลังคา"])
        m.values[MeasuredRoofSection.Key.eaveHeight] = .text("4"); m.values[MeasuredRoofSection.Key.ridgeHeight] = .text("6")
        m.values["size1"] = .text("C 10x5x2"); m.values["space1"] = .text("100")
        let i = try XCTUnwrap(MeasuredRoofSection.input(m).input)
        XCTAssertEqual(i.rise, 2); XCTAssertEqual(i.eave, 4); XCTAssertEqual(i.purlinSpacing, 1)
        XCTAssertEqual(i.members, [.init(name: "แป", size: "C 10x5x2 ซม. @100 ซม.")])
        XCTAssertNotNil(MeasuredRoofSection.draw(m).sketch)
        XCTAssertNil(MeasuredRoofSection.input(SurveyModule(type: .roof)).input, "C1 has its own section")
    }

    func testEveryOpStaysInsideTheSketch() throws {
        var g = SystemRandomNumberGenerator()
        for n in 0..<50 {
            let shape = ["หลังคาทรงจั่ว", "หลังคาทรงปั้นหยา", "หลังคาเพิงหมาแหงน", "หลังคาทรงโค้ง", "หลังคาคอนกรีต (ดาดฟ้า)"][n % 5]
            let i2 = Double.random(in: 200...600, using: &g), i1 = i2 + Double.random(in: 30...400, using: &g)
            guard let i = MeasuredRoofSection.input(house(shape: shape, i1: i1, i2: i2)).input else { continue }
            let s = MeasuredRoofSection.sketch(i)
            XCTAssertLessThan(s.ops.count, 2000)
            for op in s.ops {
                for p in points(op) {
                    XCTAssertTrue(p.x.isFinite && p.y.isFinite)
                    XCTAssertTrue(p.x >= -1 && p.x <= s.width + 1 && p.y >= -1 && p.y <= s.height + 1, "\(shape) \(p)")
                }
            }
        }
    }

    func points(_ op: DrawOp) -> [Pt] {
        switch op {
        case let .line(a, b, _, _, _): return [a, b]
        case let .polyline(p, _, _, _): return p
        case let .polygon(p, _, _, _): return p
        case let .rect(b, _, _, _): return [Pt(b.x, b.y), Pt(b.maxX, b.maxY)]
        default: return []
        }
    }

    /// `DRAWINGS_SVG_DIR=<dir>` writes each shape's section, the C1 section with a measured pitch and the printed tank
    /// plan and section as SVG, to look at.
    func testWriteSVGs() throws {
        guard let dir = ProcessInfo.processInfo.environment["DRAWINGS_SVG_DIR"] else { return }
        let url = URL(fileURLWithPath: dir)
        for (n, shape) in ["หลังคาทรงจั่ว", "หลังคาเพิงหมาแหงน", "หลังคาทรงโค้ง", "หลังคาคอนกรีต (ดาดฟ้า)"].enumerated() {
            let i = try XCTUnwrap(MeasuredRoofSection.input(house(shape: shape, i1: n == 3 ? 300 : 500)).input)
            try MeasuredRoofSection.sketch(i).svg().write(to: url.appendingPathComponent("c3-\(n).svg"), atomically: true, encoding: .utf8)
        }
        var v = Values()
        Roof.setSpans(&v, .x, [4, 4, 4, 4]); Roof.setSpans(&v, .y, [4, 4]); Roof.setFrame(&v, .pratt); v[Roof.Key.ridgeHeight] = .text("7.5")
        try RoofSection(v).sketch.svg().write(to: url.appendingPathComponent("c1-measured.svg"), atomically: true, encoding: .utf8)
        var t = Values()
        TankDesign.apply(&t, .pwa40x40); Tank.setHeight(&t, 4.5); t[Tank.Key.pos] = .choice(Tank.partly, other: ""); Tank.setExposed(&t, 1.2)
        try XCTUnwrap(TankPlan(t, details: true)).sketch.svg().write(to: url.appendingPathComponent("tank-plan.svg"), atomically: true, encoding: .utf8)
        try XCTUnwrap(TankDrawings.section(t, across: false)).svg().write(to: url.appendingPathComponent("tank-section.svg"), atomically: true, encoding: .utf8)
    }

    func testSchemaKeepsCompletion() throws {
        for t in [ModuleType.house, .roofForm] {
            let f = try XCTUnwrap(Schema.spec(t).groups.flatMap(\.fields).first { $0.id == "roofSection" })
            XCTAssertFalse(f.countable)
        }
        let c2 = Schema.spec(.roofForm).groups.flatMap(\.fields)
        for id in [MeasuredRoofSection.Key.eaveHeight, MeasuredRoofSection.Key.ridgeHeight] {
            XCTAssertTrue(try XCTUnwrap(c2.first { $0.id == id }).optional)
        }
    }
}

import XCTest
@testable import TCRoofCore

/// The tank's printed drawings and report lines (docs/specs/tank-drawing-swift.md §4.3, §5).
final class TankDrawingsTests: XCTestCase {
    func tank(height: Double? = 4.5, position: String = Tank.partly, exposed: Double = 1.2) -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        TankPoints.seed(&v)
        v[Tank.Key.pos] = .choice(position, other: "")
        if let height { Tank.setHeight(&v, height) }
        if position == Tank.partly { Tank.setExposed(&v, exposed) }
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        return v
    }
    func texts(_ s: Sketch) -> [String] { s.ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { return t }; return nil } }

    func testTheLayoutPlanDrawsEveryPanelCutAndPost() throws {
        let v = tank(), l = try XCTUnwrap(TankLayout.current(v))
        let plan = try XCTUnwrap(TankDrawings.layoutPlan(v, l)), base = try XCTUnwrap(TankPlan(v))
        let panels = l.tables.flatMap(\.panels).count, posts = l.builtTables.flatMap(\.posts).count
        XCTAssertEqual(plan.ops.count - base.sketch.ops.count, panels + l.cuts.count + posts + 3)   // and the slope tag's arrow, head and text
        XCTAssertTrue(texts(plan).contains { $0.hasPrefix("แผงลาดลงด้านผนังล่าง") })
    }

    func testSectionsFollowTheGround() throws {
        let partly = texts(try XCTUnwrap(TankDrawings.section(tank(), across: false)))
        XCTAssertTrue(partly.contains("พ้นดิน 1.20"))
        XCTAssertTrue(partly.contains("สูง 4.5"))
        XCTAssertTrue(partly.contains { $0.hasPrefix("รูปตัด 1–1") })
        let buried = texts(try XCTUnwrap(TankDrawings.section(tank(position: Tank.buried), across: true)))
        XCTAssertTrue(buried.contains("ดินถม 0.50"))
        XCTAssertTrue(buried.contains { $0.hasPrefix("รูปตัด 2–2") })
        XCTAssertTrue(texts(try XCTUnwrap(TankDrawings.section(tank(height: nil), across: false))).contains("ใส่ความสูงถังเพื่อวาดรูปตัด"))
        XCTAssertNil(TankDrawings.section(Values(), across: false))
        // the summary (§5.5): 40 × 40 × 4.5, gross
        XCTAssertTrue(partly.contains("40.00 × 40.00 × 4.50 ม. | หลังคา 1,600 ม² | ปริมาตรภายนอกโดยประมาณ 7,200 ม³"))
        XCTAssertTrue(partly.contains { $0.contains(TankDrawings.note) })
    }

    func testTheRowSectionShowsTheStandard() {
        let t = texts(TankDrawings.tableSection(TankLayout.Params()))
        for s in ["2.80", "2.70", "1.00", "2.00", "เอียง 19.7°"] { XCTAssertTrue(t.contains(s), s) }
        XCTAssertTrue(t.contains { $0.contains("อยู่ใต้แผงได้") })
    }

    func testReportLinesAndEnergy() throws {
        var v = tank()
        let l = try XCTUnwrap(TankLayout.current(v))
        XCTAssertTrue(l.summaryLine(latitude: 15, facing: nil).hasPrefix("ผังแผงอัตโนมัติ \(l.count) แผง"))
        XCTAssertTrue(l.boqLine.contains("เสา \(l.bom.posts)"))
        XCTAssertTrue(l.checksLine.hasPrefix("ตรวจ \(l.checks.passed)/3"))
        // south-facing panels yield more than north-facing ones
        XCTAssertGreaterThan(l.yield(latitude: 15, facing: 180), l.yield(latitude: 15, facing: 0))
        XCTAssertNil(TankLayout.facing(v))
        XCTAssertEqual(TankLayout.assumptions(v, latitude: nil).count, 3)
        Tank.setAzimuth(&v, 10, source: .compass, accuracy: 3)
        // the top wall faces 10°, so the bottom wall faces 190°: the panels slope down to it
        XCTAssertEqual(try XCTUnwrap(TankLayout.facing(v)), 190, accuracy: 1e-9)
    }
}

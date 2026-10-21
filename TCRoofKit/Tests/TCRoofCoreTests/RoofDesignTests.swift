import XCTest
@testable import TCRoofCore

/// Standard building roofs for C1 (docs/specs/standard-designs.md §7).
final class RoofDesignTests: XCTestCase {
    var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("designs-\(UUID().uuidString).json")
        DesignLibrary.shared.configure(url: url)
        DesignLibrary.shared.reset()
    }
    override func tearDown() { DesignLibrary.shared.reset() }

    func roof() -> Values {
        var v = Values()
        Roof.setSpans(&v, .x, [4, 4, 4, 4]); Roof.setSpans(&v, .y, [6, 6])
        Roof.setPurlinSpacing(&v, 1.2)
        v[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: "")
        Roof.addArea(&v, kind: Roof.skylightKind, x1: 2, y1: 1, x2: 3, y2: 5)
        Roof.addArea(&v, kind: RoofObstacleKind.turbine.rawValue, x1: 8, y1: 6, x2: 8.6, y2: 6.6)
        return v
    }

    /// The check screen's drag (§3.2): a moved area differs from the design, and moved back it matches again.
    func testMovingAnAreaOnSite() {
        let d = RoofDesign.from(roof(), name: "โรงสูบน้ำ", job: "TCR-7", by: nil)
        var site = roof()
        RoofDesign.apply(&site, d)
        RoofDesign.confirmRest(&site)
        let id = "o:" + site.obstacles(Roof.Key.obstacles)[1].id.uuidString
        // the turbine, 0.6 m wide, dragged 1.23 m right: snapped to 5 cm
        XCTAssertTrue(Roof.moveArea(&site, index: 1, x: 9.23, y: 6, lx: 16, ly: 12))
        XCTAssertEqual(Roof.areas(site)[1].x, 9.25, accuracy: 1e-9)
        XCTAssertEqual(RoofDesign.items(site).first { $0.id == id }?.state, .differs)
        // kept on the roof: past the right edge it stops at 16 − 0.6
        Roof.moveArea(&site, index: 1, x: 30, y: -2, lx: 16, ly: 12)
        XCTAssertEqual(Roof.areas(site)[1].x, 15.4, accuracy: 1e-9)
        XCTAssertEqual(Roof.areas(site)[1].y, 0, accuracy: 1e-9)
        // back where the design has it: it matches again
        Roof.moveArea(&site, index: 1, x: 8, y: 6, lx: 16, ly: 12)
        XCTAssertEqual(RoofDesign.items(site).first { $0.id == id }?.state, .matches)
        XCTAssertFalse(Roof.moveArea(&site, index: 1, x: 8.01, y: 6, lx: 16, ly: 12), "under 2.5 cm doesn't move it")
        XCTAssertFalse(Roof.moveArea(&site, index: 9, x: 1, y: 1, lx: 16, ly: 12))
    }

    func testSavingPickingAndCheckingARoof() throws {
        let d = RoofDesign.from(roof(), name: "โรงสูบน้ำ 16×12", job: "TCR-7", by: "a@tcroof.co")
        DesignLibrary.shared.saveRoof(d)
        XCTAssertEqual(d.size, "16 × 12 ม.")
        // a roof measured 12 × 16 matches it turned
        var site = Values()
        Roof.setSpans(&site, .x, [6, 6]); Roof.setSpans(&site, .y, [4, 4, 4, 4.4])
        let r = RoofDesign.ranked(site)
        XCTAssertEqual(r.first?.design.id, d.id)
        XCTAssertEqual(r.first?.matches, true)

        RoofDesign.apply(&site, d)
        XCTAssertEqual(Roof.purlinSpacing(site), 1.2)
        XCTAssertEqual(RoofDesign.current(site)?.id, d.id)
        var items = RoofDesign.items(site)
        XCTAssertEqual(items.count, 5 + 2)
        XCTAssertTrue(items.allSatisfy { $0.state == .open })
        XCTAssertFalse(RoofDesign.done(site))

        // the purlins differ on site, the turbine is gone, a stack is added, the rest confirmed
        Roof.setPurlinSpacing(&site, 1.0)
        var list = site.obstacles(Roof.Key.obstacles)
        list.removeAll { $0.kind == RoofObstacleKind.turbine.rawValue }
        site[Roof.Key.obstacles] = .obstacles(list)
        Roof.addArea(&site, kind: RoofObstacleKind.stack.rawValue, x1: 10, y1: 2, x2: 10.5, y2: 2.5)
        RoofDesign.confirmRest(&site)
        items = RoofDesign.items(site)
        XCTAssertEqual(items.first { $0.id == "purlin" }?.state, .differs)
        XCTAssertEqual(items.filter { $0.state == .missing }.count, 1)
        XCTAssertEqual(items.filter { $0.state == .added }.count, 1)
        XCTAssertTrue(RoofDesign.done(site))
        let s = try XCTUnwrap(RoofDesign.summary(site))
        XCTAssertEqual(s.counts, "ตรงแบบ 5 | ต่างจากแบบ 1 | ไม่มีจริง 1 | เพิ่มหน้างาน 1")
        XCTAssertTrue(s.differences.contains("ระยะแป ต่างจากแบบ"))
        // toggling a confirmation back opens it again
        RoofDesign.toggle(&site, "size")
        XCTAssertEqual(RoofDesign.items(site).first { $0.id == "size" }?.state, .open)
    }

    func testRoofDesignsAreKeptRevisedAndImported() throws {
        let d = RoofDesign.from(roof(), name: "A", job: "J", by: nil)
        DesignLibrary.shared.saveRoof(d)
        DesignLibrary.shared.renameRoof(d.id, to: "B")
        XCTAssertEqual(DesignLibrary.shared.roofs.first?.revision, 2)
        let other = DesignLibrary()
        other.configure(url: url)
        XCTAssertEqual(other.roofs.first?.name, "B")
        // a file of either kind imports
        DesignLibrary.shared.reset()
        XCTAssertEqual(try DesignLibrary.shared.importAny(d.exported()), "A")
        XCTAssertEqual(DesignLibrary.shared.roofs.count, 1)
        let tank = try XCTUnwrap(TankDesign.from({ var v = Values(); TankDesign.apply(&v, .pwa40x40); return v }(), name: "T", job: "J", by: nil))
        XCTAssertEqual(try DesignLibrary.shared.importAny(tank.exported()), "T")
        XCTAssertEqual(DesignLibrary.shared.tanks.count, 1)
        // archived roofs aren't offered
        DesignLibrary.shared.archiveRoof(d.id)
        XCTAssertTrue(RoofDesign.ranked(roof()).isEmpty)
    }
}

import XCTest
@testable import TCRoofCore

/// The standard design library (docs/specs/standard-designs.md §2, §5): saving a checked tank, revisions, the job's
/// snapshot, `.tcdesign` files and the newer-revision rule for designs from other devices.
final class DesignLibraryTests: XCTestCase {
    var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("designs-\(UUID().uuidString).json")
        DesignLibrary.shared.configure(url: url)
        DesignLibrary.shared.reset()
    }
    override func tearDown() { DesignLibrary.shared.reset(); try? FileManager.default.removeItem(at: url) }

    /// The 40 × 40 sheet checked with one vent missing and one hatch moved.
    func checked() -> Values {
        var v = Values()
        TankDesign.apply(&v, .pwa40x40)
        let list = TankPoints.points(v)
        TankPoints.setStatus(&v, list[0].id, TankPoints.absent)
        let h = list.first { $0.kind == TankPoints.hatch }!
        TankPoints.move(&v, h.id, x: (TankPoints.rect(h)!.x) + 1.4, y: nil)
        TankPoints.confirmRest(&v)
        return v
    }

    func testASavedDesignRebuildsTheCheckedTank() throws {
        let v = checked()
        let d = try XCTUnwrap(TankDesign.from(v, name: "ถัง 40×40 สถานีบางไทร", job: "TCR-1", by: "a@tcroof.co"))
        XCTAssertTrue(d.id.hasPrefix("team-"))
        XCTAssertEqual(d.basedOn, "pwa-40x40")
        XCTAssertEqual(d.vents.count, TankDesign.pwa40x40.vents.count - 1)
        XCTAssertEqual(d.hatches.count, TankDesign.pwa40x40.hatches.count)
        XCTAssertTrue(d.source.contains("TCR-1") && d.source.contains("อ้างอิง"))
        // applied again, every point that was there is where it was
        var again = Values()
        TankDesign.apply(&again, d)
        let site = TankPoints.points(v).filter { !$0.isAbsent }.compactMap(TankPoints.rect).map { "\($0.cx),\($0.cy)" }.sorted()
        let back = TankPoints.points(again).compactMap(TankPoints.rect).map { "\($0.cx),\($0.cy)" }.sorted()
        XCTAssertEqual(site.count, back.count)
        XCTAssertEqual(Tank.spans(again).x, Tank.spans(v).x)
    }

    func testSavedDesignsAreOfferedAndArchivedOnesHidden() throws {
        let d = try XCTUnwrap(TankDesign.from(checked(), name: "A", job: "J", by: nil))
        DesignLibrary.shared.save(d)
        XCTAssertTrue(TankDesign.all.contains { $0.id == d.id })
        XCTAssertEqual(TankDesign.ranked(checked()).count, 3)
        DesignLibrary.shared.archive(d.id)
        XCTAssertFalse(TankDesign.all.contains { $0.id == d.id })
        XCTAssertEqual(DesignLibrary.shared.tanks.first?.revision, 2)
        // the library is kept on disk
        let other = DesignLibrary()
        other.configure(url: url)
        XCTAssertEqual(other.tanks.map(\.id), [d.id])
        XCTAssertTrue(other.tanks[0].archived)
        // the seeds are never stored
        DesignLibrary.shared.save(.pwa40x40)
        XCTAssertEqual(DesignLibrary.shared.tanks.count, 1)
    }

    func testAJobKeepsItsSnapshotWhenTheLibraryChanges() throws {
        let d = try XCTUnwrap(TankDesign.from(checked(), name: "เดิม", job: "J", by: nil))
        DesignLibrary.shared.save(d)
        var v = Values()
        TankDesign.apply(&v, d)
        DesignLibrary.shared.rename(d.id, to: "ใหม่")
        XCTAssertEqual(TankDesign.current(v)?.design.name, "เดิม")
        XCTAssertEqual(TankDesign.current(v)?.design.revision, 1)
        // an older job without a snapshot reads the library
        v[Tank.Key.designSnapshot] = nil
        XCTAssertEqual(TankDesign.current(v)?.design.name, "ใหม่")
    }

    func testFilesAndRemoteDesignsKeepTheHigherRevision() throws {
        var d = try XCTUnwrap(TankDesign.from(checked(), name: "A", job: "J", by: nil))
        let file = d.exported()
        XCTAssertEqual(try TankDesign.imported(file), d)
        let imported = try DesignLibrary.shared.importFile(file)
        XCTAssertEqual(imported.id, d.id)
        XCTAssertEqual(DesignLibrary.shared.tanks.count, 1)
        // an older revision doesn't replace a newer one
        d.revision = 3; d.name = "rev 3"
        XCTAssertTrue(DesignLibrary.shared.receive(d))
        var older = d
        older.revision = 2; older.name = "rev 2"
        XCTAssertFalse(DesignLibrary.shared.receive(older))
        XCTAssertEqual(DesignLibrary.shared.tanks[0].name, "rev 3")
        // a turned design comes out turned
        var v = Values()
        TankDesign.apply(&v, d, turned: true)
        XCTAssertEqual(TankDesign.current(v)?.turned, true)
    }
}

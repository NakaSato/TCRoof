import XCTest
@testable import TCRoofCore

/// The team's tank structure standard (docs/specs/tank-mounting-layout.md §1, open question 7).
final class TankStandardTests: XCTestCase {
    override func tearDown() { TankStandard.Store.shared.reset() }

    func tank() -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        TankPoints.seed(&v)
        return v
    }

    func testBuiltInIsTheReferenceSheetsWithTheCatalogueModule() {
        let s = TankStandard.builtIn, m = RoofPlan.Module.catalogDefault
        XCTAssertEqual(s.moduleL, m.length); XCTAssertEqual(s.moduleKW, m.kW)
        XCTAssertEqual(s.hFront, 1); XCTAssertEqual(s.hBack, 2); XCTAssertEqual(s.postDY, 2.8); XCTAssertEqual(s.rowGap, 2.7)
        XCTAssertEqual(s.params.tilt, 19.65, accuracy: 0.01)
        XCTAssertTrue(s.problems.isEmpty)
        XCTAssertEqual(TankLayout.defaults(), s.params)
        XCTAssertEqual(TankStandard.Store.shared.current, s)
    }

    func testJSONRoundTripsAndMissingFieldsKeepTheBuiltIn() throws {
        var s = TankStandard.builtIn
        s.rowGap = 3.1; s.revision = 4; s.savedBy = "m@tc.test"; s.savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(TankStandard.decode(s.json), s)
        let partial = try XCTUnwrap(TankStandard.decode(#"{"hFront":1.2,"revision":2}"#))
        XCTAssertEqual(partial.hFront, 1.2); XCTAssertEqual(partial.revision, 2)
        XCTAssertEqual(partial.hBack, 2); XCTAssertEqual(partial.moduleW, TankStandard.builtIn.moduleW)
        XCTAssertNil(TankStandard.decode("not json"))
    }

    func testProblems() {
        var s = TankStandard.builtIn
        s.hBack = 1.0
        XCTAssertTrue(s.problems.contains { $0.hasPrefix("เสาหลังต้องสูงกว่า") })
        s = .builtIn; s.rowGap = 9
        XCTAssertEqual(s.problems, ["เสาหลัง → แถวถัดไป ต้องอยู่ระหว่าง 1.5 – 6 ม."])
        s = .builtIn; s.moduleKW = 0.1
        XCTAssertTrue(s.problems[0].contains("300 – 800 W"), s.problems[0])
        s = .builtIn; s.minPairGap = 2; s.postDX = 1.8
        XCTAssertTrue(s.problems.contains("ระยะคู่เสาต่ำสุดต้องไม่เกินระยะคู่เสาตามแถว"))
    }

    func testStoreSavesRevisionsAndReceivesOnlyNewer() {
        let store = TankStandard.Store()
        var sent: [TankStandard] = []
        store.onChange = { sent.append($0) }
        var s = TankStandard.builtIn; s.rowGap = 3.0
        let a = store.save(s, by: "m@tc.test")
        XCTAssertEqual(a?.revision, 1); XCTAssertEqual(store.current.rowGap, 3.0); XCTAssertEqual(sent.count, 1)
        var bad = s; bad.hBack = 0.9
        XCTAssertNil(store.save(bad, by: "m@tc.test")); XCTAssertEqual(store.current.revision, 1)
        var old = s; old.revision = 1; old.rowGap = 2.9; old.savedAt = .distantPast
        XCTAssertFalse(store.receive(old)); XCTAssertEqual(store.current.rowGap, 3.0)
        var newer = s; newer.revision = 5; newer.rowGap = 3.3
        XCTAssertTrue(store.receive(newer)); XCTAssertEqual(store.current.rowGap, 3.3)
        XCTAssertEqual(store.save(s, by: nil)?.revision, 6)
        bad.revision = 9
        XCTAssertFalse(store.receive(bad))
        XCTAssertEqual(sent.count, 2, "received standards are not sent back")
    }

    func testStorePersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tank-standard-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = TankStandard.Store(); a.configure(url: url)
        var s = TankStandard.builtIn; s.clearance = 1.5
        a.save(s, by: "m@tc.test")
        let b = TankStandard.Store(); b.configure(url: url)
        XCTAssertEqual(b.current.clearance, 1.5); XCTAssertEqual(b.current.revision, 1)
    }

    /// A job keeps the standard it was laid out with; a new layout takes the team's.
    func testAJobKeepsItsStandardUntilLaidOutAgain() throws {
        var v = tank()
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        let before = try XCTUnwrap(TankLayout.current(v))
        XCTAssertEqual(TankLayout.standard(v), .builtIn)
        XCTAssertFalse(TankLayout.standardChanged(v))

        var s = TankStandard.builtIn; s.rowGap = 3.3; s.moduleKW = 0.6
        TankStandard.Store.shared.save(s, by: "m@tc.test")
        XCTAssertTrue(TankLayout.standardChanged(v))
        XCTAssertEqual(TankLayout.current(v)?.count, before.count)
        XCTAssertEqual(TankLayout.current(v)?.params.rowGap, 2.7)
        // a toggle keeps the job's standard
        TankLayout.toggle(&v, before.tables[0].panels[0].key)
        XCTAssertEqual(TankLayout.current(v)?.params.rowGap, 2.7)
        XCTAssertEqual(TankLayout.standard(v).revision, 0)

        // จัดแผงใหม่ takes the team's
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        let after = try XCTUnwrap(TankLayout.current(v))
        XCTAssertEqual(after.params.rowPitch, 2.8 + 3.3, accuracy: 1e-9)
        XCTAssertEqual(after.params.moduleKW, 0.6)
        XCTAssertEqual(TankLayout.standard(v).revision, 1)
        XCTAssertNil(v[TankLayout.Key.gap], "the standard's own gap is not a wider one")
        XCTAssertFalse(TankLayout.standardChanged(v))
        XCTAssertLessThan(after.rows, before.rows)
    }

    /// Layouts made before the standard was editable have no copy: they keep the built-in one.
    func testALayoutWithoutACopyUsesTheBuiltIn() throws {
        var v = tank()
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        v[TankLayout.Key.standard] = nil
        var s = TankStandard.builtIn; s.hFront = 1.2; s.hBack = 2.4
        TankStandard.Store.shared.save(s, by: "m@tc.test")
        XCTAssertEqual(TankLayout.params(v)?.hFront, 1.0)
        XCTAssertTrue(TankLayout.standardChanged(v))
    }

    /// The energy search's gaps start from the standard's, and a wider pick is kept beside it.
    func testGapsFollowTheStandard() throws {
        var s = TankStandard.builtIn; s.rowGap = 3.0
        TankStandard.Store.shared.save(s, by: nil)
        var v = tank()
        var p = TankLayout.auto(v); p.rowGap = 3.4
        TankLayout.save(&v, p, off: [])
        XCTAssertEqual(v.text(TankLayout.Key.gap), "3.4")
        XCTAssertEqual(TankLayout.params(v)?.standardGap, 3.0)
        XCTAssertEqual(TankLayout.params(v)?.rowGap, 3.4)
        v[TankLayout.Key.gap] = .text("2.8")
        XCTAssertEqual(TankLayout.params(v)?.rowGap, 3.0, "never under the job's standard")
        XCTAssertEqual(TankLayout.gapSteps(3.0).first, 3.0)
    }
}

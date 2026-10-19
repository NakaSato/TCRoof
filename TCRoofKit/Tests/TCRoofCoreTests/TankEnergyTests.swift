import XCTest
@testable import TCRoofCore

/// `หาผังที่ได้พลังงานมากที่สุด` and the front elevation (docs/specs/tank-mounting-layout.md §3a, §5).
final class TankEnergyTests: XCTestCase {
    func tank(points: Bool = true, azimuth: Int? = nil) -> Values {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        if points { TankPoints.seed(&v) }
        if let a = azimuth { v[Tank.Key.azimuth] = .text(String(a)) }
        return v
    }

    func testGapsStartAtTheStandardAndGoTwoMetresWider() {
        let g = TankLayout.gapSteps()
        XCTAssertEqual(g.count, 11)
        XCTAssertEqual(g.first, 2.7); XCTAssertEqual(g.last!, 4.7, accuracy: 1e-9)
        XCTAssertEqual(g[2], 3.1, accuracy: 1e-9)
    }

    func testTheSearchNeverMakesLessThanTheStandardGap() throws {
        let v = tank(azimuth: 12)
        let s = try XCTUnwrap(TankLayout.bestEnergy(v, latitude: 17))
        XCTAssertEqual(s.trials.count, 11)
        XCTAssertGreaterThanOrEqual(s.chosen.gap, 2.7 - 1e-9)
        XCTAssertGreaterThanOrEqual(s.chosen.mwh, s.trials[0].mwh)
        XCTAssertTrue(s.trials.allSatisfy { s.chosen.mwh >= $0.mwh - 1e-9 })
        // the standard gap trial is the module max search
        XCTAssertEqual(s.trials[0].modules, TankLayout(v, params: TankLayout.best(v)!)!.count)
        // wider gaps shade less but hold no more modules
        XCTAssertLessThan(s.trials.last!.rowLoss, s.trials[0].rowLoss)
        XCTAssertLessThanOrEqual(s.trials.last!.modules, s.trials[0].modules)
        // the prototype on the กปภ. 40 × 40 tank at 17° N: the standard 2.70 m wins
        XCTAssertEqual(s.chosen.gap, 2.7, accuracy: 1e-9)
        XCTAssertTrue(s.line.hasPrefix("ลองระยะห่างแถว 11 แบบ · เลือก 2.70 ม."))
    }

    func testAStoredGapRoundTripsAndNeverGoesUnderTheStandard() {
        var v = tank()
        var p = TankLayout.auto(v); p.rowGap = 3.1
        TankLayout.save(&v, p, off: [])
        XCTAssertEqual(v.text(TankLayout.Key.gap), "3.1")
        XCTAssertEqual(TankLayout.params(v)!.rowGap, 3.1, accuracy: 1e-9)
        XCTAssertEqual(TankLayout.current(v)!.params.rowPitch, 5.9, accuracy: 1e-9)
        XCTAssertTrue(TankLayout.current(v)!.summaryLine(latitude: 15, facing: nil).hasSuffix("แถวห่าง 3.10 ม."))
        v[TankLayout.Key.gap] = .text("2.0")
        XCTAssertEqual(TankLayout.params(v)!.rowGap, 2.7, accuracy: 1e-9)
        // the automatic layout goes back to the standard and clears the key
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        XCTAssertNil(v[TankLayout.Key.gap])
        XCTAssertFalse(TankLayout.current(v)!.summaryLine(latitude: 15, facing: nil).contains("แถวห่าง"))
    }

    func testNetEnergyIsTheUnshadedLessTheLosses() {
        var v = tank(points: false)
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        let s = TankShade(v, latitude: 17)!
        XCTAssertEqual(s.netMWh, s.energy * (1 - s.totalLoss), accuracy: 1e-9)
        XCTAssertLessThan(s.netMWh, s.energy)
    }

    func testFrontElevationOfTheLongestTable() throws {
        for az in [nil, 12, 100, 200, 280] {
            var v = tank(azimuth: az)
            TankLayout.save(&v, TankLayout.auto(v), off: [])
            let l = TankLayout.current(v)!
            let sk = try XCTUnwrap(TankDrawings.tableFront(l))
            let texts = sk.ops.compactMap { op -> String? in if case .text(let s, _, _, _, _, _, _) = op { return s }; return nil }
            let t = l.builtTables.max { $0.columns < $1.columns }!
            XCTAssertTrue(texts.contains { $0.contains("\(t.columns) คอลัมน์") }, "az \(String(describing: az))")
            XCTAssertTrue(texts.contains { $0.hasPrefix("เสา \(t.pairs) คู่") })
            XCTAssertTrue(texts.contains(String(format: "ยาว %.2f", l.params.width(t.columns))))
            // the bays and the cantilevers wide enough to label add up to the length, less at most the two cantilevers
            let parts = texts.compactMap { Double($0) }.filter { $0 > 0.05 && $0 < 3 && $0 != l.params.hFront }
            let sum = parts.reduce(0, +), L = l.params.width(t.columns)
            XCTAssertLessThanOrEqual(sum, L + 0.01 * Double(parts.count))
            XCTAssertGreaterThanOrEqual(sum, L - 2 * l.params.maxCantilever - 0.01 * Double(parts.count))
        }
        XCTAssertNil(TankDrawings.tableFront(TankLayout(size: (2, 2), turn: 0, openings: [], params: TankLayout.defaults(), off: [])))
    }
}

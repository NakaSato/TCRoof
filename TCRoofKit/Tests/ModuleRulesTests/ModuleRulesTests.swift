import XCTest
@testable import ModuleRules

/// docs/specs/module-install-rules.md §6: the calculation table and the tilt boundaries.
final class ModuleRulesTests: XCTestCase {
    /// The spec's example: ZXM6-NH144-445/M, Voc 50.1 V, Isc 11.40 A, β −0.28 %/°C (illustrative), L 2094 mm.
    static let nh144 = ModuleModel(id: "ZXM6-NH144-445/M", cellCount: 144, pmaxW: 445, vmpV: 41.4, impA: 10.75, vocV: 50.1,
                                   iscA: 11.40, lengthMm: 2094, widthMm: 1038, betaVocPctPerC: -0.28)
    static var noBeta: ModuleModel { var m = nh144; m.betaVocPctPerC = nil; return m }
    static let small = ModuleModel(id: "ZXM6-60", cellCount: 60, pmaxW: 330, vmpV: 34, impA: 9.7, vocV: 41, iscA: 10.2,
                                   lengthMm: 1650, widthMm: 992, betaVocPctPerC: -0.29)

    func testMaxModulesInSeries() {
        XCTAssertEqual(ModuleRules.maxModulesInSeries(module: Self.nh144, tMinC: 15, inverterMaxDcV: nil), 29)
        XCTAssertEqual(ModuleRules.maxModulesInSeries(module: Self.nh144, tMinC: 15, inverterMaxDcV: 1100), 21)
        XCTAssertNil(ModuleRules.maxModulesInSeries(module: Self.noBeta, tMinC: 15, inverterMaxDcV: nil))
        XCTAssertEqual(ModuleRules.coldVoc(module: Self.nh144, tMinC: 15)!, 51.5, accuracy: 0.01)
    }

    func testMinCableAmpacity() {
        XCTAssertEqual(ModuleRules.minCableAmpacity(module: Self.nh144, parallelCount: 1), 14.25, accuracy: 1e-9)
        XCTAssertEqual(ModuleRules.minCableAmpacity(module: Self.nh144, parallelCount: 2), 28.5, accuracy: 1e-9)
    }

    func testRecommendedTiltAndItsBoundaries() {
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 13.7), 15)
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 18.8), 18.8, accuracy: 1e-9)
        // the boundaries take the row above: 15° → latitude, 25° → +5, 30° → +10, 35° → +15, 40° → +20
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 14.99), 15)
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 15), 15)
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 25), 30)
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 30), 40)
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 35), 50)
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: 40), 60)
        XCTAssertEqual(ModuleRules.recommendedTilt(latitude: -20), 20, "the southern hemisphere by |latitude|")
    }

    func testClampZone() {
        XCTAssertEqual(ModuleRules.clampZone(module: Self.nh144, side: .long), 473.5...573.5)
        XCTAssertNil(ModuleRules.clampZone(module: Self.nh144, side: .short), "144 cells: short side not rated")
        XCTAssertEqual(ModuleRules.clampZone(module: Self.small, side: .short), (992.0 / 5 - 50)...(992.0 / 5 + 50))
    }

    func testSizeClass() {
        for n in [72, 78, 144, 156] { XCTAssertEqual(SizeClass(cellCount: n), .big) }
        for n in [60, 66, 120, 132] { XCTAssertEqual(SizeClass(cellCount: n), .small) }
    }
}

/// The bundled data: catalog, mounting profiles (source §5.5) and the rule set.
final class ModuleCatalogTests: XCTestCase {
    func testTheCatalogLoads() throws {
        XCTAssertFalse(ModuleCatalog.models.isEmpty)
        XCTAssertEqual(Set(ModuleCatalog.models.map(\.id)).count, ModuleCatalog.models.count, "ids are unique")
        let m = try XCTUnwrap(ModuleCatalog.model("ZXM7-UHLDD144-570"))
        XCTAssertEqual(m.sizeClass, .big)
        XCTAssertEqual(m.vocV, 51.1); XCTAssertEqual(m.iscA, 14.23)
        XCTAssertEqual(m.lengthMm, 2278); XCTAssertEqual(m.widthMm, 1134)
        XCTAssertEqual(m.betaVocPctPerC, -0.25)
        XCTAssertTrue(m.bifacial && m.doubleGlass)
        for m in ModuleCatalog.models { XCTAssertGreaterThan(m.pmaxW, 0); XCTAssertGreaterThan(m.lengthMm, m.widthMm) }
    }

    func testMountingProfilesFollowTheManual() throws {
        XCTAssertEqual(Set(ModuleCatalog.profiles.map(\.method)), Set(MountingMethod.allCases))
        let bolt = try XCTUnwrap(ModuleCatalog.profile(.bolt))
        XCTAssertEqual(bolt.torqueNm, 16...20)
        XCTAssertEqual(bolt.washerMinThicknessMm, 1.8); XCTAssertEqual(bolt.washerOdMm, 20...24)
        XCTAssertEqual(bolt.load(cellCount: 144)?.pushPa, 3600); XCTAssertEqual(bolt.load(cellCount: 144)?.pullPa, 1600)
        XCTAssertEqual(bolt.load(cellCount: 156)?.pushPa, 2400)
        let tracker = try XCTUnwrap(ModuleCatalog.profile(.tracker1P))
        XCTAssertEqual(tracker.washerMinThicknessMm, 1.5); XCTAssertEqual(tracker.washerOdMm, 16...20)
        let clamp = try XCTUnwrap(ModuleCatalog.profile(.clamp))
        XCTAssertEqual(clamp.load(cellCount: 144, side: .long)?.pushPa, 3600)
        XCTAssertNil(clamp.load(cellCount: 144, side: .short), "big modules: no short-side rating")
        XCTAssertEqual(clamp.load(cellCount: 60, side: .short)?.pushPa, 1050)
        XCTAssertNil(ModuleCatalog.profile(.tracker2V)?.load(cellCount: 78), "78 cells: not in the 2V table")
    }

    /// Every rule of the rule set has a condition in the engine, and every condition a rule; each has both messages.
    func testTheRuleSetAndTheEngineAgree() {
        let ids = ModuleCatalog.rules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "rule ids are unique")
        XCTAssertEqual(Set(ids), RuleEngine.conditions)
        for r in ModuleCatalog.rules {
            XCTAssertFalse(r.message_th.isEmpty, r.id); XCTAssertFalse(r.message_en.isEmpty, r.id); XCTAssertFalse(r.stages.isEmpty, r.id)
        }
        XCTAssertFalse(ModuleCatalog.ruleSetVersion.isEmpty)
    }
}

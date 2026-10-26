import XCTest
@testable import ModuleRules

/// The string test, rules phase 5 (docs/specs/module-install-rules.md §7.4): ZN-132 against the ZXM7-UHLDD144 datasheet
/// (570 W: Voc 51.1 V, β −0.25 %/°C, NMOT 44 °C) and ZN-110 per MPPT.
final class StringTestTests: XCTestCase {
    let m570 = ModuleCatalog.model("ZXM7-UHLDD144-570")!

    func input(_ voc: [Double?], groups: [String]? = nil, light: Double? = 1000, temp: Double? = 65, air: Double? = nil,
               polarity: [Bool?]? = nil, module: ModuleModel?? = nil) -> StringTestInput {
        StringTestInput(module: module ?? m570, irradianceWm2: light, moduleTempC: temp, ambientC: air,
                        strings: voc.enumerated().map { i, v in
                            .init(id: "S\(i + 1)", group: groups?[i] ?? "G\(i + 1)", modules: 16, vocV: v, polarityOK: polarity?[i] ?? true)
                        })
    }

    func testExpectedVocFromTheDatasheet() {
        XCTAssertEqual(ModuleRules.expectedVoc(module: m570, modules: 16, cellTempC: 25)!, 817.6, accuracy: 1e-9)
        XCTAssertEqual(ModuleRules.expectedVoc(module: m570, modules: 16, cellTempC: 65)!, 735.84, accuracy: 1e-9)
        var noBeta = m570; noBeta.betaVocPctPerC = nil
        XCTAssertNil(ModuleRules.expectedVoc(module: noBeta, modules: 16, cellTempC: 65))
    }

    func testNMOTEstimatesTheModuleTemperature() {
        XCTAssertEqual(ModuleRules.cellTemperature(module: m570, ambientC: 34.3, irradianceWm2: 1022)!, 64.96, accuracy: 1e-9)
        var noNMOT = m570; noNMOT.nmotC = nil
        XCTAssertNil(ModuleRules.cellTemperature(module: noNMOT, ambientC: 34.3, irradianceWm2: 1022))
        let t = StringTestCheck(input([750], temp: nil, air: 34.3))
        XCTAssertFalse(t.tempMeasured)
        XCTAssertEqual(t.cellTempC!, 34.3 + 24 * 1000 / 800, accuracy: 1e-9)
        XCTAssertTrue(StringTestCheck(input([750], temp: 58, air: 34.3)).tempMeasured, "a measured temperature wins")
    }

    func testFivePercentFromExpected() {
        // expected 735.84 V: +5 % is 772.6, over it fires
        let pass = RuleEngine.check(input([772.6]))
        let fail = RuleEngine.check(input([773, 735]))
        XCTAssertTrue(pass.results.isEmpty)
        let r = fail.results.first { $0.id == "ZN-132" }
        XCTAssertEqual(r?.severity, .warn)
        XCTAssertEqual(r?.messageTH.contains("(S1)"), true, "names the strings")
        XCTAssertEqual(StringTestCheck(input([699])).flags("S1"), true, "low too")
    }

    func testNotBelow200WPerSquareMetre() {
        let t = StringTestCheck(input([600], light: 150))
        XCTAssertFalse(t.enoughLight)
        XCTAssertFalse(t.flags("S1"))
        XCTAssertTrue(t.validation.results.isEmpty)
        XCTAssertFalse(StringTestCheck(input([600], light: nil)).enoughLight)
    }

    func testParallelGroups() {
        let ok = StringTestCheck(input([750, 760], groups: ["1", "1"]))
        XCTAssertEqual(ok.groups["1"]?.spreadV, 10)
        XCTAssertFalse(ok.validation.results.contains { $0.id == "ZN-110" })
        let far = StringTestCheck(input([750, 760.5], groups: ["1", "1"]))
        XCTAssertEqual(far.validation.blocks.map(\.id), ["ZN-110"])
        let reversed = StringTestCheck(input([750, 750], groups: ["1", "1"], polarity: [true, false]))
        XCTAssertTrue(reversed.groups["1"]!.fails)
        XCTAssertNil(StringTestCheck(input([750, nil], groups: ["1", "1"])).groups["1"], "one reading: nothing to compare")
    }

    func testWithoutACatalogModuleOnlyTheParallelCheck() {
        let t = StringTestCheck(input([600, 650], groups: ["1", "1"], temp: nil, air: 34.3, module: .some(nil)))
        XCTAssertNil(t.cellTempC)
        XCTAssertTrue(t.strings.isEmpty)
        XCTAssertEqual(t.validation.results.map(\.id), ["ZN-110"])
    }

    func testTheIECModuleNameFindsTheCatalogModel() {
        XCTAssertEqual(ModuleCatalog.model(brand: "Znshine", powerW: 570)?.id, "ZXM7-UHLDD144-570")
        XCTAssertEqual(ModuleCatalog.model(brand: "", powerW: 575)?.id, "ZXM7-UHLDD144-575")
        XCTAssertNil(ModuleCatalog.model(brand: "Jinko", powerW: 570))
        XCTAssertNil(ModuleCatalog.model(brand: "Znshine", powerW: 450))
    }
}

import XCTest
@testable import ModuleRules

/// docs/specs/module-install-rules.md §5 and §8: each rule fires on its failing input and stays quiet on its passing one,
/// and the acceptance cases.
final class RuleEngineTests: XCTestCase {
    let nh144 = ModuleRulesTests.nh144, small = ModuleRulesTests.small

    func ids(_ v: Validation) -> Set<String> { Set(v.results.map(\.id)) }

    /// `pass` must not fire `id`, `fail` must; and the result carries the rule set's severity and both messages.
    func expect(_ id: String, pass: Validation, fail: Validation, line: UInt = #line) {
        XCTAssertFalse(ids(pass).contains(id), "\(id) fired on its passing input", line: line)
        guard let r = fail.results.first(where: { $0.id == id }) else { return XCTFail("\(id) didn't fire", line: line) }
        XCTAssertEqual(r.severity, ModuleCatalog.rule(id)?.severity, line: line)
        XCTAssertFalse(r.messageTH.isEmpty || r.messageEN.isEmpty, line: line)
    }

    // MARK: survey

    func testSurveyRules() {
        func site(_ f: (inout SiteInput) -> Void) -> Validation { var s = SiteInput(); f(&s); return RuleEngine.check(s) }
        expect("ZN-70", pass: site { $0.altitudeM = 2000 }, fail: site { $0.altitudeM = 2001 })
        expect("ZN-73a", pass: site { $0.seaDistance = .to1km }, fail: site { $0.seaDistance = .under100m })
        expect("ZN-73b", pass: site { $0.seaDistance = .over1km }, fail: site { $0.seaDistance = .to1km })
        expect("ZN-69", pass: site { $0.humidityPct = 85 }, fail: site { $0.humidityPct = 86 })
        expect("T5-1", pass: site { $0.monthlyMinC = -20; $0.monthlyMaxC = 47 }, fail: site { $0.monthlyMaxC = 48 })
        expect("T5-1", pass: site { $0.monthlyMinC = 20 }, fail: site { $0.monthlyMinC = -21 })
        expect("ZN-77", pass: site { $0.roofFireproof = true }, fail: site { $0.roofFireproof = false })
        expect("ZN-81", pass: site { $0.plannedTiltDeg = 10 }, fail: site { $0.plannedTiltDeg = 9.9 })
        expect("ZN-82", pass: site { $0.latitude = 13.7; $0.plannedTiltDeg = 15 }, fail: site { $0.latitude = 13.7; $0.plannedTiltDeg = 10 })
        expect("ZN-90", pass: site { $0.rearClearanceMm = 120 }, fail: site { $0.rearClearanceMm = 100 })
        XCTAssertTrue(site { _ in }.results.isEmpty, "nothing answered, nothing fires")
    }

    /// The survey's stored record: its input, notes, JSON round trip and an old or empty value.
    func testTheSiteRecord() {
        var c = SiteInstallCheck()
        XCTAssertTrue(c.isEmpty)
        c.altitudeM = 2100; c.highWind = true; c.plannedTiltDeg = 5; c.reasons = ["ZN-81": "หลังคาลาดน้อย"]
        XCTAssertFalse(c.isEmpty)
        XCTAssertEqual(Set(c.validation(latitude: 13.7).results.map(\.id)), ["ZN-70", "ZN-81", "ZN-82"])
        XCTAssertEqual(c.notes.count, 1)
        XCTAssertEqual(SiteInstallCheck.decode(c.json), c)
        XCTAssertEqual(SiteInstallCheck.decode(""), SiteInstallCheck())
        XCTAssertEqual(SiteInstallCheck.decode("{\"altitudeM\":10}").altitudeM, 10, "fields added later decode as nil")
    }

    // MARK: layout

    func layout(_ m: ModuleModel? = nil, _ f: (inout LayoutInput) -> Void) -> Validation {
        var l = LayoutInput(module: m ?? nh144); f(&l); return RuleEngine.check(l)
    }

    func testLayoutRules() {
        expect("ZN-81", pass: layout { $0.tiltDeg = 15 }, fail: layout { $0.tiltDeg = 5 })
        expect("ZN-82", pass: layout { $0.latitude = 18.8; $0.tiltDeg = 18.8 }, fail: layout { $0.latitude = 18.8; $0.tiltDeg = 25 })
        expect("ZN-79", pass: layout { $0.strings = [.uniform(id: "S1", model: "a", count: 10, tilt: 15, azimuth: 180)] },
               fail: layout { $0.strings = [StringPlan(id: "S1", modelIDs: ["a", "a"], tiltsDeg: [15, 20], azimuthsDeg: [180, 180])] })
        expect("ZN-52", pass: layout { $0.landscape = true; $0.clampSide = .long },
               fail: layout { $0.landscape = true; $0.clampSide = .short })
        expect("ZN-53", pass: layout(small) { $0.landscape = true; $0.sharesLongRail = false },
               fail: layout(small) { $0.landscape = true; $0.sharesLongRail = true })
        var bifacial = nh144; bifacial.bifacial = true
        expect("ZN-85", pass: layout(bifacial) { $0.bifacialHeightM = 1 }, fail: layout(bifacial) { $0.bifacialHeightM = 0.3 })
        XCTAssertFalse(ids(layout { $0.bifacialHeightM = 0.3 }).contains("ZN-85"), "only bifacial modules")
        expect("ZN-90", pass: layout { $0.rearClearanceMm = 115 }, fail: layout { $0.rearClearanceMm = 100 })
        expect("ZN-91", pass: layout { $0.gapMm = 10 }, fail: layout { $0.gapMm = 8 })
        expect("ZN-95", pass: layout { $0.clampLengthMm = 60; $0.clampThicknessMm = 3 }, fail: layout { $0.clampLengthMm = 50 })
        expect("ZN-95", pass: layout { $0.clampThicknessMm = 3.5 }, fail: layout { $0.clampThicknessMm = 2.5 })
        expect("ZN-97", pass: layout { $0.clampsPerModule = 4 }, fail: layout { $0.clampsPerModule = 3 })
        expect("S553-zone", pass: layout { $0.clampSide = .long; $0.clampOffsetMm = 500 },
               fail: layout { $0.clampSide = .long; $0.clampOffsetMm = 600 })
        expect("S553-short", pass: layout(small) { $0.clampSide = .short }, fail: layout { $0.clampSide = .short })
        expect("ZN-88", pass: layout { $0.railsPerModule = 2 }, fail: layout { $0.railsPerModule = 1 })
        expect("ZN-105", pass: layout { $0.strings = [.uniform(id: "S1", model: "a", count: 3, tilt: 15, azimuth: 180)] },
               fail: layout { $0.strings = [StringPlan(id: "S1", modelIDs: ["a", "b"])] })
        expect("ZN-106", pass: layout { $0.tMinC = 15; $0.strings = [.uniform(id: "S1", model: "a", count: 29, tilt: 15, azimuth: 180)] },
               fail: layout { $0.tMinC = 15; $0.strings = [.uniform(id: "S1", model: "a", count: 30, tilt: 15, azimuth: 180)] })
        expect("ZN-106b", pass: layout { $0.strings = [.uniform(id: "S1", model: "a", count: 10, tilt: 15, azimuth: 180)] },
               fail: layout(ModuleRulesTests.noBeta) { $0.strings = [.uniform(id: "S1", model: "a", count: 10, tilt: 15, azimuth: 180)] })
        expect("ZN-112", pass: layout { $0.cableAmpacityA = 14.25 }, fail: layout { $0.cableAmpacityA = 14 })
        expect("ZN-112", pass: layout { $0.parallelCount = 2; $0.cableAmpacityA = 30 }, fail: layout { $0.parallelCount = 2; $0.cableAmpacityA = 25 })
        expect("ZN-107", pass: layout { $0.cableMm2 = 4 }, fail: layout { $0.cableMm2 = 2.5 })
        expect("ZN-122", pass: layout { $0.groundingParallel = 4; $0.groundingSeries = 8 }, fail: layout { $0.groundingParallel = 5 })
        expect("ZN-122", pass: layout { $0.groundingSeries = 8 }, fail: layout { $0.groundingSeries = 9 })
    }

    // MARK: installation

    func install(_ f: (inout InstallInput) -> Void) -> Validation { var i = InstallInput(method: .bolt); f(&i); return RuleEngine.check(i) }

    func testInstallRules() {
        expect("S551-torque", pass: install { $0.boltTorquesNm = [16, 18, 20] }, fail: install { $0.boltTorquesNm = [18, 22] })
        expect("S551-torque", pass: install { $0.boltTorquesNm = [16] }, fail: install { $0.boltTorquesNm = [15.5] })
        expect("S551-washer", pass: install { $0.washerThicknessMm = 1.8; $0.washerOdMm = 22 }, fail: install { $0.washerThicknessMm = 1.5 })
        expect("S551-washer", pass: install { $0.washerOdMm = 24 }, fail: install { $0.washerOdMm = 18 })
        // the tracker's washer is thinner and smaller
        XCTAssertFalse(ids({ var i = InstallInput(method: .tracker1P); i.washerThicknessMm = 1.5; i.washerOdMm = 18; return RuleEngine.check(i) }()).contains("S551-washer"))
        expect("S553-overlap", pass: install { $0.clampOverlapMm = 8 }, fail: install { $0.clampOverlapMm = 5 })
        expect("S553-overlap", pass: install { $0.clampOverlapMm = 10 }, fail: install { $0.clampOverlapMm = 11 })
        expect("ZN-97", pass: install { $0.clampsPerModule = 4 }, fail: install { $0.clampsPerModule = 2 })
        expect("ZN-121", pass: install { $0.groundTorquesNm = [4, 8] }, fail: install { $0.groundTorquesNm = [9] })
        expect("ZN-108", pass: install { $0.bendRadiusMm = 43 }, fail: install { $0.bendRadiusMm = 30 })
        expect("ZN-61", pass: install { $0.crewCount = 2 }, fail: install { $0.crewCount = 1 })
        expect("ZN-63", pass: install { $0.frameModified = false }, fail: install { $0.frameModified = true })
        expect("ZN-91", pass: install { $0.gapMm = 12 }, fail: install { $0.gapMm = 5 })
        expect("ZN-90", pass: install { $0.rearClearanceMm = 150 }, fail: install { $0.rearClearanceMm = 80 })
    }

    // MARK: commissioning

    func testParallelStrings() {
        let ok = [StringReading(id: "S1", vocV: 760, polarityOK: true), StringReading(id: "S2", vocV: 770, polarityOK: true)]
        let far = [StringReading(id: "S1", vocV: 760, polarityOK: true), StringReading(id: "S2", vocV: 771, polarityOK: true)]
        let reversed = [StringReading(id: "S1", vocV: 760, polarityOK: true), StringReading(id: "S2", vocV: 760, polarityOK: false)]
        expect("ZN-110", pass: RuleEngine.check(parallel: ok), fail: RuleEngine.check(parallel: far))
        expect("ZN-110", pass: RuleEngine.check(parallel: ok), fail: RuleEngine.check(parallel: reversed))
    }

    // MARK: submit and sign

    func testSubmitNeedsNoBlockAndAReasonPerWarn() {
        let warn = install { $0.rearClearanceMm = 80 }
        XCTAssertEqual(warn.warns.map(\.id), ["ZN-90"])
        XCTAssertFalse(warn.canSubmit(reasons: [:]))
        XCTAssertFalse(warn.canSubmit(reasons: ["ZN-90": "  "]))
        XCTAssertTrue(warn.canSubmit(reasons: ["ZN-90": "หลังคาเตี้ย วัดได้ 80 มม."]))
        XCTAssertTrue(warn.canSign)
        let block = install { $0.boltTorquesNm = [22] }
        XCTAssertFalse(block.canSubmit(reasons: ["S551-torque": "ขันใหม่แล้ว"]))
        XCTAssertFalse(block.canSign)
        XCTAssertEqual(block.ruleSetVersion, ModuleCatalog.ruleSetVersion)
        XCTAssertEqual(block.catalogVersion, ModuleCatalog.version)
    }

    /// Blocks come first in the list, then warns, then hints.
    func testResultsAreSortedBySeverity() {
        let v = RuleEngine.check(SiteInput(latitude: 13.7, altitudeM: 2500, humidityPct: 90, plannedTiltDeg: 5))
        XCTAssertEqual(v.results.map(\.severity), [.block, .warn, .warn, .info])
    }

    // MARK: acceptance cases (§8)

    func testLowTiltAtBangkok() throws {
        let v = RuleEngine.check(SiteInput(latitude: 13.7, plannedTiltDeg: 5))
        XCTAssertEqual(v.results.first { $0.id == "ZN-81" }?.severity, .warn)
        let hint = try XCTUnwrap(v.results.first { $0.id == "ZN-82" })
        XCTAssertTrue(hint.messageEN.contains("15°"), hint.messageEN)
        XCTAssertTrue(hint.messageTH.contains("15°"), hint.messageTH)
    }

    func testBigModuleOnItsShortSide() {
        let v = layout { $0.landscape = true; $0.clampSide = .short }
        XCTAssertTrue(ids(v).contains("ZN-52"))
        XCTAssertFalse(v.canSign)
    }

    func testStringTooLong() throws {
        let v = layout { $0.tMinC = 15; $0.inverterMaxDcV = 1100; $0.strings = [.uniform(id: "S1", model: "a", count: 24, tilt: 15, azimuth: 180)] }
        let r = try XCTUnwrap(v.results.first { $0.id == "ZN-106" })
        XCTAssertEqual(r.severity, .block)
        XCTAssertTrue(r.messageTH.contains("21"), r.messageTH)
    }

    func testMissingBetaBlocksUntilEntered() {
        var m = ModuleRulesTests.noBeta
        let plan = [StringPlan.uniform(id: "S1", model: "a", count: 10, tilt: 15, azimuth: 180)]
        XCTAssertTrue(ids(layout(m) { $0.strings = plan }).contains("ZN-106b"))
        m.betaVocPctPerC = -0.28
        XCTAssertFalse(ids(layout(m) { $0.strings = plan }).contains("ZN-106b"))
    }

    func testTorqueOutOfRangeStopsSignOff() {
        let v = install { $0.boltTorquesNm = [22] }
        XCTAssertTrue(ids(v).contains("S551-torque"))
        XCTAssertFalse(v.canSign)
    }

    /// A report keeps the rule set it was checked with: checking again with an edited rule set changes only a new check.
    func testAnotherRuleSetChangesOnlyANewCheck() {
        var edited = ModuleCatalog.rules
        let i = edited.firstIndex { $0.id == "ZN-90" }!
        edited[i].severity = .block
        let input: InstallInput = { var x = InstallInput(method: .bolt); x.rearClearanceMm = 80; return x }()
        let signed = RuleEngine.check(input)
        XCTAssertEqual(signed.results.first?.severity, .warn)
        XCTAssertEqual(RuleEngine.check(input, rules: edited).results.first?.severity, .block)
        XCTAssertEqual(signed.results.first?.severity, .warn, "the earlier check is a value: unchanged")
    }
}

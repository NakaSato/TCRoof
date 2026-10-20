import XCTest
@testable import PVYield

final class TCPVModuleTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try Data(contentsOf: url)
    }

    private struct Reference: Decodable {
        struct Case: Decodable { let g, t, pmp, vmp, voc, isc: Double }
        let iLRef: Double
        let i0Ref: Double
        let cases: [Case]
    }

    // MARK: PAN parsing

    func testParsePAN() throws {
        let spec = try PANParser.parse(data: fixture("ET-M772BH550GL.PAN"))
        XCTAssertEqual(spec.manufacturer, "ET SOLAR")
        XCTAssertEqual(spec.model, "ET-M772BH550GL")
        XCTAssertEqual(spec.technology, .monoSi)
        XCTAssertEqual(spec.source, .pan)
        XCTAssertEqual(spec.stc.pNomW, 550)
        XCTAssertEqual(spec.stc.iscA, 14.0)
        XCTAssertEqual(spec.cells.cellsInSeries, 72)
        XCTAssertEqual(spec.cells.cellsInParallel, 2)
        XCTAssertEqual(spec.temperatureCoefficients.muIscAPerK, 0.00728, accuracy: 1e-12)
        XCTAssertEqual(spec.temperatureCoefficients.muVocVPerK, -0.128, accuracy: 1e-12)
        XCTAssertEqual(spec.oneDiode.rSeriesOhm, 0.203)
        XCTAssertEqual(spec.oneDiode.rShunt0Ohm, 2000)
        XCTAssertEqual(spec.oneDiode.gammaRef, 0.98)
        XCTAssertEqual(spec.bifaciality, 0.7)
        XCTAssertEqual(spec.dimensions?.areaM2 ?? 0, 1.134 * 2.278, accuracy: 1e-9)
        XCTAssertEqual(spec.iamProfile?.count, 9)
        XCTAssertEqual(spec.iamProfile?.last, IAMPoint(angleDeg: 90, factor: 0))
        XCTAssertEqual(spec.id, "et-solar-et-m772bh550gl")
        XCTAssertEqual(spec.validate(), [])
    }

    func testRejectsBinaryPAN() {
        let data = Data([0x50, 0x56, 0x00, 0x01, 0x02])
        XCTAssertThrowsError(try PANParser.parse(data: data)) {
            XCTAssertEqual($0 as? PANParser.ParseError, .protectedOrBinary)
        }
    }

    func testJSONRoundTrip() throws {
        let spec = try PANParser.parse(data: fixture("ET-M772BH550GL.PAN"))
        let decoded = try PVModuleSpec.from(json: spec.jsonData())
        XCTAssertEqual(decoded, spec)
    }

    // MARK: One-diode model vs pvlib (calcparams_pvsyst + singlediode)

    func testMatchesPvlib() throws {
        let spec = try PANParser.parse(data: fixture("ET-M772BH550GL.PAN"))
        let ref = try JSONDecoder().decode(Reference.self, from: fixture("pvlib-reference-ET-M772BH550GL.json"))
        let model = PVsystSingleDiodeModel(spec: spec)
        XCTAssertEqual(model.iLRef, ref.iLRef, accuracy: ref.iLRef * 1e-9)
        XCTAssertEqual(model.i0Ref, ref.i0Ref, accuracy: ref.i0Ref * 1e-6)
        for c in ref.cases {
            let mpp = model.maxPowerPoint(effectiveIrradiance: c.g, cellTempC: c.t)
            let voc = model.openCircuitVoltage(effectiveIrradiance: c.g, cellTempC: c.t)
            let isc = model.current(atVoltage: 0, effectiveIrradiance: c.g, cellTempC: c.t)
            let label = "G=\(c.g) T=\(c.t)"
            XCTAssertEqual(mpp.p, c.pmp, accuracy: c.pmp * 1e-6, label)   // ≤ 0.0001 %
            XCTAssertEqual(mpp.v, c.vmp, accuracy: 1e-3, label)
            XCTAssertEqual(voc, c.voc, accuracy: 1e-6, label)
            XCTAssertEqual(isc, c.isc, accuracy: 1e-9, label)
        }
    }

    func testSTCPowerCloseToNameplate() throws {
        let spec = try PANParser.parse(data: fixture("ET-M772BH550GL.PAN"))
        let p = PVsystSingleDiodeModel(spec: spec).maxPowerPoint(effectiveIrradiance: 1000, cellTempC: 25).p
        XCTAssertEqual(p, 550, accuracy: 550 * 0.005)   // PVsyst models within ±0.5 % of Pnom
    }

    func testZeroIrradiance() throws {
        let spec = try PANParser.parse(data: fixture("ET-M772BH550GL.PAN"))
        let mpp = PVsystSingleDiodeModel(spec: spec).maxPowerPoint(effectiveIrradiance: 0, cellTempC: 25)
        XCTAssertEqual(mpp.p, 0)
    }

    // MARK: Datasheet fit (no PAN file)

    func testDatasheetFitReproducesDatasheet() throws {
        let r = try DatasheetFitter.fit(
            id: "example-550", manufacturer: "Example", model: "550 datasheet", technology: .monoSi,
            stc: STCRatings(pNomW: 550, vmpV: 41.96, impA: 13.11, vocV: 49.90, iscA: 14.00),
            temperatureCoefficients: TemperatureCoefficients(muIscAPerK: 0.00728, muVocVPerK: -0.128,
                                                             muPmpPercentPerK: -0.34),
            cells: CellLayout(cellsInSeries: 72, cellsInParallel: 2, bypassDiodes: 3))
        XCTAssertEqual(r.spec.source, .datasheetFit)
        XCTAssertEqual(r.pmpErrorPercent, 0, accuracy: 0.01)
        XCTAssertEqual(r.vmpErrorPercent, 0, accuracy: 2.0)          // Vmp is a check, not a target
        XCTAssertEqual(r.muPmpErrorPercentPerK, 0, accuracy: 0.005)
        XCTAssertEqual(r.relativeEfficiencyAt200, 0.975, accuracy: 1e-4)
        XCTAssertEqual(r.spec.validate(), [])
    }

    /// Fitting the same module from its datasheet values alone should stay within 2 % of the
    /// manufacturer PAN model across the operating range.
    func testDatasheetFitTracksPANModel() throws {
        let pan = try PANParser.parse(data: fixture("ET-M772BH550GL.PAN"))
        let r = try DatasheetFitter.fit(
            id: "fit", manufacturer: pan.manufacturer, model: pan.model, technology: pan.technology,
            stc: pan.stc, temperatureCoefficients: pan.temperatureCoefficients, cells: pan.cells)
        let a = PVsystSingleDiodeModel(spec: pan), b = PVsystSingleDiodeModel(spec: r.spec)
        for (g, t) in [(1000.0, 25.0), (800, 45), (500, 30), (200, 25), (1000, 60), (100, 20)] {
            let pa = a.maxPowerPoint(effectiveIrradiance: g, cellTempC: t).p
            let pb = b.maxPowerPoint(effectiveIrradiance: g, cellTempC: t).p
            XCTAssertEqual(pb / pa, 1, accuracy: 0.02, "G=\(g) T=\(t)")
        }
    }

    func testDatasheetFitRejectsBadInput() {
        XCTAssertThrowsError(try DatasheetFitter.fit(
            id: "bad", manufacturer: "x", model: "x", technology: .monoSi,
            stc: STCRatings(pNomW: 550, vmpV: 52, impA: 13, vocV: 50, iscA: 14),
            temperatureCoefficients: TemperatureCoefficients(muIscAPerK: 0.007, muVocVPerK: -0.13, muPmpPercentPerK: -0.3),
            cells: CellLayout(cellsInSeries: 72)))
    }
}

final class ZnshineTests: XCTestCase {
    /// The fit uses only STC + temperature coefficients; NMOT is an independent check.
    func testZXM7_570_PredictsNMOT() throws {
        let r = try ZnshineZXM7UHLDD144.fit(570)
        XCTAssertEqual(r.pmpErrorPercent, 0, accuracy: 0.01)
        XCTAssertEqual(r.spec.validate(), [])
        let m = PVsystSingleDiodeModel(spec: r.spec)
        let p = m.maxPowerPoint(effectiveIrradiance: 800, cellTempC: ZnshineZXM7UHLDD144.nmotCellTempC).p
        let nmot = try XCTUnwrap(ZnshineZXM7UHLDD144.nmotPmaxW[570])
        XCTAssertEqual(p / nmot, 1, accuracy: 0.015, "model \(p) W vs datasheet NMOT \(nmot) W")
    }

    func testAllClassesFit() throws {
        for w in ZnshineZXM7UHLDD144.stc.keys.sorted() {
            let r = try ZnshineZXM7UHLDD144.fit(w)
            XCTAssertEqual(r.pmpErrorPercent, 0, accuracy: 0.01, "\(w) W")
        }
    }
}

final class InverterTests: XCTestCase {
    func testGrowattFitsReproduceDatasheet() throws {
        let expected: [String: (Double, Double)] = [
            "growatt-max-60ktl3-lv": (0.988, 0.984),
            "growatt-max-80ktl3-lv": (0.990, 0.985),
            "growatt-max-125ktl3-x-lv": (0.988, 0.985),
        ]
        for inv in try GrowattCatalog.all() {
            let (etaMax, etaEuro) = try XCTUnwrap(expected[inv.id])
            XCTAssertEqual(InverterEfficiencyModel.peakEfficiency(inv.lossModel), etaMax, accuracy: 1e-4, inv.id)
            XCTAssertEqual(InverterEfficiencyModel.euroEfficiency(inv.lossModel), etaEuro, accuracy: 1e-6, inv.id)
            // AC nominal power is reached at p = 1
            let ac = InverterEfficiencyModel.acPower(dcW: inv.lossModel.pDC0W, spec: inv).acW
            XCTAssertEqual(ac, inv.acNominalPowerW, accuracy: 1, inv.id)
            XCTAssertEqual(inv.validate(), [], inv.id)
            XCTAssertEqual(try InverterSpec.from(json: inv.jsonData()), inv)
        }
    }

    func testClippingAndNight() throws {
        let inv = try GrowattCatalog.max60KTL3LV()
        let r = InverterEfficiencyModel.acPower(dcW: 75_000, spec: inv)
        XCTAssertEqual(r.acW, 60_000)
        XCTAssertGreaterThan(r.clippedDCW, 13_000)
        XCTAssertEqual(InverterEfficiencyModel.acPower(dcW: 0, spec: inv).acW, -1)
        let maxVA = InverterEfficiencyModel.acPower(dcW: 75_000, spec: inv, limit: .maxApparentPower)
        XCTAssertEqual(maxVA.acW, 66_600)
    }

    func testZnshine570StringDesign() throws {
        let module = try ZnshineZXM7UHLDD144.fit(570).spec
        let i60 = try GrowattCatalog.max60KTL3LV()
        let i125 = try GrowattCatalog.max125KTL3XLV()

        let l60 = StringSizing.limits(module: module, inverter: i60)
        XCTAssertEqual(l60.max, 20)       // Voc at 10 °C ≈ 53.0 V × 20 = 1,060 V ≤ 1,100 V
        XCTAssertEqual(l60.min, 7)        // start voltage 250 V
        XCTAssertEqual(StringSizing.limits(module: module, inverter: i125).min, 6)

        // 60/80 kW: two strings per MPPT exceed the 26 A operating limit (26.9 A).
        let r60 = StringSizing.check(module: module, inverter: i60, modulesPerString: 11, stringsPerMppt: 2, totalModules: 132)
        XCTAssertEqual(r60.worst, .warning)
        XCTAssertEqual(r60.checks.first { $0.name == "Operating current per MPPT" }?.level, .warning)
        XCTAssertEqual(r60.checks.first { $0.name == "Short-circuit current per MPPT" }?.level, .ok)

        // 125 kW: 32 A / 40 A limits hold even with +10 % bifacial current.
        let r125 = StringSizing.check(module: module, inverter: i125, modulesPerString: 14, stringsPerMppt: 2,
                                      totalModules: 280, conditions: .init(bifacialCurrentGain: 0.10))
        XCTAssertEqual(r125.worst, .ok)

        // 21 modules breaks the 1,100 V limit.
        let bad = StringSizing.check(module: module, inverter: i60, modulesPerString: 21, stringsPerMppt: 1)
        XCTAssertEqual(bad.worst, .error)
    }
}

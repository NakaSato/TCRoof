import XCTest
@testable import PVYield

/// The hourly chain against the reference engine (tools/yield-reference, pvlib 0.13–0.16): each stage on
/// `stages-60kW-ERA5.json`, the full hourly trace of 60kW-ERA5, and every front-lit golden scenario.
///
/// Tolerances (the reference states none; these are what an exact port of the same equations gives, with margin):
/// - SPA: 1e-5° (the fixture keeps 6 decimals). The hour's effective sun interpolates the slow SPA terms over the
///   hour: 1e-4°.
/// - DNI, DHI, POA parts, effective irradiance: 0.01 W/m² or 1e-5 relative.
/// - Cell temperature 1e-4 °C; module MPP 1e-4 relative (the one-diode solver's own 1e-6 against pvlib, plus input
///   rounding).
/// - Annual energies at every step, monthly sums: 0.01 %. PR, specific yield: their rounding in the golden file.
final class HourlyYieldTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let reference = repo.appendingPathComponent("tools/yield-reference")

    static let weather: HourlyWeather = {
        let url = reference.appendingPathComponent("data/pvgis-tmy-era5-bangkok-13.75-100.50.csv")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return (try? HourlyWeather.pvgisTMY(csv: text, latitude: 13.75, longitude: 100.50)) ?? HourlyWeather(
            unix: [], ghi: [], dni: [], dhi: [], tempAir: [], windSpeed: [], source: "missing")
    }()
    static let site = SolarPosition.Site(latitude: 13.75, longitude: 100.50)
    static let track = SunTrack(weather: weather, site: site)

    func component<T: Decodable>(_ path: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: Self.reference.appendingPathComponent(path)))
    }

    func golden<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/golden/\(name).json", withExtension: nil))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: fixtures

    struct Stages: Decodable {
        struct Hour: Decodable {
            let row, unix: Int
            let rawApparentZenith, rawAzimuth, zenith, azimuth, dni, dhi, dniExtra, airmass: Double
            let aoi, poaDirect, poaSky, poaGround, poaGlobal, iamBeam, gIAM, gEff, tCell, pMpp, iMpp, vMpp: Double
            let eastDirect, eastSky, eastGround: Double
        }
        struct Marion: Decodable { let tilt, sky, ground: Double }
        let hours: [Hour]
        let marion: [Marion]
    }

    struct Golden: Decodable {
        struct Config: Decodable {
            struct Design: Decodable { let modules_per_string, strings: Int }
            struct Uncertainty: Decodable { let meteo_data: Double }
            struct Face: Decodable {
                let name: String, n_modules: Int, tilt, azimuth, near_shading: Double
                let horizon: [[Double]]?
            }
            let lat, lon, tilt, azimuth: Double
            let inverter_json, module_json: String
            let design: Design
            let ghi_target_kwh_m2: Double?
            let uncertainty: Uncertainty
            let faces: [Face]?
        }
        struct Month: Decodable { let month: Int; let GHI, POA, E_grid, PR: Double }
        struct Age: Decodable { let year: Int; let E_grid: Double }
        struct Probability: Decodable { let sigma_1yr, sigma_10yr, P50, P90_1yr, P90_10yr, P99_1yr: Double }
        struct Hours: Decodable { let current_limited, clipped: Int; let max_dc_kW, t_cell_mean_daylight, t_cell_max: Double }
        struct Face: Decodable { let name: String; let H_inc, H_shade, E_dc_in, dc_yield_kWh_per_kWp: Double }
        let config: Config
        let p_nom_dc_kWp, dc_ac_ratio, specific_yield, PR: Double
        let energies_kWh: YieldEnergies
        let loss_diagram: [[LossValue]]
        let monthly: [Month]
        let ageing: [Age]
        let lifetime_kWh: Double
        let probability: Probability
        let hours: Hours
        let faces: [Face]?
    }

    enum LossValue: Decodable {
        case label(String), value(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .value(d) } else { self = .label(try c.decode(String.self)) }
        }
        var number: Double? { if case .value(let d) = self { return d }; return nil }
    }

    struct HourlyTrace: Decodable { let ghi, poa, g_eff, t_cell, p_module, p_dc_in, p_ac, p_grid: [Double] }

    func system(_ g: Golden) throws -> YieldSystem {
        let c = g.config
        let module = try component(c.module_json, as: PVModuleSpec.self)
        let inverter = try component(c.inverter_json, as: InverterSpec.self)
        let faces: [ArrayFace] = c.faces.map { list in
            list.map { f in
                ArrayFace(id: f.name, moduleCount: f.n_modules, tiltDeg: f.tilt, azimuthDegTrueN: f.azimuth, nearShadingLossFrac: f.near_shading,
                          horizon: f.horizon.map { HorizonProfile(pairs: $0.map { ($0[0], $0[1]) }) })
            }
        } ?? [ArrayFace(id: "array", moduleCount: c.design.modules_per_string * c.design.strings, tiltDeg: c.tilt, azimuthDegTrueN: c.azimuth)]
        var s = YieldSystem(module: module, inverter: inverter,
                            design: StringDesign(modulesPerString: c.design.modules_per_string, strings: c.design.strings), faces: faces)
        s.uncertainty = YieldUncertainty(meteoData: c.uncertainty.meteo_data)
        return s
    }

    func track(_ g: Golden) -> SunTrack {
        guard let target = g.config.ghi_target_kwh_m2 else { return Self.track }
        return SunTrack(weather: Self.weather.scaled(toAnnualGHI: target), site: Self.site)
    }

    // MARK: stages

    func testWeatherParses() {
        XCTAssertEqual(Self.weather.count, 8760)
        XCTAssertEqual(Self.weather.annualGHI, 1825.2, accuracy: 0.05)
        XCTAssertEqual(Self.weather.unix.first, 631_152_000)   // 1990-01-01 00:00 UTC
    }

    func testSolarPositionMatchesSPA() throws {
        let st = try golden("stages-60kW-ERA5", as: Stages.self)
        for h in st.hours {
            let p = SolarPosition.position(unix: Double(h.unix), site: Self.site)
            XCTAssertEqual(p.apparentZenith, h.rawApparentZenith, accuracy: 1e-5, "row \(h.row)")
            XCTAssertEqual(p.azimuth, h.rawAzimuth, accuracy: 1e-5, "row \(h.row)")
        }
    }

    func testSunTrackMatchesReference() throws {
        let st = try golden("stages-60kW-ERA5", as: Stages.self)
        for h in st.hours {
            let t = Self.track.hours[h.row]
            XCTAssertEqual(t.unix, h.unix)
            XCTAssertEqual(t.zenith, h.zenith, accuracy: 1e-4, "row \(h.row)")
            XCTAssertEqual(t.azimuth, h.azimuth, accuracy: 1e-4, "row \(h.row)")
            XCTAssertEqual(t.dni, h.dni, accuracy: max(0.01, h.dni * 1e-5), "row \(h.row)")
            XCTAssertEqual(t.dhi, h.dhi, accuracy: 1e-6, "row \(h.row)")
            XCTAssertEqual(t.dniExtra, h.dniExtra, accuracy: 1e-6, "row \(h.row)")
            XCTAssertEqual(t.airmass ?? 0, h.airmass, accuracy: max(1e-6, h.airmass * 1e-5), "row \(h.row)")
        }
    }

    func testMarionDiffuseMatchesPvlib() throws {
        for m in try golden("stages-60kW-ERA5", as: Stages.self).marion {
            let d = IAM.marionDiffuse(tilt: m.tilt, b0: 0.05)
            XCTAssertEqual(d.sky, m.sky, accuracy: 1e-9, "tilt \(m.tilt)")
            XCTAssertEqual(d.ground, m.ground, accuracy: 1e-9, "tilt \(m.tilt)")
        }
    }

    func testPlaneOfArrayMatchesPerez() throws {
        for h in try golden("stages-60kW-ERA5", as: Stages.self).hours {
            let t = Self.track.hours[h.row]
            let s = Irradiance.planeOfArray(tilt: 10, azimuth: 180, albedo: 0.2, hour: t)
            let tol = { (x: Double) in max(0.01, abs(x) * 1e-5) }
            XCTAssertEqual(s.direct, h.poaDirect, accuracy: tol(h.poaDirect), "row \(h.row)")
            XCTAssertEqual(s.sky, h.poaSky, accuracy: tol(h.poaSky), "row \(h.row)")
            XCTAssertEqual(s.ground, h.poaGround, accuracy: tol(h.poaGround), "row \(h.row)")
            XCTAssertEqual(s.aoi, h.aoi, accuracy: 1e-4, "row \(h.row)")
            XCTAssertEqual(IAM.ashrae(aoi: s.aoi), h.iamBeam, accuracy: 1e-6, "row \(h.row)")
            let e = Irradiance.planeOfArray(tilt: 30, azimuth: 90, albedo: 0.2, hour: t)
            XCTAssertEqual(e.direct, h.eastDirect, accuracy: tol(h.eastDirect), "east row \(h.row)")
            XCTAssertEqual(e.sky, h.eastSky, accuracy: tol(h.eastSky), "east row \(h.row)")
            XCTAssertEqual(e.ground, h.eastGround, accuracy: tol(h.eastGround), "east row \(h.row)")
        }
    }

    func testCellTemperatureAndModuleMatchReference() throws {
        let g = try golden("60kW-ERA5", as: Golden.self)
        let r = YieldEngine.run(try system(g), track: Self.track, hourly: true)
        let hourly = try XCTUnwrap(r.hourly)
        for h in try golden("stages-60kW-ERA5", as: Stages.self).hours {
            XCTAssertEqual(hourly.gEff[h.row], h.gEff, accuracy: max(0.01, h.gEff * 1e-5), "row \(h.row)")
            XCTAssertEqual(hourly.tCell[h.row], h.tCell, accuracy: 1e-4, "row \(h.row)")
            XCTAssertEqual(hourly.pModule[h.row], h.pMpp, accuracy: max(1e-4, h.pMpp * 1e-4), "row \(h.row)")
        }
    }

    // MARK: whole chain

    func testHourlyTraceMatchesReference() throws {
        let g = try golden("60kW-ERA5", as: Golden.self)
        let trace = try golden("60kW-ERA5-hourly", as: HourlyTrace.self)
        let h = try XCTUnwrap(YieldEngine.run(try system(g), track: Self.track, hourly: true).hourly)
        XCTAssertEqual(trace.poa.count, h.poa.count)
        func check(_ a: [Double], _ b: [Double], _ name: String, rel: Double, abs: Double) {
            var worst = 0.0
            for k in a.indices {
                let tol = max(abs, Swift.abs(b[k]) * rel)
                worst = max(worst, Swift.abs(a[k] - b[k]) / tol)
                if Swift.abs(a[k] - b[k]) > tol { XCTFail("\(name)[\(k)] \(a[k]) vs \(b[k])"); return }
            }
            print(String(format: "PVYield hourly %@: worst %.3f of tolerance", name, worst))
        }
        check(h.poa, trace.poa, "poa", rel: 1e-5, abs: 0.01)
        check(h.gEff, trace.g_eff, "g_eff", rel: 1e-5, abs: 0.01)
        check(h.tCell, trace.t_cell, "t_cell", rel: 0, abs: 1e-3)
        check(h.pModule, trace.p_module, "p_module", rel: 1e-4, abs: 1e-3)
        check(h.pDCIn, trace.p_dc_in, "p_dc_in", rel: 1e-4, abs: 0.1)
        check(h.pAC, trace.p_ac, "p_ac", rel: 1e-4, abs: 0.1)
        check(h.pGrid, trace.p_grid, "p_grid", rel: 1e-4, abs: 0.1)
    }

    static let goldenScenarios = ["60kW-ERA5", "60kW-GSA", "80kW-ERA5", "80kW-GSA", "125kW-ERA5", "125kW-GSA",
                                  "60kW-ERA5-faces-horizon"]

    func testGoldenScenarios() throws {
        for name in Self.goldenScenarios {
            let g = try golden(name, as: Golden.self)
            let r = YieldEngine.run(try system(g), track: track(g))
            compare(r, g, name)
        }
    }

    func compare(_ r: YieldResult, _ g: Golden, _ name: String) {
        let e = r.energies, ge = g.energies_kWh
        let pairs: [(String, Double, Double)] = [
            ("H_hor", e.hHor, ge.hHor), ("H_inc", e.hInc, ge.hInc), ("H_iam", e.hIAM, ge.hIAM), ("H_shade", e.hShade, ge.hShade),
            ("H_front_eff", e.hFrontEff, ge.hFrontEff), ("H_eff", e.hEff, ge.hEff), ("E_nominal", e.eNominal, ge.eNominal),
            ("E_after_irr_level", e.eAfterIrrLevel, ge.eAfterIrrLevel), ("E_after_temp", e.eAfterTemp, ge.eAfterTemp),
            ("E_after_quality_lid_mm", e.eAfterQualityLidMismatch, ge.eAfterQualityLidMismatch), ("E_arr_mpp", e.eArrMpp, ge.eArrMpp),
            ("E_after_current_limit", e.eAfterCurrentLimit, ge.eAfterCurrentLimit), ("E_after_inv_eff", e.eAfterInvEff, ge.eAfterInvEff),
            ("E_after_clipping", e.eAfterClipping, ge.eAfterClipping), ("E_after_ac_ohmic", e.eAfterACOhmic, ge.eAfterACOhmic),
            ("E_grid", e.eGrid, ge.eGrid),
        ]
        for (k, a, b) in pairs { XCTAssertEqual(a, b, accuracy: max(0.01, b * 1e-4), "\(name) \(k)") }
        let worst = pairs.filter { $0.2 > 0 }.map { abs($0.1 / $0.2 - 1) }.max() ?? 0
        print(String(format: "PVYield golden %@: E_grid %.2f vs %.2f kWh (%+.4f %%), worst step %.4f %%", name, e.eGrid, ge.eGrid,
                     (e.eGrid / ge.eGrid - 1) * 100, worst * 100))
        XCTAssertEqual(r.dcKWp, g.p_nom_dc_kWp, accuracy: 1e-9, name)
        XCTAssertEqual(r.dcAcRatio, g.dc_ac_ratio, accuracy: 0.0005, name)
        XCTAssertEqual(r.specificYield, g.specific_yield, accuracy: 0.05 + g.specific_yield * 1e-4, name)
        XCTAssertEqual(r.performanceRatio, g.PR, accuracy: 0.00005 + g.PR * 1e-4, name)
        // the golden diagram has a bifacial step (index 4) the front-only port leaves out
        let goldenLosses = g.loss_diagram.compactMap { $0.last?.number }.enumerated().filter { $0.offset != 4 }.map(\.element)
        XCTAssertEqual(r.lossDiagram.count, goldenLosses.count, name)
        for (a, b) in zip(r.lossDiagram.map(\.percent), goldenLosses) {
            XCTAssertEqual(a, b, accuracy: 0.0051 + abs(b) * 1e-3, "\(name) loss diagram")
        }
        for (m, gm) in zip(r.monthly, g.monthly) {
            XCTAssertEqual(m.month, gm.month)
            XCTAssertEqual(m.ghi, gm.GHI, accuracy: 0.051, "\(name) GHI \(gm.month)")
            XCTAssertEqual(m.poa, gm.POA, accuracy: 0.051 + gm.POA * 1e-4, "\(name) POA \(gm.month)")
            XCTAssertEqual(m.eGrid, gm.E_grid, accuracy: 0.51 + gm.E_grid * 1e-4, "\(name) E_grid \(gm.month)")
            XCTAssertEqual(m.pr, gm.PR, accuracy: 0.00005 + gm.PR * 1e-4, "\(name) PR \(gm.month)")
        }
        XCTAssertEqual(r.ageing.count, g.ageing.count)
        for (a, b) in zip(r.ageing, g.ageing) { XCTAssertEqual(a, b.E_grid, accuracy: 0.51 + b.E_grid * 1e-4, "\(name) year \(b.year)") }
        XCTAssertEqual(r.ageing.map { $0.rounded() }.reduce(0, +), g.lifetime_kWh, accuracy: g.lifetime_kWh * 1e-4, name)
        let p = r.probability, gp = g.probability
        XCTAssertEqual(p.sigma1yr, gp.sigma_1yr, accuracy: 0.00005, name)
        XCTAssertEqual(p.sigma10yr, gp.sigma_10yr, accuracy: 0.00005, name)
        XCTAssertEqual(p.p50, gp.P50, accuracy: 0.51 + gp.P50 * 1e-4, name)
        XCTAssertEqual(p.p90OneYear, gp.P90_1yr, accuracy: 0.51 + gp.P90_1yr * 1e-4, name)
        XCTAssertEqual(p.p90TenYear, gp.P90_10yr, accuracy: 0.51 + gp.P90_10yr * 1e-4, name)
        XCTAssertEqual(p.p99OneYear, gp.P99_1yr, accuracy: 0.51 + gp.P99_1yr * 1e-4, name)
        XCTAssertEqual(r.hours.currentLimited, g.hours.current_limited, name)
        XCTAssertEqual(r.hours.clipped, g.hours.clipped, name)
        XCTAssertEqual(r.hours.maxDCkW, g.hours.max_dc_kW, accuracy: 0.0051, name)
        XCTAssertEqual(r.hours.tCellMeanDaylight, g.hours.t_cell_mean_daylight, accuracy: 0.051, name)
        XCTAssertEqual(r.hours.tCellMax, g.hours.t_cell_max, accuracy: 0.051, name)
        if let gf = g.faces {
            XCTAssertEqual(r.faces.count, gf.count, name)
            for (f, b) in zip(r.faces, gf) {
                XCTAssertEqual(f.id, b.name)
                XCTAssertEqual(f.hInc, b.H_inc, accuracy: 0.051 + b.H_inc * 1e-4, "\(name) \(b.name) H_inc")
                XCTAssertEqual(f.hShade, b.H_shade, accuracy: 0.051 + b.H_shade * 1e-4, "\(name) \(b.name) H_shade")
                XCTAssertEqual(f.eDCIn, b.E_dc_in, accuracy: 0.51 + b.E_dc_in * 1e-4, "\(name) \(b.name) E_dc_in")
                XCTAssertEqual(f.dcYield, b.dc_yield_kWh_per_kWp, accuracy: 0.051 + b.dc_yield_kWh_per_kWp * 1e-4, "\(name) \(b.name)")
            }
        }
    }

    // MARK: inputs

    func testHorizonProfile() {
        let h = HorizonProfile(pairs: [(60, 8), (90, 12), (120, 6)])
        XCTAssertEqual(h.elevation(at: 75), 10, accuracy: 1e-12)
        XCTAssertEqual(h.elevation(at: 90), 12, accuracy: 1e-12)
        XCTAssertEqual(h.elevation(at: 0), 6 + (8 - 6) * 240.0 / 300, accuracy: 1e-12)   // wraps from 120° to 420°
        XCTAssertEqual(h.elevation(at: 270), 6 + (8 - 6) * (270 - 120) / 300, accuracy: 1e-12)
        XCTAssertLessThan(h.skyFactor(tilt: 15), 1)
        XCTAssertEqual(HorizonProfile(pairs: [(0, 0)]).skyFactor(tilt: 15), 1, accuracy: 1e-12)
    }

    func testBundledWeather() throws {
        let near = try XCTUnwrap(BundledWeather.nearest(latitude: 13.90, longitude: 100.60))
        XCTAssertEqual(near.dataset.id, "pvgis-era5-bangkok")
        XCTAssertEqual(near.distanceKm, 19.8, accuracy: 0.5)
        XCTAssertNil(BundledWeather.nearest(latitude: 18.79, longitude: 98.98))   // Chiang Mai
        // the bundled copy is the reference's file
        XCTAssertEqual(try BundledWeather.load(near.dataset), Self.weather)
        let t = try BundledWeather.track(near.dataset, latitude: 13.75, longitude: 100.50)
        XCTAssertEqual(t.hours.count, 8760)
        XCTAssertEqual(t.hours[4].zenith, Self.track.hours[4].zenith, accuracy: 1e-12)
    }

    func testScaledWeather() {
        let w = Self.weather.scaled(toAnnualGHI: 1794)
        XCTAssertEqual(w.annualGHI, 1794, accuracy: 1e-6)
        XCTAssertTrue(w.source.contains("×"))
    }

    func testMoreInvertersShareTheArray() throws {
        // two inverters of half the array behave like one with the same per-unit loading
        let g = try golden("60kW-ERA5", as: Golden.self)
        var one = try system(g)
        one.design = nil
        var two = one
        two.inverterCount = 2
        two.faces[0].moduleCount *= 2
        let a = YieldEngine.run(one, track: Self.track), b = YieldEngine.run(two, track: Self.track)
        XCTAssertEqual(b.energies.eGrid, 2 * a.energies.eGrid, accuracy: a.energies.eGrid * 1e-9)
        XCTAssertEqual(b.dcAcRatio, a.dcAcRatio, accuracy: 1e-12)
    }

    /// One year on one face, for the report: `swift test -c release --filter testRuntimeOneFaceOneYear`.
    func testRuntimeOneFaceOneYear() throws {
        let g = try golden("60kW-ERA5", as: Golden.self)
        let s = try system(g)
        let t0 = Date()
        let track = SunTrack(weather: Self.weather, site: Self.site)
        let t1 = Date()
        let r = YieldEngine.run(s, track: track)
        let t2 = Date()
        print(String(format: "PVYield runtime: sun track %.1f ms, one face %.1f ms (E_grid %.0f kWh)",
                     t1.timeIntervalSince(t0) * 1000, t2.timeIntervalSince(t1) * 1000, r.energies.eGrid))
        XCTAssertGreaterThan(r.energies.eGrid, 0)
    }
}

import XCTest
@testable import TCRoofCore

/// C1's energy from the hourly engine (PVYield), and the SolarModel fallback when an input is missing.
final class RoofMountYieldTests: XCTestCase {
    static let layout = RoofMountLayout.best(RoofMountLayoutTests.hip, standard: RoofMount.defaultStandard)

    static func job(gps: String?, inverters: String? = "60,60", roofs: Int = 1) -> Job {
        var j = Job()
        if let gps { j.values["gps"] = .text(gps) }
        j.modules = (0..<roofs).map { _ in SurveyModule(type: .roof) }
        if let inverters {
            var v = Values()
            v["invSizes"] = .text(inverters)
            j.modules.append(SurveyModule(type: .inverter, values: v))
        }
        return j
    }

    func testHourlyNearBangkok() throws {
        let i = RoofMountYield.inputs(Self.layout, job: Self.job(gps: "13.80, 100.55"))
        XCTAssertEqual(i.inverterSizes, [60, 60])
        XCTAssertGreaterThan(i.modules, 0)
        let e = RoofMountYield.estimate(i)
        guard case .hourly(_, let place, let km, let attribution) = e.source else { return XCTFail("\(e.source)") }
        XCTAssertEqual(place, "กรุงเทพฯ")
        XCTAssertEqual(km, 7.6, accuracy: 0.5)
        XCTAssertEqual(attribution, "PVGIS © European Union")
        XCTAssertTrue(e.sourceLine.hasPrefix("คำนวณรายชั่วโมง"), e.sourceLine)
        XCTAssertEqual(e.faces.count, i.faces.count)
        XCTAssertEqual(e.faces.reduce(0) { $0 + $1.mwh }, e.mwh, accuracy: 1e-9)
        XCTAssertEqual(e.kWp, i.kWp, accuracy: 1e-9)
        // a low-pitch roof in Bangkok: about 1,300–1,550 kWh/kWp, PR around 0.8 on the plane, P90 below P50
        XCTAssertGreaterThan(e.kWhPerKWp, 1250)
        XCTAssertLessThan(e.kWhPerKWp, 1600)
        XCTAssertEqual(e.performanceRatio ?? 0, 0.80, accuracy: 0.04)
        XCTAssertLessThan(e.p90MWh ?? .infinity, e.mwh)
        XCTAssertEqual(e.inverterLine?.hasPrefix("Growatt MAX 60KTL3 LV × 2"), true, e.inverterLine ?? "")
        // the south face beats the north face
        let s = try XCTUnwrap(e.faces.first { $0.id == "S" }), n = try XCTUnwrap(e.faces.first { $0.id == "N" })
        XCTAssertGreaterThan(s.kWhPerKWp, n.kWhPerKWp)
        // within a quarter of the clear-sky model, which the layout's face choice still uses
        let clear = RoofMountYield.clearSky(i, reason: "")
        XCTAssertEqual(e.mwh / clear.mwh, 1, accuracy: 0.25)
    }

    func testFallsBackToTheClearSkyModel() {
        let far = RoofMountYield.estimate(RoofMountYield.inputs(Self.layout, job: Self.job(gps: "18.79, 98.98")))
        XCTAssertEqual(far.source, .clearSky(reason: "ยังไม่มีข้อมูลอากาศรายชั่วโมงของพื้นที่นี้"))
        XCTAssertEqual(far.mwh, Self.layout.quantities.energy, accuracy: 1e-9)
        XCTAssertNil(far.p90MWh)
        let none = RoofMountYield.estimate(RoofMountYield.inputs(Self.layout, job: Self.job(gps: nil)))
        XCTAssertEqual(none.source, .clearSky(reason: "ยังไม่มีพิกัด A1"))
        XCTAssertTrue(none.sourceLine.hasPrefix("ประมาณแบบท้องฟ้าใส"))
        // a module the engine has no model of (the plain standard's 600 W)
        let other = RoofMountLayout.best(RoofMountLayoutTests.hip, standard: .standard)
        let e = RoofMountYield.estimate(RoofMountYield.inputs(other, job: Self.job(gps: "13.75, 100.50")))
        XCTAssertEqual(e.source, .clearSky(reason: "ยังไม่มีแบบจำลองแผง 600 W"))
    }

    func testInverterAssumptions() {
        func inv(_ j: Job) -> (Int, Int, String?)? {
            RoofMountYield.inverters(RoofMountYield.inputs(Self.layout, job: j)).map { (Int($0.spec.acNominalPowerW / 1000), $0.count, $0.assumed) }
        }
        let kWp = RoofMountYield.inputs(Self.layout, job: Self.job(gps: nil)).kWp
        let fit = Int((kWp / 78).rounded(.up))
        // one roof: all of B2's inverters
        XCTAssertEqual(inv(Self.job(gps: nil, inverters: "80,80,80"))?.1, 3)
        XCTAssertNil(inv(Self.job(gps: nil, inverters: "80,80,80"))?.2)
        // mixed sizes: the most common one, as many as give the same AC
        XCTAssertEqual(inv(Self.job(gps: nil, inverters: "60,125,125"))?.0, 125)
        XCTAssertEqual(inv(Self.job(gps: nil, inverters: "60,125,125"))?.1, 2)
        // two roofs: this roof's share at DC/AC ≤ 1.3
        XCTAssertEqual(inv(Self.job(gps: nil, inverters: "60,60", roofs: 2))?.1, fit)
        XCTAssertNotNil(inv(Self.job(gps: nil, inverters: "60,60", roofs: 2))?.2)
        // none picked, or a size without a model: 60 kW, assumed
        XCTAssertEqual(inv(Self.job(gps: nil, inverters: nil))?.2, "ยังไม่เลือกอินเวอร์เตอร์ (B2) · คิด Growatt 60 kW × \(fit)")
        XCTAssertEqual(inv(Self.job(gps: nil, inverters: "40"))?.2?.hasPrefix("ไม่มีแบบจำลองอินเวอร์เตอร์ 40 kW"), true)
    }

    func testCatalogModule() {
        let m = RoofPlan.Module.catalogDefault
        XCTAssertEqual(RoofMountYield.catalogModule(wp: m.kW * 1000, length: m.length, width: m.width)?.id, "p570")
        XCTAssertNotNil(RoofMountYield.moduleSpec(catalogID: "p570"))
        XCTAssertNil(RoofMountYield.moduleSpec(catalogID: "p620"))
        XCTAssertNil(RoofMountYield.catalogModule(wp: 600, length: 2.28, width: 1.13))
    }
}

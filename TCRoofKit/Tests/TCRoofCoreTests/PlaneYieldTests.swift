import XCTest
@testable import TCRoofCore

/// `PlaneYield`: the hourly engine for a plane near the bundled weather, `SolarModel` elsewhere, and the roof and tank
/// figures that read it.
final class PlaneYieldTests: XCTestCase {
    static let bangkok = (lat: 13.80, lon: 100.55)

    func testHourlyNearBangkok() {
        let y = PlaneYield.kWhPerKWp(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon, tilt: 10, azimuthFromSouth: 0)
        // a 10° south plane in Bangkok, after PVYield's default losses
        XCTAssertGreaterThan(y, 1250)
        XCTAssertLessThan(y, 1600)
        XCTAssertNotEqual(y, SolarModel.yield(lat: Self.bangkok.lat, tilt: 10, azimuthFromSouth: 0))
        guard case .hourly(_, let place, let km) = PlaneYield.source(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon) else {
            return XCTFail("not hourly")
        }
        XCTAssertEqual(place, "กรุงเทพฯ")
        XCTAssertEqual(km, 7.6, accuracy: 0.5)
        // kept: the same plane gives the same figure
        XCTAssertEqual(PlaneYield.kWhPerKWp(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon, tilt: 10, azimuthFromSouth: 0), y)
    }

    func testOrientationAndTilt() {
        func y(_ tilt: Double, _ az: Double) -> Double {
            PlaneYield.kWhPerKWp(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon, tilt: tilt, azimuthFromSouth: az)
        }
        XCTAssertGreaterThan(y(15, 0), y(15, 180))
        XCTAssertGreaterThan(y(15, 0), y(15, 90))
        XCTAssertEqual(y(15, 90), y(15, -270), accuracy: 1e-9)
        // flat has no orientation
        XCTAssertEqual(y(0, 0), y(0, 120), accuracy: 1)
        // within a quarter of the clear-sky model
        XCTAssertEqual(y(15, 0) / SolarModel.yield(lat: Self.bangkok.lat, tilt: 15, azimuthFromSouth: 0), 1, accuracy: 0.25)
    }

    func testSolarModelKeepsWhatItWorkedOut() {
        // pages ask on every redraw, so the sun positions and the planes are kept; the figures stay the same
        let planes: [(lat: Double, tilt: Double, az: Double)] = [(13.8, 15, 20), (13.8, 15, -160), (18.79, 5, 0), (7.0, 30, 90)]
        for p in planes {
            let fresh = SolarModel.computeYield(lat: p.lat, tilt: p.tilt, azimuthFromSouth: p.az)
            XCTAssertEqual(SolarModel.yield(lat: p.lat, tilt: p.tilt, azimuthFromSouth: p.az), fresh)
            XCTAssertEqual(SolarModel.yield(lat: p.lat, tilt: p.tilt, azimuthFromSouth: p.az), fresh)
        }
        let s = SolarModel.samples(lat: 13.8), c = SolarModel.computeSamples(lat: 13.8)
        XCTAssertEqual(s.count, c.count)
        XCTAssertEqual(s.map(\.dni), c.map(\.dni))
        // more latitudes than are kept: each still gives its own figure
        for lat in stride(from: 5.0, through: 20, by: 1) {
            XCTAssertEqual(SolarModel.yield(lat: lat, tilt: 10, azimuthFromSouth: 0), SolarModel.computeYield(lat: lat, tilt: 10, azimuthFromSouth: 0))
        }
    }

    func testFallsBackToSolarModel() {
        // no longitude, or no weather near the site (Chiang Mai)
        XCTAssertEqual(PlaneYield.kWhPerKWp(latitude: 13.8, longitude: nil, tilt: 15, azimuthFromSouth: 20),
                       SolarModel.yield(lat: 13.8, tilt: 15, azimuthFromSouth: 20))
        XCTAssertEqual(PlaneYield.kWhPerKWp(latitude: 18.79, longitude: 98.98, tilt: 15, azimuthFromSouth: 20),
                       SolarModel.yield(lat: 18.79, tilt: 15, azimuthFromSouth: 20))
        XCTAssertEqual(PlaneYield.source(latitude: 18.79, longitude: 98.98), .clearSky)
        XCTAssertEqual(PlaneYield.source(latitude: 13.8, longitude: nil), .clearSky)
    }

    func testRoofFacesTakeTheHourlyFigure() throws {
        var input = RoofMountLayoutTests.hip
        input.latitude = Self.bangkok.lat; input.longitude = Self.bangkok.lon
        let m = RoofMountLayout.best(input, standard: RoofMount.defaultStandard)
        let south = try XCTUnwrap(m.faces.first { $0.face.id == "S" }), north = try XCTUnwrap(m.faces.first { $0.face.id == "N" })
        let tilt = south.face.tilt * 180 / .pi
        XCTAssertEqual(south.yield, PlaneYield.kWhPerKWp(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon, tilt: tilt,
                                                         azimuthFromSouth: 0), accuracy: 1e-9)
        XCTAssertGreaterThan(south.yield, north.yield)
        XCTAssertEqual(m.latitude, Self.bangkok.lat)
        // the energy card's fallback stays SolarModel's
        let i = RoofMountYield.inputs(m, job: RoofMountYieldTests.job(gps: nil))
        let s = try XCTUnwrap(i.faces.first { $0.id == "S" })
        XCTAssertEqual(s.clearSkyYield, SolarModel.yield(lat: Self.bangkok.lat, tilt: tilt, azimuthFromSouth: 0), accuracy: 1e-9)
    }

    func testTheReportPrintsTheCardsFigure() throws {
        var v = Values()
        v[Roof.Key.spansX] = .text("6@5"); v[Roof.Key.spansY] = .text("3@6")
        var job = RoofMountYieldTests.job(gps: "\(Self.bangkok.lat), \(Self.bangkok.lon)")
        job.modules[0].values = v
        XCTAssertEqual(RoofMount.site(job).longitude, Self.bangkok.lon)
        let (m, energy) = RoofMount.printed(v, job: job)
        XCTAssertGreaterThan(m.quantities.modules, 0)
        XCTAssertTrue(energy.isHourly, energy.sourceLine)
        XCTAssertTrue(RoofMount.summaryLine(m, energy: energy.mwh).contains(String(format: "%.1f MWh/ปี", energy.mwh)))
        // the screen's layout is the same one
        let screen = RoofMount.layout(v, latitude: Self.bangkok.lat, longitude: Self.bangkok.lon).layout
        XCTAssertEqual(RoofMountYield.inputs(screen, job: job), RoofMountYield.inputs(m, job: job))
        // no GPS: no longitude either
        XCTAssertNil(RoofMount.site(RoofMountYieldTests.job(gps: nil)).longitude)
    }

    func testTankEnergyReadsTheSite() throws {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        TankLayout.save(&v, TankLayout.auto(v), off: [])
        let l = try XCTUnwrap(TankLayout.current(v))
        let hourly = l.yield(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon, facing: nil)
        XCTAssertEqual(hourly, PlaneYield.kWhPerKWp(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon, tilt: l.params.tilt,
                                                    azimuthFromSouth: 0), accuracy: 1e-9)
        XCTAssertEqual(l.yield(latitude: Self.bangkok.lat, facing: nil),
                       SolarModel.yield(lat: Self.bangkok.lat, tilt: l.params.tilt, azimuthFromSouth: 0), accuracy: 1e-9)
        let s = try XCTUnwrap(TankShade(v, latitude: Self.bangkok.lat, longitude: Self.bangkok.lon))
        XCTAssertEqual(s.energy, l.kWp * hourly / 1000, accuracy: 1e-9)
        XCTAssertTrue(l.summaryLine(latitude: Self.bangkok.lat, longitude: Self.bangkok.lon, facing: nil)
            .contains(String(format: "%.1f MWh/ปี", l.kWp * hourly / 1000)))
        // the shade kept for one site isn't served for another
        let a = try XCTUnwrap(TankShade.current(v, latitude: Self.bangkok.lat, longitude: Self.bangkok.lon))
        let b = try XCTUnwrap(TankShade.current(v, latitude: Self.bangkok.lat))
        XCTAssertNotEqual(a.energy, b.energy)
    }
}

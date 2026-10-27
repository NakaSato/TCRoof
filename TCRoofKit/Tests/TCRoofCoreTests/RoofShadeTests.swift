import XCTest
import PVYield
@testable import TCRoofCore

/// C1's shade card (docs/ui/survey-c1-ipad-shade): the obstacles' shade on the modules (`RoofObstacleShade`, change 1),
/// the figures (`RoofShade`, change 2) and the plan's moment (3b).
final class RoofShadeTests: XCTestCase {
    static let site = (lat: 13.75, lon: 100.50)
    static let bangkok = "13.75, 100.50"

    /// A 12 × 10 m gable, ridge along x, the plan's top north, shade avoidance off so modules sit in the shadows; with a
    /// stack (2.00 m) or another obstacle at (x, y).
    static func values(_ obstacle: (kind: RoofObstacleKind, x: Double, y: Double)? = nil) -> Values {
        var v = Values()
        Roof.setSpans(&v, .x, [6, 6]); Roof.setSpans(&v, .y, [5, 5]); Roof.setRidge(&v, .h)
        v[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: "")
        var c = RoofMount.Choice()
        c.avoidShade = false
        RoofMount.setChoice(&v, c)
        if let o = obstacle { Roof.addArea(&v, kind: o.kind.rawValue, x1: o.x, y1: o.y, x2: o.x + 0.6, y2: o.y + 0.6) }
        return v
    }

    static func layout(_ v: Values) -> RoofMountLayout { RoofMount.layout(v, latitude: site.lat, longitude: site.lon).layout }

    /// A stack on the south face, between the eave and the modules near the ridge.
    static let southStack = layout(values((.stack, 5.7, 8.4)))
    /// The same stack on the north face.
    static let northStack = layout(values((.stack, 5.7, 1.0)))
    static let bare = layout(values())

    /// The sun at 21 December, local noon (12:15, the sun's transit at 100.5° E).
    static func decemberNoon(_ s: RoofObstacleShade) -> RoofObstacleShade.P3 {
        let p = SolarPosition.position(unix: 1_797_811_200 + (12.25 - 7) * 3600, site: .init(latitude: site.lat, longitude: site.lon))
        return s.sun(azimuth: p.azimuth, elevation: p.apparentElevation)
    }

    func faceIndex(_ s: RoofObstacleShade, _ id: String) throws -> Int { try XCTUnwrap(s.faces.firstIndex { $0.id == id }) }

    // MARK: - Change 1: obstacles shade the modules

    func testAnObstacleWithoutHeightChangesNothing() {
        let other = Self.layout(Self.values((.other, 5.7, 8.4)))
        XCTAssertNil(RoofObstacleShade(other))
        XCTAssertNil(RoofObstacleShade(Self.bare))
        let i = RoofMountYield.inputs(other, job: RoofMountYieldTests.job(gps: Self.bangkok))
        XCTAssertNil(i.shade)
        XCTAssertFalse(RoofMountYield.estimate(i).assumptions.contains { $0.contains("เงาสิ่งกีดขวาง") })
    }

    func testAStackSouthOfTheModulesShadesThemAtDecemberNoon() throws {
        let s = try XCTUnwrap(RoofObstacleShade(Self.southStack))
        let south = try faceIndex(s, "S")
        XCTAssertEqual(s.obstacles.first?.height, 2.0)
        XCTAssertGreaterThan(s.fraction(face: south, sun: Self.decemberNoon(s)), 0)
        // the hourly fractions at that hour, and the engine's beam
        let i = RoofMountYield.inputs(Self.southStack, job: RoofMountYieldTests.job(gps: Self.bangkok))
        let near = try XCTUnwrap(BundledWeather.nearest(latitude: Self.site.lat, longitude: Self.site.lon))
        let track = try BundledWeather.track(near.dataset, latitude: Self.site.lat, longitude: Self.site.lon)
        let hourly = try XCTUnwrap(s.hourly(track)["S"])
        XCTAssertEqual(hourly.count, track.hours.count)
        let noon = try XCTUnwrap(track.hours.firstIndex { h in
            let d = Calendar.utc.dateComponents([.month, .day, .hour], from: Date(timeIntervalSince1970: Double(h.unix + 7 * 3600)))
            return d.month == 12 && d.day == 21 && d.hour == 12
        })
        XCTAssertGreaterThan(hourly[noon], 0)
        XCTAssertTrue(hourly.allSatisfy { (0...1).contains($0) })
        var without = i
        without.shade = nil
        let shaded = RoofMountYield.estimate(i), free = RoofMountYield.estimate(without)
        XCTAssertTrue(shaded.isHourly)
        XCTAssertLessThan(try XCTUnwrap(shaded.faces.first { $0.id == "S" }).mwh, try XCTUnwrap(free.faces.first { $0.id == "S" }).mwh)
        XCTAssertTrue(shaded.assumptions.contains { $0.contains("เงาสิ่งกีดขวาง") })
    }

    func testAStackNorthOfASouthFaceShadesNothingAtNoon() throws {
        let s = try XCTUnwrap(RoofObstacleShade(Self.northStack))
        XCTAssertEqual(s.fraction(face: try faceIndex(s, "S"), sun: Self.decemberNoon(s)), 0)
    }

    /// The roof's golden figures without obstacle shade: those of the hip sample before obstacles shaded anything.
    func testTheFiguresWithoutObstacleShadeAreUnchanged() {
        var i = RoofMountYield.inputs(RoofMountYieldTests.layout, job: RoofMountYieldTests.job(gps: "13.80, 100.55"))
        XCTAssertNotNil(i.shade)   // its turbine and pipe have heights
        i.shade = nil
        let e = RoofMountYield.estimate(i)
        XCTAssertEqual(e.mwh, 85.193660, accuracy: 1e-5)
        XCTAssertEqual(e.kWhPerKWp, 1451.092826, accuracy: 1e-5)
        XCTAssertEqual(e.faces.map(\.id), ["S", "N", "E", "W"])
        XCTAssertEqual(e.faces[0].mwh, 32.611329, accuracy: 1e-5)
        XCTAssertEqual(e.faces[1].mwh, 29.343054, accuracy: 1e-5)
    }

    // MARK: - Change 2: the figures

    func testNoShadeIsFullSunAccess() throws {
        let i = RoofMountYield.inputs(Self.bare, job: RoofMountYieldTests.job(gps: Self.bangkok))
        let r = try XCTUnwrap(RoofMountYield.estimateAndShade(i).shade.shade)
        XCTAssertEqual(r.groups.map(\.id), i.faces.map(\.id) + (i.faces.count > 1 ? ["all"] : []))
        for g in r.groups {
            XCTAssertEqual(g.sunAccess, 1, accuracy: 1e-12)
            XCTAssertTrue(g.monthlySunAccess.allSatisfy { abs($0 - 1) < 1e-12 })
            XCTAssertTrue(g.silhouettes.isEmpty)
        }
        XCTAssertEqual(r.groups.last?.title, "รวมทั้งหลังคา")
        XCTAssertEqual(r.groups.first?.title, "ด้านใต้")
        XCTAssertEqual(r.groups.first?.caption, "ด้านใต้ของสันหลังคา")
        XCTAssertEqual(r.moduleName, "ZNSHINE 570 W")
        XCTAssertTrue(r.sourceLine.hasPrefix("PVYield รายชั่วโมง | PVGIS-ERA5 TMY กรุงเทพฯ | พิกัด A1 13.75° N"), r.sourceLine)
    }

    func testTheFiguresWithAStack() throws {
        let i = RoofMountYield.inputs(Self.southStack, job: RoofMountYieldTests.job(gps: Self.bangkok))
        let r = try XCTUnwrap(RoofMountYield.estimateAndShade(i).shade.shade)
        let south = try XCTUnwrap(r.groups.first { $0.id == "S" })
        XCTAssertLessThan(south.sunAccess, 1)
        XCTAssertGreaterThan(south.sunAccess, 0.5)
        XCTAssertEqual(south.orientations.first?.azimuthText, "S 180°")
        XCTAssertFalse(south.silhouettes.isEmpty)
        for g in r.groups {
            XCTAssertEqual(g.tsrf, g.tof * g.sunAccess, accuracy: 1e-12)
            XCTAssertTrue(g.monthlySunAccess.allSatisfy { (0...1).contains($0) })
            XCTAssertTrue(g.monthlyShading.allSatisfy { (0...1).contains($0) })
            XCTAssertLessThanOrEqual(g.tof, 1 + 1e-9)
            XCTAssertEqual(g.hourMonth.count, 12)
            XCTAssertTrue(g.hourMonth.allSatisfy { $0.count == r.hours.count })
            XCTAssertTrue(g.hourMonth.joined().compactMap { $0 }.allSatisfy { (0...1).contains($0) })
        }
        // the whole roof sits between its faces
        if let all = r.groups.first(where: { $0.id == "all" }) {
            let faces = r.groups.filter { $0.id != "all" }
            XCTAssertEqual(all.modules, faces.reduce(0) { $0 + $1.modules })
            XCTAssertGreaterThanOrEqual(all.sunAccess, faces.map(\.sunAccess).min()! - 1e-12)
            XCTAssertLessThanOrEqual(all.sunAccess, faces.map(\.sunAccess).max()! + 1e-12)
            XCTAssertEqual(all.tiltAzimuthText.components(separatedBy: ",").count, 2)
        }
        // the charts draw from the same figures
        XCTAssertFalse(r.sunPathSketch(south).ops.isEmpty)
        XCTAssertEqual(r.monthlySketch(south).width, RoofShade.monthlySize.w)
        XCTAssertEqual(r.hourMonthSketch(south).ops.filter { if case .rect = $0 { return true }; return false }.count, 12 * r.hours.count + 5)
    }

    func testAFaceOnTheBestPlaneHasFullTOF() throws {
        // the figures alone (no engine run), on the same track
        let i = RoofMountYield.inputs(Self.bare, job: RoofMountYieldTests.job(gps: Self.bangkok))
        let near = try XCTUnwrap(BundledWeather.nearest(latitude: Self.site.lat, longitude: Self.site.lon))
        let track = try BundledWeather.track(near.dataset, latitude: Self.site.lat, longitude: Self.site.lon)
        func report(_ i: RoofMountYield.Inputs) -> RoofShade { RoofShade.make(i, track: track, shade: [:], weather: "") }
        let best = report(i).bestPlane
        // Bangkok: a low tilt facing about south
        XCTAssertLessThanOrEqual(best.tilt, 20)
        XCTAssertEqual(best.azimuth, 180, accuracy: 30)
        var one = i
        one.faces = [.init(id: "S", modules: 10, tiltDeg: best.tilt, azimuthDeg: best.azimuth, clearSkyYield: 1400)]
        let g = try XCTUnwrap(report(one).groups.first)
        XCTAssertEqual(g.tof, 1, accuracy: 1e-9)
        // a step off it in tilt (1°) or azimuth (2°) is no better
        for (t, a) in [(best.tilt + 1, best.azimuth), (max(0, best.tilt - 1), best.azimuth), (best.tilt, best.azimuth + 2), (best.tilt, best.azimuth - 2)] {
            one.faces[0].tiltDeg = t; one.faces[0].azimuthDeg = a
            XCTAssertLessThanOrEqual(try XCTUnwrap(report(one).groups.first).tof, 1 + 1e-9)
        }
    }

    func testNoReportWithoutGPSOrWeather() {
        let none = RoofMountYield.estimateAndShade(RoofMountYield.inputs(Self.bare, job: RoofMountYieldTests.job(gps: nil))).shade
        XCTAssertEqual(none, .unavailable(RoofShade.noGPS))
        let far = RoofMountYield.estimateAndShade(RoofMountYield.inputs(Self.bare, job: RoofMountYieldTests.job(gps: "18.79, 98.98"))).shade
        XCTAssertEqual(far, .unavailable(RoofShade.noWeather))
    }

    func testTheSunPathAtBangkok() throws {
        let days = RoofShade.sunPath(.init(latitude: 13.75, longitude: 100.5))
        XCTAssertEqual(days.map(\.label), ["มิ.ย.", "มี.ค./ก.ย.", "ธ.ค."])
        let june = try XCTUnwrap(days[0].points.map(\.y).max()), dec = try XCTUnwrap(days[2].points.map(\.y).max())
        XCTAssertEqual(june, 80, accuracy: 1.5)
        XCTAssertEqual(dec, 53, accuracy: 1.5)
        // June's noon sun is in the north, December's in the south
        XCTAssertTrue(days[0].points.max { $0.y < $1.y }.map { $0.x < 90 || $0.x > 270 } ?? false)
        XCTAssertEqual(try XCTUnwrap(days[2].points.max { $0.y < $1.y }).x, 180, accuracy: 10)
        XCTAssertTrue((11...13).contains(days[1].hours.count))
    }

    // MARK: - 3b: the plan's moment

    func testThePlanMarksTheModulesThatTheHourlyShadeCounts() throws {
        let s = try XCTUnwrap(RoofObstacleShade(Self.southStack))
        let m = RoofObstacleShade.planMoment(latitude: Self.site.lat, longitude: Self.site.lon)
        XCTAssertEqual(m.azimuth, 135, accuracy: 15)     // morning sun in the south-east
        let sun = s.sun(azimuth: m.azimuth, elevation: m.elevation)
        let moment = s.moment(latitude: Self.site.lat, longitude: Self.site.lon)
        var counted: Set<RoofMountLayout.SlotRef> = []
        for (i, f) in s.faces.enumerated() where f.used {
            for (k, x) in s.moduleShade(face: i, sun: sun).enumerated() where x > 0 { counted.insert(f.slots[k]) }
        }
        XCTAssertFalse(moment.slots.isEmpty)
        XCTAssertEqual(moment.slots, counted)
        XCTAssertEqual(moment.shadows.count, 1)
        // the face fraction is positive exactly when a module is marked
        for (i, f) in s.faces.enumerated() where f.used {
            XCTAssertEqual(s.fraction(face: i, sun: sun) > 0, f.slots.contains { moment.slots.contains($0) })
        }
        // the plan draws them, tagged `shade`, and only when asked
        let v = Self.values((.stack, 5.7, 8.4))
        let plan = RoofPlan(v, mode: .pv, mount: Self.southStack, shade: moment)
        XCTAssertEqual(plan.tags.filter { $0 == "shade" }.count, moment.slots.count + 2 * moment.shadows.count)
        XCTAssertEqual(RoofPlan(v, mode: .pv, mount: Self.southStack).tags.filter { $0 == "shade" }.count,
                       plan.tags.filter { $0 == "shade" }.count - moment.slots.count - 2 * moment.shadows.count)
    }
}

private extension Calendar {
    static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
}

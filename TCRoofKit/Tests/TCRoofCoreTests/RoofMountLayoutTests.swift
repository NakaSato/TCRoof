import XCTest
@testable import TCRoofCore

/// The roof PV engine against docs/specs/img/roof_pv.py on the spec's three sample roofs (docs/specs/roof-pv-layout.md;
/// the hip and shed roofs are the HTML prototype's, with its single verge/hip setback).
final class RoofMountLayoutTests: XCTestCase {
    static func sky(_ x: Double, _ y: Double, _ h: Double) -> RoofMountInput.Obstacle { .init(kind: .skylight, x: x, y: y, w: 0.82, h: h) }

    /// หลังคาจั่ว 42 × 24 m, purlins @1.20, the plan's top facing 15°.
    static func gable(purlins: Double = 1.20) -> RoofMountInput {
        let skylights = [10.3, 20.6, 30.9].flatMap { x in [sky(x, 3, 6), sky(x, 15, 6)] }
        let turbines = [4.7, 15.7, 26.2, 36.7].map { RoofMountInput.Obstacle(kind: .turbine, x: $0, y: 10.9, w: 0.6, h: 0.6) }
        return RoofMountInput(spansX: Array(repeating: 6, count: 7), spansY: Array(repeating: 6, count: 4), shape: .gable,
                              eaveHeight: 6.0, ridgeHeight: 7.5, purlinSpacing: purlins, latitude: 17, bearing: 15,
                              obstacles: skylights + turbines + [
                                .init(kind: .stack, x: 37.2, y: 16.4, w: 0.5, h: 0.5, height: 2.5),
                                .init(kind: .pipe, x: 16.9, y: 5.2, w: 0.15, h: 0.15, height: 0.8),
                                .init(kind: .other, x: 2.0, y: 19.0, w: 1.6, h: 1.2, height: 0.9, label: "คอยล์ร้อนแอร์"),
                              ])
    }

    /// หลังคาปั้นหยา 30 × 18 m, purlins @1.00.
    static let hip = RoofMountInput(spansX: Array(repeating: 5, count: 6), spansY: Array(repeating: 6, count: 3), shape: .hip,
                                    eaveHeight: 4.0, ridgeHeight: 6.6, purlinSpacing: 1.0, latitude: 17, bearing: 0,
                                    obstacles: [.init(kind: .turbine, x: 14.7, y: 8.0, w: 0.6, h: 0.6), sky(8.0, 12.5, 4), sky(21.0, 12.5, 4),
                                                .init(kind: .pipe, x: 22.0, y: 4.0, w: 0.15, h: 0.15, height: 0.6)])

    /// หลังคาเพิงหมาแหงน 30 × 12 m, purlins @1.10, the plan's top facing −20°.
    static let shed = RoofMountInput(spansX: Array(repeating: 6, count: 5), spansY: [6, 6], shape: .shed,
                                     eaveHeight: 5.0, ridgeHeight: 6.3, purlinSpacing: 1.1, latitude: 17, bearing: -20,
                                     obstacles: [sky(9.0, 1.0, 10), sky(19.5, 1.0, 10), .init(kind: .stack, x: 26.0, y: 3.0, w: 0.6, h: 0.6, height: 1.8)])

    /// The three samples' default layouts, searched once per run and shared by the tests that only read them.
    static let gableBest = RoofMountLayout.best(gable())
    static let hipBest = RoofMountLayout.best(hip)
    static let shedBest = RoofMountLayout.best(shed)
    static var samples: [RoofMountLayout] { [gableBest, hipBest, shedBest] }

    func testGableMatchesThePrototype() {
        let l = Self.gableBest
        let q = l.quantities
        XCTAssertEqual(q.modules, 216)
        XCTAssertEqual(q.kWp, 129.6, accuracy: 1e-9)
        XCTAssertEqual(q.energy, 191.1, accuracy: 0.05)
        XCTAssertEqual(q.railLength, 502.2, accuracy: 0.05)
        XCTAssertEqual(q.splices, 80)
        XCTAssertEqual(q.feet, 496)
        XCTAssertEqual(q.midClamps, 364)
        XCTAssertEqual(q.endClamps, 136)
        XCTAssertEqual(q.runs, 34)
        XCTAssertEqual(q.cuts, 0)
        XCTAssertEqual(q.moved, 6)

        let s = l.faces[0], n = l.faces[1]
        XCTAssertEqual(s.face.id, "S")
        XCTAssertEqual(s.face.azimuth, 195, accuracy: 0.5)
        XCTAssertEqual(n.face.azimuth, 15, accuracy: 0.5)
        XCTAssertEqual(s.face.tilt * 180 / .pi, 7.1, accuracy: 0.05)
        XCTAssertEqual(s.yield, 1493, accuracy: 0.5)
        XCTAssertEqual(n.yield, 1458, accuracy: 0.5)
        XCTAssertEqual(s.modules, 105)
        XCTAssertEqual(n.modules, 111)
        XCTAssertEqual(s.rows.map { ($0.v * 100).rounded() / 100 }, [0.52, 2.92, 5.32, 7.72])
        XCTAssertEqual(s.placement, .init(columnOffset: 0.55, rowShift: 0, centred: false))
        XCTAssertEqual(n.placement.columnOffset, 0, accuracy: 1e-9)
        XCTAssertEqual(s.tried, 1656)
        XCTAssertEqual(s.shade.count, 234)
        XCTAssertTrue(s.used && n.used)
    }

    func testRibClampFitsMoreOnTheSample() {
        XCTAssertEqual(RoofMountLayout.best(Self.gable(), options: .init(ribClamp: true)).quantities.modules, 222)
    }

    func testPurlinSpacingDecidesTheRows() {
        // §3.2's table: modules, and rows on each face
        for (s, modules, rows) in [(1.00, 226, 4), (1.10, 223, 4), (1.20, 216, 4), (1.50, 160, 3)] {
            let l = RoofMountLayout.best(Self.gable(purlins: s))
            XCTAssertEqual(l.quantities.modules, modules, "@\(s)")
            XCTAssertEqual(l.faces.map(\.rows.count), [rows, rows], "@\(s)")
        }
    }

    func testHipMatchesThePrototype() {
        let l = Self.hipBest
        let q = l.quantities
        XCTAssertEqual(q.modules, 105)
        XCTAssertEqual(q.energy, 91.2, accuracy: 0.05)
        XCTAssertEqual(q.railLength, 243.7, accuracy: 0.05)
        XCTAssertEqual(q.splices, 44)
        XCTAssertEqual(q.feet, 233)
        XCTAssertEqual(q.runs, 14)
        XCTAssertEqual(q.moved, 4)
        XCTAssertEqual(l.faces.map(\.face.id), ["S", "N", "E", "W"])
        XCTAssertEqual(l.faces.map(\.modules), [38, 39, 14, 14])
        XCTAssertEqual(l.faces.map { $0.face.azimuth.rounded() }, [180, 0, 90, 270])
        XCTAssertEqual(l.faces[0].tried, 1518)
    }

    func testShedMatchesThePrototype() {
        let q = Self.shedBest.quantities
        XCTAssertEqual(q.modules, 76)
        XCTAssertEqual(q.energy, 68.0, accuracy: 0.05)
        XCTAssertEqual(q.railLength, 176.9, accuracy: 0.05)
        XCTAssertEqual(q.splices, 20)
        XCTAssertEqual(q.feet, 178)
        XCTAssertEqual(q.runs, 13)
    }

    // MARK: rules that hold for every layout (§6 tests)

    func testRailsSitOnPurlinsInsideTheClampingZone() {
        for l in Self.samples {
            let s = l.standard
            for f in l.faces {
                for row in f.rows {
                    XCTAssertTrue(l.purlins.contains { abs($0 - row.rails.0) < 1e-9 } && l.purlins.contains { abs($0 - row.rails.1) < 1e-9 })
                    XCTAssertTrue((s.clampMin - 1e-9...s.clampMax + 1e-9).contains(row.rails.0 - row.v))
                    XCTAssertTrue((s.clampMin - 1e-9...s.clampMax + 1e-9).contains(row.v + s.moduleLength - row.rails.1))
                }
            }
        }
    }

    func testNoModuleOverASkylightOrInShadeAndNoFootNearAnObstacle() {
        for l in Self.samples {
            let s = l.standard
            for f in l.faces {
                for row in f.rows {
                    for slot in row.slots where slot.isModule {
                        let rect = [Pt(slot.u, row.v), Pt(slot.u + s.moduleWidth, row.v), Pt(slot.u + s.moduleWidth, row.v + s.moduleLength),
                                    Pt(slot.u, row.v + s.moduleLength)]
                        XCTAssertTrue(f.face.contains(rect), "module past a setback or a hip line on \(f.face.id)")
                        for ob in f.obstacles {
                            let b = ob.box, m = ob.obstacle.kind.moduleClearance
                            XCTAssertFalse(slot.u < b.u1 + m && b.u0 - m < slot.u + s.moduleWidth && row.v < b.v1 + m && b.v0 - m < row.v + s.moduleLength)
                        }
                        XCTAssertFalse(f.shade.contains { Polygon.overlap(rect, $0) }, "module in shade on \(f.face.id)")
                    }
                    for run in row.runs {
                        for (rail, feet) in zip([row.rails.0, row.rails.1], run.feet) {
                            for x in feet {
                                for ob in f.obstacles {
                                    let b = ob.box, m = ob.obstacle.footClearance
                                    if b.v0 - m <= rail && rail <= b.v1 + m { XCTAssertFalse(b.u0 - m < x && x < b.u1 + m, "foot on an obstacle") }
                                }
                            }
                            XCTAssertTrue(zip(feet, feet.dropFirst()).allSatisfy { $1 - $0 <= s.footSpacing + 1e-9 })
                        }
                    }
                }
            }
        }
    }

    // MARK: options

    func testAFaceSwitchedOffLeavesTheQuantities() {
        let l = RoofMountLayout.compute(Self.gable(), options: .init(faceUse: ["N": false]))
        XCTAssertFalse(l.faces[1].used)
        XCTAssertEqual(l.quantities.modules, 105)
    }

    func testRemovedSlotsAndAFixedPlacement() {
        let best = Self.gableBest
        var o = RoofMountLayout.Options()
        let first = best.faces[0].rows[0].slots.firstIndex(where: \.isModule)!
        o.removed = [.init(face: "S", row: 0, column: first)]
        let l = RoofMountLayout.compute(Self.gable(), options: o, placements: best.placements)
        XCTAssertEqual(l.faces[0].rows[0].slots[first].blocked, RoofMountLayout.removedByUser)
        XCTAssertEqual(l.quantities.modules, 215)
        XCTAssertEqual(RoofMountLayout.best(Self.gable(), options: o).quantities.modules, 216)   // the search clears them
    }

    func testShadeOffLetsModulesIntoTheShade() {
        let off = RoofMountLayout.best(Self.gable(), options: .init(avoidShade: false))
        XCTAssertGreaterThanOrEqual(off.quantities.modules, 216)
        XCTAssertFalse(off.faces.flatMap(\.rows).flatMap(\.slots).contains { $0.blocked == RoofMountLayout.shaded })
    }

    // MARK: open questions decided (§9)

    func testTileHooksSitOnRaftersAndRowsIgnoreThePurlins() {
        let s = RoofMountStandard.standard
        let l = RoofMountLayout.best(Self.gable(), options: .init(tileHooks: true))
        XCTAssertTrue(l.quantities.hooks)
        XCTAssertGreaterThan(l.quantities.modules, 0)
        for f in l.faces {
            let u0 = f.face.polygon.map(\.x).min() ?? 0
            for row in f.rows {
                XCTAssertEqual(row.rails.0 - row.v, s.moduleLength / 4, accuracy: 1e-9)
                XCTAssertTrue(RoofMountDrawings.rowPasses(row, in: l))
                for run in row.runs {
                    for hooks in run.feet {
                        XCTAssertFalse(hooks.isEmpty)
                        for x in hooks {
                            let k = (x - u0) / s.rafterSpacing
                            XCTAssertEqual(k, k.rounded(), accuracy: 1e-6, "a hook off a rafter")
                        }
                        XCTAssertTrue(zip(hooks, hooks.dropFirst()).allSatisfy { $1 - $0 <= s.rafterSpacing + 1e-9 })
                    }
                }
            }
        }
        XCTAssertTrue(RoofMount.boqLine(l.quantities).contains("ขอเกี่ยวกระเบื้อง"))
        XCTAssertTrue(RoofMountDrawings.rowSection(l, face: 0, row: 0).ops.contains {
            if case .text(let t, _, _, _, _, _, _) = $0 { return t.contains("ขอเกี่ยวกระเบื้อง") } else { return false }
        })
    }

    /// ด้านยาวตามแป: landscape modules, the long side along the eave, with the rails on purlins inside the short side's
    /// share of the clamping zone.
    func testLandscapeModulesLieAlongThePurlins() {
        let s = RoofMountStandard.standard
        // purlins @1.20 can't put two rails inside a 1.13 m module's clamping zone: none fits, and the tab says so
        XCTAssertEqual(RoofMountLayout.best(Self.gable(), options: .init(landscape: true)).quantities.modules, 0)
        XCTAssertFalse(RoofMountLayout.purlinsHoldLandscape(s, purlinSpacing: 1.20))
        XCTAssertTrue(RoofMountLayout.purlinsHoldLandscape(s, purlinSpacing: 0.60))
        let l = RoofMountLayout.best(Self.gable(purlins: 0.60), options: .init(landscape: true))
        XCTAssertEqual(l.moduleUp, s.moduleWidth); XCTAssertEqual(l.moduleAlong, s.moduleLength)
        XCTAssertGreaterThan(l.quantities.modules, 0)
        let z = RoofMountLayout.clampZone(s, side: s.moduleWidth)
        for f in l.faces {
            for row in f.rows {
                XCTAssertTrue(l.purlins.contains { abs($0 - row.rails.0) < 1e-9 } && l.purlins.contains { abs($0 - row.rails.1) < 1e-9 })
                XCTAssertTrue((z.min - 1e-9...z.max + 1e-9).contains(row.rails.0 - row.v))
                XCTAssertTrue((z.min - 1e-9...z.max + 1e-9).contains(row.v + s.moduleWidth - row.rails.1))
                for slot in row.slots where slot.isModule {
                    let rect = [Pt(slot.u, row.v), Pt(slot.u + s.moduleLength, row.v), Pt(slot.u + s.moduleLength, row.v + s.moduleWidth),
                                Pt(slot.u, row.v + s.moduleWidth)]
                    XCTAssertTrue(f.face.contains(rect))
                }
            }
        }
        XCTAssertTrue(RoofMount.summaryLine(l).contains("แผงด้านยาวตามแป | รางตามแป"))
    }

    /// รางตัดแป: rails up the slope, a foot on each purlin they cross (none near an obstacle), every module on a run.
    func testRailsAcrossThePurlinsPortrait() { checkRailsAcross(landscape: false) }
    func testRailsAcrossThePurlinsLandscape() { checkRailsAcross(landscape: true) }

    func checkRailsAcross(landscape: Bool) {
        do {
            for input in [Self.gable(), Self.hip, Self.shed] {
                let l = RoofMountLayout.best(input, options: .init(landscape: landscape, railsAcross: true)), s = l.standard
                let q = l.quantities
                XCTAssertGreaterThan(q.modules, 0)
                for f in l.faces {
                    XCTAssertTrue(f.rows.allSatisfy(\.runs.isEmpty), "no rails along the eave")
                    var held = 0
                    for run in f.columnRuns {
                        XCTAssertEqual(run.railsAt.count, 2); XCTAssertEqual(run.feet.count, 2)
                        held += run.count
                        for (u, feet) in zip(run.railsAt, run.feet) {
                            XCTAssertGreaterThanOrEqual(feet.count, 2)
                            for v in feet {
                                XCTAssertTrue(l.purlins.contains { abs($0 - v) < 1e-9 }, "a foot off a purlin")
                                XCTAssertTrue(v > run.start && v < run.end)
                                for ob in f.obstacles {
                                    let b = ob.box, m = ob.obstacle.footClearance
                                    if b.u0 - m <= u && u <= b.u1 + m { XCTAssertFalse(b.v0 - m < v && v < b.v1 + m, "foot on an obstacle") }
                                }
                            }
                            XCTAssertTrue(zip(feet, feet.dropFirst()).allSatisfy { $1 - $0 <= max(s.footSpacing, input.purlinSpacing) + 1e-6 })
                        }
                        // the modules of a run touch, in one column
                        let rows = run.rows.map { f.rows[$0] }
                        XCTAssertTrue(zip(rows, rows.dropFirst()).allSatisfy { abs($1.v - ($0.v + l.moduleUp + s.moduleGap)) < 1e-6 })
                    }
                    XCTAssertEqual(held, f.modules, "every module on a run across the purlins")
                }
                XCTAssertEqual(q.runs, l.faces.filter(\.used).map(\.columnRuns.count).reduce(0, +))
                XCTAssertTrue(RoofMountDrawings.rowSection(l, face: 0, row: 0).ops.contains {
                    if case .text(let t, _, _, _, _, _, _) = $0 { return t.contains("รางตัดแป") } else { return false }
                })
            }
        }
        // rib clamps and tile hooks keep their rails along the eave
        XCTAssertFalse(RoofMountLayout.Options(ribClamp: true, railsAcross: true).acrossPurlins)
        XCTAssertFalse(RoofMountLayout.Options(tileHooks: true, railsAcross: true).acrossPurlins)
    }

    /// What the installation rules read off a layout: which side the clamps hold and the offsets A, inside the zone the
    /// engine laid the rails in.
    func testClampSideAndOffsets() {
        let l = Self.gableBest, s = l.standard
        XCTAssertTrue(l.clampsLongSide)
        XCTAssertFalse(l.clampOffsetsMm.isEmpty)
        for a in l.clampOffsetsMm { XCTAssertTrue((s.clampMin * 1000 - 1)...(s.clampMax * 1000 + 1) ~= a, "\(a)") }
        XCTAssertEqual(l.usedFaceAngles.count, 2)
        XCTAssertEqual(l.usedFaceAngles[0].tilt, l.roof.tilt * 180 / .pi, accuracy: 1e-9)
        XCTAssertFalse(RoofMountLayout.best(Self.gable(), options: .init(railsAcross: true)).clampsLongSide, "portrait on rails up the slope")
        let land = RoofMountLayout.best(Self.gable(), options: .init(landscape: true, railsAcross: true))
        XCTAssertTrue(land.clampsLongSide)
        // rails at ¼ and ¾ of the long side along the eave
        XCTAssertEqual(land.clampOffsetsMm.first ?? 0, (s.moduleLength / 4 * 1000).rounded(), accuracy: 1)
    }

    /// An older job's choice has no direction, and the default writes nothing new (its digest stays).
    func testTheDirectionDefaultsKeepOlderJobs() throws {
        let c = try JSONDecoder().decode(RoofMount.Choice.self, from: Data(#"{"ribClamp":false,"avoidShade":true}"#.utf8))
        XCTAssertFalse(c.landscape); XCTAssertFalse(c.railsAcross)
        let json = String(decoding: try JSONEncoder().encode(RoofMount.Choice()), as: UTF8.self)
        XCTAssertFalse(json.contains("landscape") || json.contains("railsAcross"))
        var turned = RoofMount.Choice(); turned.railsAcross = true
        XCTAssertNotEqual(RoofMount.digest(Self.gable(), choice: turned), RoofMount.digest(Self.gable(), choice: RoofMount.Choice()))
    }

    func testAWalkwayEveryNColumns() {
        let l = RoofMountLayout.best(Self.gable(), options: .init(walkwayEvery: 6))
        for f in l.faces {
            for row in f.rows {
                for (c, slot) in row.slots.enumerated() where c % 7 == 6 { XCTAssertEqual(slot.blocked, RoofMountLayout.walkway) }
                // no run spans a walkway
                for run in row.runs { XCTAssertFalse(run.columns.contains { $0 % 7 == 6 }) }
            }
        }
        XCTAssertLessThan(l.quantities.modules, 216)
    }

    func testTheShedTurnsToItsLowSide() {
        var flipped = Self.shed
        flipped.shedLowAtStart = true
        let a = Self.shedBest.faces[0].face, b = RoofMountLayout.best(flipped).faces[0].face
        XCTAssertEqual(a.id, "S")
        XCTAssertEqual(b.id, "N")
        XCTAssertEqual((b.azimuth - a.azimuth + 360).truncatingRemainder(dividingBy: 360), 180, accuracy: 1e-6)
        // the low eave (v = 0) is at the plan's top
        XCTAssertEqual(b.plan(1, 0).y, 0, accuracy: 1e-9)
        XCTAssertEqual(a.plan(1, 0).y, Self.shed.lengthY, accuracy: 1e-9)
    }

    func testTheClampingZoneFollowsTheModule() {
        var s = RoofMountStandard()
        XCTAssertTrue(s.clampFollowsModule)
        XCTAssertEqual(s.clampFromModule.min, 0.34); XCTAssertEqual(s.clampFromModule.max, 0.68)
        s.moduleLength = 2.38
        XCTAssertEqual(s.clampFromModule.min, 0.35); XCTAssertEqual(s.clampFromModule.max, 0.71)
        s.moduleLength = 1.72
        XCTAssertEqual(s.clampFromModule.min, 0.26); XCTAssertEqual(s.clampFromModule.max, 0.51)
        s.clampMin = 0.40
        XCTAssertFalse(s.clampFollowsModule)
        let d = RoofMount.defaultStandard
        XCTAssertEqual(d.clampMin, d.clampFromModule.min); XCTAssertEqual(d.clampMax, d.clampFromModule.max)
    }

    func testTheRoofLoadWarnsAboveTheLimit() {
        var s = RoofMountStandard.standard
        let q = RoofMountLayout.best(Self.gable(), standard: s).quantities
        let expected = (Double(q.modules) * s.moduleKg + q.railLength * s.railKgPerM + Double(q.feet) * s.footKg)
            / (Double(q.modules) * s.moduleLength * s.moduleWidth)
        XCTAssertEqual(q.load, expected, accuracy: 1e-9)
        XCTAssertFalse(q.overLoad)
        s.loadLimit = 10
        let over = RoofMountLayout.best(Self.gable(), standard: s).quantities
        XCTAssertTrue(over.overLoad)
        XCTAssertTrue(RoofMount.loadLine(over).contains("เกินเกณฑ์"))
    }

    func testTheStandardDecodesWithMissingFields() throws {
        let s = try JSONDecoder().decode(RoofMountStandard.self, from: Data(#"{"moduleWp":550,"setVerge":0.6}"#.utf8))
        XCTAssertEqual(s.moduleWp, 550)
        XCTAssertEqual(s.setVerge, 0.6)
        XCTAssertEqual(s.clampMin, 0.34)
    }

    func testSunAndYieldModel() throws {
        let noon = try XCTUnwrap(SolarModel.sun(lat: 17, day: 80, time: 12))
        XCTAssertEqual(noon.altitude, 73, accuracy: 0.5)
        XCTAssertNil(SolarModel.sun(lat: 17, day: 80, time: 4))
        XCTAssertGreaterThan(SolarModel.yield(lat: 17, tilt: 15, azimuthFromSouth: 0), SolarModel.yield(lat: 17, tilt: 15, azimuthFromSouth: 180))
    }
}

/// `หาผังที่ได้แผงมากที่สุด` tries every module and rail direction and keeps the one with the most modules.
final class RoofMountMostModulesTests: XCTestCase {
    static func roof(purlins: Double) -> Values {
        var v = Values()
        v["spansX"] = .text("1.5,6,6,6,6,1.5"); v["spansY"] = .text("1.5,6,6,1.5")
        v[Roof.Key.purlin] = .text(String(purlins))
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        return v
    }

    func testKeepsTheDirectionWithTheMostModules() {
        var v = Self.roof(purlins: 1.2)
        let r = RoofMount.mostModules(v, latitude: 15)
        XCTAssertEqual(r.arrangements.count, Set(r.arrangements.map(\.label)).count)
        XCTAssertGreaterThanOrEqual(r.arrangements.count, 3)
        XCTAssertEqual(r.layout.quantities.modules, r.arrangements.map(\.modules).max())
        XCTAssertEqual(r.arrangements.first, .init(landscape: false, railsAcross: false, modules: r.arrangements[0].modules),
                       "the current directions are tried first")
        // the choice comes back ready: the stored layout is the one found, not searched again
        RoofMount.setChoice(&v, r.choice)
        let kept = RoofMount.layout(v, latitude: 15)
        XCTAssertFalse(kept.fresh)
        XCTAssertEqual(kept.layout.quantities.modules, r.layout.quantities.modules)
        XCTAssertEqual(kept.layout.options.landscape, r.choice.landscape)
    }

    /// Rails along the purlins only take rows whose rails land on purlins; rails across them never hold fewer.
    func testRailsAcrossHoldAtLeastAsMany() {
        let r = RoofMount.mostModules(Self.roof(purlins: 1.5), latitude: 15)
        let along = r.arrangements.first { !$0.landscape && !$0.railsAcross }!.modules
        let across = r.arrangements.first { !$0.landscape && $0.railsAcross }!.modules
        XCTAssertGreaterThanOrEqual(across, along)
        XCTAssertGreaterThanOrEqual(r.layout.quantities.modules, across)
    }

    func testATieKeepsTheCurrentDirections() {
        var v = Self.roof(purlins: 1.2)
        var c = RoofMount.choice(v); c.landscape = true; c.railsAcross = true
        RoofMount.setChoice(&v, c)
        let r = RoofMount.mostModules(v, latitude: 15)
        XCTAssertEqual(r.arrangements.first?.landscape, true)
        XCTAssertEqual(r.arrangements.first?.railsAcross, true)
        let top = r.arrangements.map(\.modules).max()!
        if r.arrangements[0].modules == top { XCTAssertTrue(r.choice.landscape && r.choice.railsAcross) }
    }
}

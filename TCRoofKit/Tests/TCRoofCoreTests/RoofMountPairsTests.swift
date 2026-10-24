import XCTest
@testable import TCRoofCore

/// Landscape pairs (วางคู่ 2 แผ่น) and the ridge walkway's width (docs/ui/survey-c1-iphone-pv-fix01).
final class RoofMountPairsTests: XCTestCase {
    /// A plain gable, `length` m along the eave and 8 m across, no obstacles unless given.
    static func gable(length: Double, obstacles: [RoofMountInput.Obstacle] = []) -> RoofMountInput {
        RoofMountInput(spansX: [length], spansY: [8], ridgeAlongX: true, shape: .gable, eaveHeight: 4, ridgeHeight: 5,
                       purlinSpacing: 1.0, latitude: 14, bearing: 0, obstacles: obstacles)
    }

    /// Rib clamps, so the rows don't depend on the purlins; landscape, the shade search off.
    static func options(pairs: Bool) -> RoofMountLayout.Options {
        .init(ribClamp: true, avoidShade: false, landscape: true, landscapePairs: pairs)
    }

    static let start = ["S": RoofMountLayout.Placement(columnOffset: 0, rowShift: 0, centred: false),
                        "N": RoofMountLayout.Placement(columnOffset: 0, rowShift: 0, centred: false)]

    func testPairsAlongTheRow() throws {
        let s = RoofMountStandard.standard
        let m = RoofMountLayout.compute(Self.gable(length: 14), standard: s, options: Self.options(pairs: true), placements: Self.start)
        let row = try XCTUnwrap(m.faces[0].rows.first)
        // 13 m between the verges' setbacks: two pairs (4.58 m each, 0.40 m between), a third doesn't fit
        XCTAssertEqual(row.slots.count, 4)
        let w = s.moduleLength, g = s.moduleGap, gap = RoofMountStandard.pairGap
        let u0 = row.slots[0].u
        let expected = [0, w + g, 2 * w + g + gap, 3 * w + 2 * g + gap]
        for (slot, e) in zip(row.slots, expected) { XCTAssertEqual(slot.u - u0, e, accuracy: 1e-9) }
        // each pair is its own run: 2 modules, 2 mid clamps and 4 end clamps a run
        XCTAssertEqual(row.runs.map(\.columns), [[0, 1], [2, 3]])
        let q = m.quantities, runs = m.faces.filter(\.used).flatMap(\.allRuns).count
        XCTAssertEqual(q.runs, runs)
        XCTAssertEqual(q.modules, 2 * runs)
        XCTAssertEqual(q.midClamps, 2 * runs)
        XCTAssertEqual(q.endClamps, 4 * runs)
    }

    func testAModuleLeftOverIsDropped() throws {
        let tight = RoofMountLayout.compute(Self.gable(length: 14), options: Self.options(pairs: false), placements: Self.start)
        let pairs = RoofMountLayout.compute(Self.gable(length: 14), options: Self.options(pairs: true), placements: Self.start)
        XCTAssertEqual(try XCTUnwrap(tight.faces[0].rows.first).slots.count, 5)
        XCTAssertEqual(try XCTUnwrap(pairs.faces[0].rows.first).slots.count, 4)
        // pairs off keeps one run a row
        XCTAssertEqual(tight.faces[0].rows[0].runs.count, 1)
    }

    func testAnObstacleBreaksItsPair() throws {
        let clean = RoofMountLayout.compute(Self.gable(length: 14), options: Self.options(pairs: true), placements: Self.start)
        let row = clean.faces[0].rows[0], face = clean.faces[0].face
        // a keep-out zone over the middle of the first pair's second module, on the first row
        let mid = face.plan(row.slots[1].u + 1.0, row.v + 0.5)
        let zone = RoofMountInput.Obstacle(kind: .keepOut, x: mid.x - 0.1, y: mid.y - 0.1, w: 0.2, h: 0.2)
        let m = RoofMountLayout.compute(Self.gable(length: 14, obstacles: [zone]), options: Self.options(pairs: true), placements: Self.start)
        let hit = try XCTUnwrap(m.faces.flatMap(\.rows).first { $0.slots.contains { $0.blocked == RoofMountLayout.pairBroken } })
        let broken = try XCTUnwrap(hit.slots.firstIndex { $0.blocked == RoofMountLayout.pairBroken })
        let partner = broken % 2 == 0 ? broken + 1 : broken - 1
        XCTAssertNotNil(hit.slots[partner].blocked)
        XCTAssertNotEqual(hit.slots[partner].blocked, RoofMountLayout.pairBroken)
        XCTAssertFalse(hit.slots[broken].cut)
        // the whole pair goes, and every run still holds whole pairs
        XCTAssertEqual(m.quantities.modules, clean.quantities.modules - 2)
        for f in m.faces { for r in f.rows { for run in r.runs { XCTAssertEqual(run.columns.count, 2) } } }
    }

    func testAnOlderChoiceDecodesWithoutPairsOrWidth() throws {
        let c = try JSONDecoder().decode(RoofMount.Choice.self, from: Data(#"{"landscape":true,"digest":"x"}"#.utf8))
        XCTAssertTrue(c.landscape)
        XCTAssertFalse(c.landscapePairs)
        XCTAssertNil(c.pairGap)
        XCTAssertNil(c.ridgeWalkwayWidth)
        XCTAssertEqual(c.pairGapOrDefault, RoofMountStandard.pairGap)
        // nothing new is written for them, and the digest is the one it had
        let json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        for key in ["landscapePairs", "pairGap", "ridgeWalkwayWidth"] { XCTAssertFalse(json.contains(key), key) }
        let input = Self.gable(length: 14)
        var set = c
        set.landscapePairs = true
        XCTAssertNotEqual(RoofMount.digest(input, choice: set), RoofMount.digest(input, choice: c))
        var portrait = c
        portrait.landscape = false
        var portraitPairs = portrait
        portraitPairs.landscapePairs = true
        XCTAssertEqual(RoofMount.digest(input, choice: portraitPairs), RoofMount.digest(input, choice: portrait), "pairs need landscape")
    }

    func testAWiderRidgeWalkwayKeepsTheRowsOffIt() throws {
        let input = Self.gable(length: 14)
        var narrow = RoofMountLayout.Options(ribClamp: true, avoidShade: false, walkwayRidge: true)
        var wide = narrow
        wide.ridgeWalkwayWidth = 1.20
        let a = RoofMountLayout.compute(input, options: narrow, placements: Self.start)
        let b = RoofMountLayout.compute(input, options: wide, placements: Self.start)
        let face = a.faces[0].face
        // the ridge setback grows by the extra half width
        XCTAssertEqual(a.standard.setRidge, RoofWalkway.ridgeClear, accuracy: 1e-9)
        XCTAssertEqual(b.standard.setRidge, 1.20 / 2 + 0.05, accuracy: 1e-9)
        XCTAssertEqual(face.vMax(a.standard) - b.faces[0].face.vMax(b.standard), (1.20 - RoofWalkway.band) / 2, accuracy: 1e-9)
        for f in b.faces {
            let top = try XCTUnwrap(f.rows.last)
            XCTAssertLessThanOrEqual(top.v + b.moduleUp, f.face.slopeLength - (1.20 / 2 + 0.05) + 1e-9)
        }
        // this roof has room: no module lost
        XCTAssertEqual(b.quantities.modules, a.quantities.modules)
        // the walkway is the clear width, the band still centred on the ridge
        let ra = try XCTUnwrap(RoofWalkway.ridgeWalkway(a)), rb = try XCTUnwrap(RoofWalkway.ridgeWalkway(b))
        XCTAssertEqual(rb.width, 1.20, accuracy: 1e-9)
        XCTAssertEqual(rb.b0, ra.b0, accuracy: 1e-9)
        // never narrower than the team's detail
        narrow.ridgeWalkwayWidth = 0.40
        XCTAssertEqual(narrow.ridgeWidth, RoofWalkway.band)
        XCTAssertEqual(narrow.ridgeClear, RoofWalkway.ridgeClear, accuracy: 1e-9)
    }

    func testThePlanNumbersPairsOnlyWhenAsked() {
        var v = Values()
        v[Roof.Key.spansX] = .text("14"); v[Roof.Key.spansY] = .text("8")
        let m = RoofMountLayout.compute(Self.gable(length: 14), options: Self.options(pairs: true), placements: Self.start)
        let page = RoofPlan(v, mode: .pv, mount: m, pairNumbers: true), report = RoofPlan(v, mode: .pv, mount: m)
        XCTAssertTrue(page.tags.contains("pairs"))
        XCTAssertFalse(report.tags.contains("pairs"))
    }
}

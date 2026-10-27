import XCTest
@testable import TCRoofCore

/// The roof beam plan in D1's DXF, after the team's `reference/Tank_Truss.dxf`.
final class TankFramingTests: XCTestCase {
    let t = DXFRead()
    /// Whether the DXF has a TEXT reading `s` (Thai written in TIS-620).
    func hasText(_ d: Data, _ s: String) -> Bool {
        let key = String(data: SketchDXF.tis620(s), encoding: .isoLatin1)!
        return t.rawEntities(d).contains { $0.first?.1 == "TEXT" && t.value($0, "1") == key }
    }

    /// The team's example: 40 × 24 m on a 4.00 m grid. B1 on the 32 perimeter spans (128 m), B2 on the 104 interior
    /// ones (5 lines of 10 spans along x, 9 lines of 6 along y: 416 m).
    func testTheTeamsExample() {
        let b = TankFraming.beams(x: Array(repeating: 4, count: 10), y: Array(repeating: 4, count: 6))
        let rows = TankFraming.schedule(b)
        XCTAssertEqual(rows.map(\.mark), ["B1", "B2"])
        XCTAssertEqual(rows[0].spans, 32); XCTAssertEqual(rows[0].length, 128, accuracy: 1e-9)
        XCTAssertEqual(rows[1].spans, 104); XCTAssertEqual(rows[1].length, 416, accuracy: 1e-9)
        // a span on the bottom line and on the right line is a perimeter one
        XCTAssertEqual(b.first { $0.along == .x && $0.line == 6 }?.mark, "B1")
        XCTAssertEqual(b.first { $0.along == .y && $0.line == 10 }?.mark, "B1")
        XCTAssertEqual(b.first { $0.along == .y && $0.line == 3 }?.mark, "B2")
        // a one-bay tank is all perimeter
        XCTAssertEqual(TankFraming.schedule(TankFraming.beams(x: [6], y: [5])).map(\.mark), ["B1"])
        XCTAssertTrue(TankFraming.beams(x: [], y: [4]).isEmpty)
    }

    /// In the DXF, right of the plans: a mark on every span, the beam edges on S-BEAM-E (continuous) stopping at the crossing
    /// beams' faces (none longer than its span less a beam), bubbles at both ends of every grid line, the span chains and
    /// overall sizes as DIMENSIONs, the title and the schedule.
    func testTheDXFHasTheBeamPlan() throws {
        let v = TankDXFTests.sample(layout: true), s = Tank.spans(v)
        let out = try XCTUnwrap(TankDXF.build(v)), recs = t.rawEntities(out.data)
        let (n, m) = (s.x.count, s.y.count)
        // the plan starts right of everything else: right of the mounting plan's footings
        let footings = recs.filter { $0.first?.1 == "INSERT" && (t.value($0, "2") ?? "").hasPrefix("TC_FOOTING_") }.map { t.double($0, "10") }
        // the marks at their height (the schedule's cells read B1 / B2 too)
        let marks = recs.filter { $0.first?.1 == "TEXT" && ["B1", "B2"].contains(t.value($0, "1") ?? "") && abs(t.double($0, "40") - TankFraming.markH) < 1e-6 }
        XCTAssertEqual(marks.count, (m + 1) * n + (n + 1) * m)
        XCTAssertEqual(marks.filter { t.value($0, "1") == "B1" }.count, 2 * (n + m))
        let x0 = try XCTUnwrap(marks.map { t.double($0, "10") }.min())
        XCTAssertGreaterThan(x0, try XCTUnwrap(footings.max()))
        // the beam edges: two per interior span, one per perimeter span, and the outer edge in one closed polyline
        let edges = recs.filter { $0.first?.1 == "LINE" && t.value($0, "8") == "S-BEAM-E" && t.double($0, "10") > x0 - 2 }
        XCTAssertEqual(edges.count, 2 * TankFraming.beams(x: s.x, y: s.y).count - 2 * (n + m))
        let longest = max(s.x.max()!, s.y.max()!) - TankFraming.beamWidth
        XCTAssertTrue(edges.allSatisfy { hypot(t.double($0, "11") - t.double($0, "10"), t.double($0, "21") - t.double($0, "20")) <= longest + 1e-6 })
        let outer = recs.filter { $0.first?.1 == "LWPOLYLINE" && t.value($0, "8") == "S-BEAM-E" && t.double($0, "10") > x0 - 2 }
        XCTAssertEqual(outer.count, 1); XCTAssertEqual(outer.first.flatMap { t.value($0, "70") }, "1")
        // continuous lines, ByLayer: the layer's linetype, no entity of its own
        XCTAssertEqual(CADLayers.tankBeamPlan.linetype, .continuous)
        XCTAssertTrue((edges + outer).allSatisfy { t.value($0, "6") == nil })
        // a bubble at both ends of every grid line
        let bubbles = recs.filter { $0.first?.1 == "CIRCLE" && t.value($0, "8") == "G-GRID" && t.double($0, "10") > x0 - 5 }
        XCTAssertEqual(bubbles.count, 2 * (n + 1 + m + 1))
        // the chains: every span each way and the two overall sizes, reading the spans
        let dims = recs.filter { $0.first?.1 == "DIMENSION" && t.double($0, "13") > x0 - 5 }
        XCTAssertEqual(dims.count, n + m + 2)
        let W = s.x.reduce(0, +), H = s.y.reduce(0, +)
        XCTAssertTrue(dims.contains { abs(abs(t.double($0, "14") - t.double($0, "13")) - W) < 1e-3 })
        XCTAssertTrue(dims.contains { abs(abs(t.double($0, "24") - t.double($0, "23")) - H) < 1e-3 })
        // the title and the schedule
        XCTAssertTrue(hasText(out.data, "แปลนคานหลังคาถัง / ROOF BEAM PLAN"))
        XCTAssertTrue(hasText(out.data, "ตารางคาน / BEAM SCHEDULE"))
        XCTAssertTrue(hasText(out.data, "\(2 * (n + m))"), "B1's spans in the schedule")
    }

    /// A round tank has ring beams, not this grid: no beam plan.
    func testARoundTankHasNone() throws {
        var v = TankDXFTests.sample()
        Tank.setShape(&v, .round)
        XCTAssertTrue(Tank.isRound(v))
        let out = try XCTUnwrap(TankDXF.build(v))
        XCTAssertFalse(hasText(out.data, "แปลนคานหลังคาถัง / ROOF BEAM PLAN"))
        XCTAssertTrue(hasText(try XCTUnwrap(TankDXF.build(TankDXFTests.sample())).data, "แปลนคานหลังคาถัง / ROOF BEAM PLAN"))
    }
}

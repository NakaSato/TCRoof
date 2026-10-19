import XCTest
@testable import TCRoofCore

final class InverterStationTests: XCTestCase {
    let cat = EquipmentCatalog.bundled

    func testCatalogDecodes() {
        XCTAssertEqual(cat.version, "2026-09-30")
        XCTAssertEqual(cat.inverters.count, 4)
        XCTAssertEqual(cat.pv.count, 4)
        XCTAssertEqual(cat.cabinets.ac.map(\.w), [900, 1000, 1200])
        XCTAssertEqual(cat.cabinets.dc.map(\.w), [600, 700, 800])
        XCTAssertEqual(cat.cabinets.meter.w, 630)
        XCTAssertEqual(cat.rules.cbFactor, 1.25)
        XCTAssertEqual(cat.inverterSizes, [40, 60, 80, 125])
        XCTAssertEqual(cat.pv.first { $0.def == true }?.id, "p570")
    }

    func testLookupsAndGenericInverter() {
        XCTAssertEqual(cat.acCabinet(inverters: 2).w, 900)
        XCTAssertEqual(cat.acCabinet(inverters: 3).w, 1000)
        XCTAssertEqual(cat.acCabinet(inverters: 12).w, 1200)
        XCTAssertEqual(cat.dcCabinet(mppt: 6).w, 700)
        XCTAssertEqual(cat.dcCabinet(mppt: 10).w, 800)
        let g = cat.inverter(kw: 50)
        XCTAssertEqual(g.model, "50 kW")
        XCTAssertEqual(g.imax, 50_000 / (3.0.squareRoot() * 400), accuracy: 1e-9)
        XCTAssertEqual([g.w, g.h, g.d, g.mppt], [870, 580, 290, 6])
    }

    func testInverterBreakers() {
        let s = InverterStation(sizes: [60])
        XCTAssertEqual(s.breaker(kw: 40).at, 80)
        XCTAssertEqual(s.breaker(kw: 60).at, 125)
        XCTAssertEqual(s.breaker(kw: 80).at, 200)
        XCTAssertEqual(s.breaker(kw: 125).at, 250)
        XCTAssertEqual(s.breaker(kw: 60).af, 125)
        XCTAssertEqual(s.breaker(kw: 40).af, 100)
        XCTAssertEqual(s.cable(kw: 60).label, "4×35+G16")
        XCTAssertEqual(s.cable(kw: 60).od, 41)
    }

    func testTrayFeederLadderTwo60() {
        let s = InverterStation(sizes: [60, 60], width: 2.5, length: 9.5)
        XCTAssertEqual(s.trayMin, 100)
        XCTAssertEqual(s.feeder.at, 250)
        XCTAssertEqual(s.feeder.label, "4×1C 120 + G25")
        XCTAssertEqual(s.feeder.ladderMin, 200)
        XCTAssertEqual(s.breakerSummary, "2 × 125AT")
    }

    func testTrayFeederLadderOverflowMix() {
        let s = InverterStation(sizes: [60, 60, 80], width: 2.5, length: 9.5)
        XCTAssertEqual(s.trayMin, 200)
        XCTAssertEqual(s.feeder.at, 500)
        XCTAssertEqual(s.feeder.label, "2×(4×1C 120) + G35")
        XCTAssertEqual(s.feeder.ladderMin, 400)
        XCTAssertEqual(s.breakerSummary, "2×125+1×200 AT")
    }

    func testOutdoorRoom() {
        let s = InverterStation(sizes: [60, 60], width: 2.5, length: 9.5)
        XCTAssertEqual(s.used, 6.77, accuracy: 1e-9)
        XCTAssertEqual(s.minLength, 9.5)
        XCTAssertEqual(s.spans.map { InverterStation.r2($0) }, [2.5, 2.25, 2.25, 2.5])
        XCTAssertEqual(s.walkway, 1.48, accuracy: 1e-9)
        XCTAssertTrue(s.isOK)
        XCTAssertEqual(s.status, "ครบช่องบังคับแล้ว · พื้นที่พอสำหรับ 2 เครื่อง")
    }

    func testIndoorWall() {
        let s = InverterStation(sizes: [60, 60], width: 2.5, length: 9.5, site: .indoor)
        XCTAssertEqual(s.used, 7.75, accuracy: 1e-9)
        XCTAssertEqual(s.minLength, 8.5)
        XCTAssertEqual(s.walkway, 1.65, accuracy: 1e-9)
        XCTAssertTrue(s.isOK)
    }

    func testOverflow() {
        let s = InverterStation(sizes: [60, 60, 80], width: 2.5, length: 9.5)
        XCTAssertEqual(s.minLength, 12.0)
        XCTAssertEqual(s.shortfall, 2.5, accuracy: 1e-9)
        XCTAssertFalse(s.fits)
        XCTAssertEqual(s.status, "พื้นที่จริงสั้นไป 2.5 ม. สำหรับ 3 เครื่อง")
        XCTAssertTrue(InverterStationDrawing.sketch(s).svg().contains("เกินพื้นที่ 2.50 ม."))
    }

    func testSpans() {
        var s = InverterStation(sizes: [60, 60], width: 2.5, length: 9.5)
        XCTAssertNil(s.userSpans)
        s.userSpans = [2.5, 2.5, 2.5]
        XCTAssertEqual(s.lastSpan, 2.0, accuracy: 1e-9)
        XCTAssertTrue(s.spansOK)
        s.userSpans = [3, 3, 3.2]
        XCTAssertEqual(s.lastSpan, 0.3, accuracy: 1e-9)
        XCTAssertFalse(s.spansOK)
        XCTAssertEqual(s.status, "ระยะช่วงเสารวมเกินความยาวห้อง")
        XCTAssertEqual(s.planSpans, InverterStation.autoSpans(9.5))
        s.userSpans = s.equalSpans
        XCTAssertEqual(s.spans.count, 4)
        for v in s.spans { XCTAssertEqual(v, 2.375, accuracy: 0.006) }
        s.userSpans = nil
        XCTAssertEqual(s.spans.map { InverterStation.r2($0) }, [2.5, 2.25, 2.25, 2.5])
        XCTAssertEqual(InverterStation.autoSpans(4.5), [4.5])
    }

    func testStepSizes() {
        XCTAssertEqual(InverterStation.step(InverterStation.traySizes, from: 100, by: 1, min: 100), 150)
        XCTAssertNil(InverterStation.step(InverterStation.traySizes, from: 100, by: -1, min: 100))
        XCTAssertNil(InverterStation.step(InverterStation.ladderSizes, from: 900, by: 1, min: 200))
        let s = InverterStation(sizes: [60])
        XCTAssertEqual(s.stepSize(60, by: 1), 80)
        XCTAssertEqual(s.stepSize(125, by: 1), 125)
        XCTAssertEqual(s.stepSize(40, by: -1), 40)
        var t = InverterStation(sizes: [60, 60], width: 2.5, length: 9.5, trayPick: 50)
        XCTAssertEqual(t.trayWidth, 100)
        t.trayPick = 300
        XCTAssertEqual(t.trayWidth, 300)
        XCTAssertEqual(t.bandDepth, 0.5, accuracy: 1e-9)
    }

    func testCapacityCheck() {
        let s = InverterStation(sizes: [60, 60])
        XCTAssertEqual(s.capacityCheck(120)?.ok, true)
        XCTAssertEqual(s.capacityCheck(120)?.text, "= A1 ✓")
        XCTAssertEqual(s.capacityCheck(100)?.text, "≠ A1 100")
        XCTAssertNil(s.capacityCheck(nil))
    }

    func testOldJobIsReadAsLabelled() {
        let v = Values(["sizeLWH": .text("6x2"), "inverterCount": .text("2")])
        let s = InverterStation(v)
        XCTAssertEqual(s.width, 6)
        XCTAssertEqual(s.length, 2)
        XCTAssertNil(s.height)
        XCTAssertEqual(s.sizes, [40, 40])
        XCTAssertTrue(s.sizesAssumed)
        // not clamped until edited
        XCTAssertFalse(InverterStation.widthRange.contains(s.width!))
        XCTAssertEqual(InverterStation(Values(["sizeLWH": .text("6 × 2.5 × 3")])).height, 3)
    }

    func testWritesBack() {
        var v = Values(["sizeLWH": .text("6x2"), "inverterCount": .text("2")])
        var s = InverterStation(v)
        s.width = 2.5; s.length = 9.5; s.height = 3
        s.sizes = [60, 60, 80]; s.sizesAssumed = false
        s.write(to: &v)
        XCTAssertEqual(v.text("sizeLWH"), "2.5 x 9.5 x 3")
        XCTAssertEqual(v.text("inverterCount"), "3")
        XCTAssertEqual(v.text("invSizes"), "60,60,80")
        let back = InverterStation(v)
        XCTAssertEqual(back.sizes, [60, 60, 80])
        XCTAssertFalse(back.sizesAssumed)
        XCTAssertEqual(back.width, 2.5)
        XCTAssertEqual(back.length, 9.5)
        // the count edited on the form page wins over stored sizes
        v["inverterCount"] = .text("2")
        XCTAssertEqual(InverterStation(v).sizes, [60, 60])
        // a size edited on the form page wins over stale numbers
        v["sizeLWH"] = .text("3x10")
        XCTAssertEqual(InverterStation(v).length, 10)
        // assumed sizes are not stored
        var old = Values(["inverterCount": .text("2")])
        InverterStation(old).write(to: &old)
        XCTAssertEqual(old.text("invSizes"), "")
        XCTAssertEqual(old.text("inverterCount"), "2")
    }

    func testIndoorDrawing() {
        let s = InverterStation(sizes: [60, 60], width: 2.5, length: 9.5, site: .indoor)
        let svg = InverterStationDrawing.sketch(s).svg()
        XCTAssertTrue(svg.contains("EXISTING WALL"))
        XCTAssertTrue(svg.contains("GROWATT MAX 60KTL3 LV"))
        XCTAssertTrue(svg.contains("TO INJECTION POINT · AC CABLE LADDER 200x100 (NON COVER)"))
        XCTAssertFalse(svg.contains("เกินพื้นที่"))
    }

    func testOutdoorDrawing() {
        let s = InverterStation(sizes: [60, 60], width: 2.5, length: 9.5)
        let sk = InverterStationDrawing.sketch(s)
        XCTAssertEqual(sk.width, 1470); XCTAssertEqual(sk.height, 752)
        let svg = sk.svg()
        XCTAssertTrue(svg.contains("AC PERFORATED TRAY 100x100 WITH COVER"))
        XCTAssertTrue(svg.contains("CABLE LADDER 200x100 (NON COVER) · 4×1C 120 + G25"))
        XCTAssertTrue(svg.contains(">1.48<"))
        XCTAssertTrue(svg.contains(">9.50<"))
        XCTAssertTrue(svg.contains("INVERTER No.2"))
        XCTAssertTrue(svg.contains("DC-DB-02"))
        // five grid bubbles for four spans (columns are squares)
        XCTAssertEqual(sk.ops.filter { if case let .circle(_, r, _, _, _) = $0 { return r == 20 }; return false }.count, 5)
    }

    /// Writes the three preview plans as SVG for a visual check against docs/ui/survey-b2/plan-*.png.
    func testSnapshotsWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b2-plans")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases: [(String, InverterStation)] = [
            ("outdoor", InverterStation(sizes: [60, 60], width: 2.5, length: 9.5)),
            ("indoor", InverterStation(sizes: [60, 60], width: 2.5, length: 9.5, site: .indoor)),
            ("overflow", InverterStation(sizes: [60, 60, 80], width: 2.5, length: 9.5)),
        ]
        for (name, s) in cases {
            let svg = InverterStationDrawing.sketch(s).svg()
            XCTAssertTrue(svg.hasPrefix("<svg"))
            try svg.write(to: dir.appendingPathComponent("plan-\(name).svg"), atomically: true, encoding: .utf8)
        }
    }
}

import XCTest
@testable import TCRoofCore

/// D1 wide page, sub-step 1 "ขนาดถัง" (docs/ui/survey-d1-size).
final class TankTests: XCTestCase {
    func testPresetsWriteExpandedSpans() {
        let expected: [(String, String, String, Double, Double)] = [
            ("40 × 40 ม.", "4,4,4,4,4,4,4,4,4,4", "4,4,4,4,4,4,4,4,4,4", 40, 40),
            ("64 × 40 ม.", "4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4", "4,4,4,4,4,4,4,4,4,4", 64, 40),
            ("30 × 30 ม.", "5,5,5,5,5,5", "5,5,5,5,5,5", 30, 30),
            ("20 × 20 ม.", "4,4,4,4,4", "4,4,4,4,4", 20, 20),
        ]
        XCTAssertEqual(Tank.presets.map(\.name), expected.map(\.0))
        for (p, e) in zip(Tank.presets, expected) {
            var v = Values()
            Tank.apply(&v, p)
            XCTAssertEqual(v.text("spansX"), e.1)
            XCTAssertEqual(v.text("spansY"), e.2)
            XCTAssertEqual(parseSpans(v.text("spansX")).reduce(0, +), e.3)
            XCTAssertEqual(parseSpans(v.text("spansY")).reduce(0, +), e.4)
            XCTAssertEqual(Tank.preset(v), p)
            XCTAssertEqual(Tank.sizeLabel(v)?.name, p.name)
            XCTAssertEqual(Tank.sizeLabel(v)?.sub, p.sub)
        }
    }

    func testPresetDetection() {
        // exact spans written by hand still match
        var v = Values(["spansX": .text("5, 5, 5, 5, 5, 5"), "spansY": .text("5/5/5/5/5/5")])
        XCTAssertEqual(Tank.preset(v)?.name, "30 × 30 ม.")
        // the same total with other spans is custom
        v = Values(["spansX": .text("8,8,8,8,8"), "spansY": .text("4,4,4,4,4,4,4,4,4,4")])
        XCTAssertNil(Tank.preset(v))
        XCTAssertEqual(Tank.sizeLabel(v)?.name, "40 × 40 ม.")
        XCTAssertEqual(Tank.sizeLabel(v)?.sub, "กำหนดเอง")
        v = Values(["spansX": .text("4.5,4.5"), "spansY": .text("3")])
        XCTAssertEqual(Tank.sizeLabel(v)?.name, "9 × 3 ม.")
        // empty spans: the placeholder
        XCTAssertNil(Tank.sizeLabel(Values()))
        XCTAssertNil(Tank.sizeLabel(Values(["spansX": .text("4,4")])))
    }

    func testPositionDrivesExposedPart() {
        var v = Values()
        Tank.setHeight(&v, 4.5)
        Tank.setPosition(&v, "กึ่งฝัง")
        XCTAssertEqual(v.text("tankExposed"), "1.2")
        XCTAssertTrue(Tank.exposedEditable(v))
        Tank.setExposed(&v, 2.3)
        XCTAssertEqual(Tank.exposed(v), 2.3)
        // clamped to 0…height
        Tank.setExposed(&v, 9)
        XCTAssertEqual(Tank.exposed(v), 4.5)
        Tank.setExposed(&v, -1)
        XCTAssertEqual(Tank.exposed(v), 0)
        Tank.setExposed(&v, 2.3)

        Tank.setPosition(&v, "บนดิน")
        XCTAssertEqual(v.choice("tankPos"), "บนดิน")
        XCTAssertEqual(v.text("tankExposed"), "4.5")
        XCTAssertFalse(Tank.exposedEditable(v))
        Tank.setExposed(&v, 1)
        XCTAssertEqual(Tank.exposed(v), 4.5)
        Tank.setHeight(&v, 5)
        XCTAssertEqual(v.text("tankExposed"), "5")

        Tank.setPosition(&v, "ฝังดิน")
        XCTAssertEqual(v.text("tankExposed"), "0")
        Tank.setHeight(&v, 3)
        XCTAssertEqual(v.text("tankExposed"), "0")

        // back to partly buried: the default again, within the height
        Tank.setPosition(&v, "กึ่งฝัง")
        XCTAssertEqual(Tank.exposed(v), 1.2)
        // the height drops below the exposed part: re-clamped
        Tank.setExposed(&v, 2.8)
        Tank.setHeight(&v, 2)
        XCTAssertEqual(Tank.exposed(v), 2)
        XCTAssertEqual(v.text("tankHeight"), "2")
        // the height has a minimum of 1.00
        Tank.setHeight(&v, 0.4)
        XCTAssertEqual(Tank.height(v), 1)
        XCTAssertEqual(Tank.exposed(v), 1)
        // soil cover: never below 0, rounded to cm
        Tank.setSoil(&v, -0.05)
        XCTAssertEqual(v.text("soilDepth"), "0")
        Tank.setSoil(&v, 0.6000001)
        XCTAssertEqual(v.text("soilDepth"), "0.6")
    }

    func testAzimuthFromWallHeading() {
        XCTAssertEqual(Tank.azimuth(wall: 104), 14)
        XCTAssertEqual(Tank.azimuth(wall: 30), 300)
        XCTAssertEqual(Tank.azimuth(wall: 90), 0)
        XCTAssertEqual(Tank.azimuth(wall: 0), 270)
        XCTAssertEqual(Tank.azimuth(wall: 359.6), 270)
        XCTAssertEqual(Tank.directionName(12), "เหนือ")
        XCTAssertEqual(Tank.directionName(23), "ตะวันออกเฉียงเหนือ")
        XCTAssertEqual(Tank.directionName(90), "ตะวันออก")
        XCTAssertEqual(Tank.directionName(135), "ตะวันออกเฉียงใต้")
        XCTAssertEqual(Tank.directionName(180), "ใต้")
        XCTAssertEqual(Tank.directionName(225), "ตะวันตกเฉียงใต้")
        XCTAssertEqual(Tank.directionName(270), "ตะวันตก")
        XCTAssertEqual(Tank.directionName(300), "ตะวันตกเฉียงเหนือ")
        XCTAssertEqual(Tank.directionName(350), "เหนือ")
        XCTAssertEqual(Tank.azimuthText(14), "14° เหนือ")
    }

    func testAzimuthSourceLine() {
        var v = Values()
        XCTAssertNil(Tank.sourceLine(v))
        Tank.setAzimuth(&v, 372, source: .manual)
        XCTAssertEqual(Tank.azimuth(v), 12)
        XCTAssertEqual(Tank.sourceLine(v), "ป้อนเอง · แปลนและลูกศร N หมุนตามค่านี้")
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 30; c.hour = 16; c.minute = 55
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        Tank.setAzimuth(&v, 14, source: .compass, at: cal.date(from: c)!, accuracy: 3.4)
        XCTAssertEqual(v.text("tankAzimuthSrc"), "compass")
        XCTAssertEqual(Tank.sourceLine(v, timeZone: cal.timeZone), "วัดด้วยเข็มทิศ iPad · ±3° · 30/9 16:55 · แปลนและลูกศร N หมุนตามค่านี้")
        XCTAssertEqual(Tank.sourceLine(v, timeZone: cal.timeZone, device: "iPhone", tail: "แปลนหมุนตามค่านี้"),
                       "วัดด้วยเข็มทิศ iPhone · ±3° · 30/9 16:55 · แปลนหมุนตามค่านี้")
        Tank.setAzimuth(&v, nil, source: .manual)
        XCTAssertNil(v["tankAzimuth"]); XCTAssertNil(v["tankAzimuthAt"]); XCTAssertNil(v["tankAzimuthSrc"])
    }

    func testOldTankDecodesAndCountsAsBefore() throws {
        // a tank saved before the D1 page: no tankExposed / tankAzimuth, a surface not in the list
        let json = #"""
        {"id":"6F1C3B8E-1D0A-4B8C-9E61-0D7A0D9E1A11","type":"tank","name":"1",
         "values":{"storage":{"spansX":{"text":{"_0":"4,4,4,4"}},"spansY":{"text":{"_0":"4,4,4,4"}},
           "tankType":{"choice":{"_0":"ค.ส.ล.","other":""}},"tankPos":{"choice":{"_0":"บนดิน","other":""}},
           "tankHeight":{"text":{"_0":"4.5"}},"surface":{"text":{"_0":"กระเบื้องยาง"}},"panelsBefore":{"text":{"_0":"300"}}}}}
        """#
        let old = try JSONDecoder().decode(SurveyModule.self, from: Data(json.utf8))
        XCTAssertEqual(old.type, .tank)
        XCTAssertEqual(old.values.text("surface"), "กระเบื้องยาง")
        XCTAssertNil(Tank.preset(old.values))
        XCTAssertEqual(Tank.sizeLabel(old.values)?.name, "16 × 16 ม.")
        XCTAssertTrue(Tank.sizeDone(old.values))
        XCTAssertNil(Tank.azimuth(old.values))
        let before = old.completion
        // 11, plus the roof and cable photos required since 2026-10-19
        XCTAssertEqual(before.total, 13)
        // the new fields are optional and hidden: filling them changes nothing in the count
        var m = old
        Tank.syncExposed(&m.values)
        Tank.setAzimuth(&m.values, 14, source: .compass, accuracy: 3)
        XCTAssertEqual(m.values.text("tankExposed"), "4.5")
        XCTAssertEqual(m.completion, before)
        // round trip
        let back = try JSONDecoder().decode(SurveyModule.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
    }

    func testStepDoneNeedsTypeHeightPositionSurfaceAndSize() {
        var v = Values()
        Tank.apply(&v, Tank.presets[0])
        XCTAssertFalse(Tank.sizeDone(v))
        v["tankType"] = .choice("ค.ส.ล.", other: "")
        Tank.setHeight(&v, 4.5)
        Tank.setPosition(&v, "กึ่งฝัง")
        XCTAssertFalse(Tank.sizeDone(v))
        v["surface"] = .text("คอนกรีต")
        XCTAssertTrue(Tank.sizeDone(v))
        // อื่นๆ needs its text
        v["tankType"] = .choice("อื่นๆ", other: "")
        XCTAssertFalse(Tank.sizeDone(v))
        v["tankType"] = .choice("อื่นๆ", other: "ไฟเบอร์")
        XCTAssertTrue(Tank.sizeDone(v))
    }

    func testPlanDrawsGridChainsArrowAndTags() throws {
        var v = Values()
        Tank.apply(&v, Tank.presets[1])
        v["tankType"] = .choice("ค.ส.ล.", other: "")
        let texts: (Sketch) -> [String] = { s in s.ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { return t }; return nil } }
        var sk = try XCTUnwrap(Drawings.plan(v, tank: true))
        var t = texts(sk)
        XCTAssertTrue(t.contains("1") && t.contains("17") && t.contains("A") && t.contains("K") && !t.contains("L"))
        XCTAssertEqual(t.filter { $0 == "4.00" }.count, 26)
        XCTAssertTrue(t.contains("64.00") && t.contains("40.00"))
        XCTAssertTrue(t.contains("แปลนหลังคาถังน้ำใส 64 × 40 ม."))
        XCTAssertTrue(t.contains("ผนัง ค.ส.ล."))
        XCTAssertFalse(t.contains("N"))
        XCTAssertFalse(t.contains { $0.hasPrefix("ระดับหลังถัง") })
        // the whole plan fits the sketch
        for op in sk.ops { if case let .circle(c, r, _, _, _) = op { XCTAssertTrue(c.x - r >= 0 && c.x + r <= sk.width && c.y - r >= 0) } }

        Tank.setHeight(&v, 4.5); Tank.setPosition(&v, "กึ่งฝัง")
        Tank.setAzimuth(&v, 90, source: .manual)
        sk = try XCTUnwrap(Drawings.plan(v, tank: true))
        t = texts(sk)
        XCTAssertEqual(t.filter { $0 == "ระดับหลังถัง +1.20" }.count, 4)
        // N turned by −90°: left of the arrow's centre
        let arrow = TankPlan.northArrow(at: Pt(0, 0), azimuth: 90)
        if case let .text(n, at, _, _, _, _, _) = arrow[2] { XCTAssertEqual(n, "N"); XCTAssertLessThan(at.x, -16); XCTAssertEqual(at.y, 0, accuracy: 0.001) }
        else { XCTFail() }
        XCTAssertTrue(t.contains("N"))

        // the page draws the span numbers itself
        let plan = try XCTUnwrap(TankPlan(v, chips: true, hints: true))
        XCTAssertEqual(plan.chips.count, 26)
        XCTAssertFalse(texts(plan.sketch).contains("4.00"))
        XCTAssertTrue(texts(plan.sketch).contains("ผนัง ค.ส.ล. · สิ่งกีดขวางระบุในขั้นที่ 2"))
        XCTAssertNil(TankPlan(Values()))
    }

    func testCompactPlan() throws {
        var v = Values()
        XCTAssertNil(TankPlan.compact(v))
        Tank.apply(&v, Tank.presets[0])
        let sketch = try XCTUnwrap(TankPlan.compact(v))
        XCTAssertEqual(sketch.width, 330); XCTAssertEqual(sketch.height, 300)
        let texts = sketch.ops.compactMap { op -> String? in if case let .text(t, _, _, _, _, _, _) = op { return t }; return nil }
        // grid names 1…11 and A…K, the two totals, no single spans; no arrow without an azimuth
        XCTAssertEqual(texts.filter { $0 == "40.00" }.count, 2)
        XCTAssertTrue(texts.contains("11")); XCTAssertTrue(texts.contains("K"))
        XCTAssertFalse(texts.contains("4.00")); XCTAssertFalse(texts.contains("N"))
        Tank.setAzimuth(&v, 12, source: .manual)
        XCTAssertTrue(try XCTUnwrap(TankPlan.compact(v)).ops.contains { if case .text("N", _, _, _, _, _, _) = $0 { return true }; return false })
    }

    func testPhotoStatus() {
        var v = Values()
        // aerial, walls, roof (both photos), cable route, obstacles
        XCTAssertEqual(Tank.photoCompletion(v), Completion(filled: 0, total: 5))
        XCTAssertEqual(Tank.statusLine(v), "ยังขาดภาพบังคับ 5 ภาพ")
        v["aerialPhoto"] = .photo(Photo(fileName: "a.jpg", width: 4, height: 3))
        XCTAssertEqual(Tank.statusLine(v), "ยังขาดภาพบังคับ 4 ภาพ")
        // the roof needs its overview and its surface
        v[Tank.Key.roofPhotos] = .photos([Photo(fileName: "r.jpg", width: 4, height: 3)])
        XCTAssertEqual(Tank.statusLine(v), "ยังขาดภาพบังคับ 4 ภาพ")
        v[Tank.Key.roofPhotos] = .photos([Photo(fileName: "r.jpg", width: 4, height: 3), Photo(fileName: "s.jpg", width: 4, height: 3)])
        XCTAssertEqual(Tank.statusLine(v), "ยังขาดภาพบังคับ 3 ภาพ")
    }

    // MARK: compass lock (states/08)

    func testHeadingLocksAfterTwoStableSeconds() {
        var lock = HeadingLock()
        let t0 = Date(timeIntervalSince1970: 0)
        // 1.9 s of steady readings: not yet
        for i in 0..<20 { XCTAssertNil(lock.add(104 + (i % 2 == 0 ? 0.8 : -0.8), at: t0 + Double(i) * 0.1)) }
        // 2 s reached: locked at the mean, and the azimuth follows
        let wall = try? XCTUnwrap(lock.add(104, at: t0 + 2.0))
        XCTAssertEqual(wall ?? 0, 104, accuracy: 0.2)
        XCTAssertEqual(Tank.azimuth(wall: wall ?? 0), 14)
        // a locked value holds while the hand moves to tap บันทึกมุม
        XCTAssertEqual(lock.add(140, at: t0 + 2.1) ?? 0, 104, accuracy: 0.2)
        lock.reset()
        XCTAssertNil(lock.locked)
    }

    func testHeadingDoesNotLockWhileMoving() {
        var lock = HeadingLock()
        let t0 = Date(timeIntervalSince1970: 0)
        // swinging ±3°: never locks
        for i in 0..<40 { XCTAssertNil(lock.add(100 + (i % 2 == 0 ? 3 : -3), at: t0 + Double(i) * 0.1)) }
        // one jump restarts the 2 s: the window must be stable end to end
        lock.reset()
        for i in 0..<15 { lock.add(50, at: t0 + Double(i) * 0.1) }
        lock.add(80, at: t0 + 1.5)
        for i in 16..<30 { lock.add(50, at: t0 + Double(i) * 0.1) }
        XCTAssertNil(lock.locked)
        XCTAssertEqual(lock.add(50, at: t0 + 3.8) ?? 0, 50, accuracy: 0.01)
    }

    func testHeadingLockAcrossNorth() {
        // readings either side of 0°/360° average to north, not south
        XCTAssertEqual(HeadingLock.mean([359, 1]), 0, accuracy: 0.001)
        XCTAssertEqual(HeadingLock.mean([358, 359, 1, 2]), 0, accuracy: 0.001)
        XCTAssertEqual(HeadingLock.diff(359, 1), 2, accuracy: 0.001)
        XCTAssertEqual(HeadingLock.diff(10, 190), 180, accuracy: 0.001)
        var lock = HeadingLock()
        let t0 = Date(timeIntervalSince1970: 0)
        for i in 0...20 { lock.add(i % 2 == 0 ? 359.5 : 0.5, at: t0 + Double(i) * 0.1) }
        let wall = try? XCTUnwrap(lock.locked)
        // 11 readings at 359.5 and 10 at 0.5: just west of north
        XCTAssertEqual(HeadingLock.diff(wall ?? 180, 0), 0, accuracy: 0.05)
        XCTAssertEqual(Tank.azimuth(wall: wall ?? 0), 270)
    }

    func testAccuracyGatesSaving() {
        XCTAssertTrue(HeadingLock.accuracyOK(3))
        XCTAssertTrue(HeadingLock.accuracyOK(10))
        XCTAssertFalse(HeadingLock.accuracyOK(10.5))
        XCTAssertFalse(HeadingLock.accuracyOK(-1))
        XCTAssertFalse(HeadingLock.accuracyOK(nil))
    }

    // MARK: device checklist rules

    func testCustomSpansStayUntilAPresetIsPicked() {
        var v = Values(["spansX": .text("6,6,6.5"), "spansY": .text("5,5")])
        Tank.setHeight(&v, 4); Tank.setPosition(&v, Tank.partly); v["tankType"] = .choice("เหล็ก", other: "")
        XCTAssertEqual(v.text("spansX"), "6,6,6.5")
        XCTAssertEqual(Tank.sizeLabel(v)?.name, "18.5 × 10 ม.")
        Tank.apply(&v, Tank.presets[3])
        XCTAssertEqual(Tank.sizeLabel(v)?.name, "20 × 20 ม.")
        // editing one span afterwards turns it custom (the span editor writes through Roof.setSpans)
        var x = Tank.spans(v).x; x[0] = 4.5
        Roof.setSpans(&v, .x, x)
        XCTAssertEqual(Tank.sizeLabel(v)?.name, "20.5 × 20 ม.")
        XCTAssertEqual(Tank.sizeLabel(v)?.sub, "กำหนดเอง")
    }

    func testOtherTypeAndSurfaceText() {
        var v = Values(["tankType": .choice("อื่นๆ", other: " ไฟเบอร์กลาส ")])
        XCTAssertEqual(Tank.typeName(v), "ไฟเบอร์กลาส")
        Tank.apply(&v, Tank.presets[0])
        let note = TankPlan(v, hints: false).map { p in p.sketch.ops.compactMap { op -> String? in if case let .text(t, _, _, _, _, _, _) = op { return t }; return nil } } ?? []
        XCTAssertTrue(note.contains("ผนัง ไฟเบอร์กลาส"))
        v["tankType"] = nil
        let none = TankPlan(v)!.sketch.ops.compactMap { op -> String? in if case let .text(t, _, _, _, _, _, _) = op { return t }; return nil }
        XCTAssertFalse(none.contains { $0.hasPrefix("ผนัง") })
        // any surface text is kept as is
        v["surface"] = .text("แผ่นยางกันซึม")
        XCTAssertFalse(Tank.surfaces.contains(v.text("surface")))
        XCTAssertEqual(v.text("surface"), "แผ่นยางกันซึม")
    }

    func testOldPositionWithoutExposedHidesLevelTags() {
        // an old job: partly buried, no tankExposed yet
        var v = Values(["tankPos": .choice("กึ่งฝัง", other: ""), "tankHeight": .text("4.5")])
        Tank.apply(&v, Tank.presets[0])
        XCTAssertNil(Tank.exposed(v))
        let texts = TankPlan(v)!.sketch.ops.compactMap { op -> String? in if case let .text(t, _, _, _, _, _, _) = op { return t }; return nil }
        XCTAssertFalse(texts.contains { $0.hasPrefix("ระดับหลังถัง") })
        // the first + on ส่วนพ้นดิน starts at 0 and stays in range
        Tank.setExposed(&v, 0.1)
        XCTAssertEqual(Tank.exposed(v), 0.1)
    }

    func testManualAzimuthIsNormalised() {
        var v = Values()
        Tank.setAzimuth(&v, -10, source: .manual)
        XCTAssertEqual(Tank.azimuth(v), 350)
        XCTAssertEqual(Tank.directionName(350), "เหนือ")
        XCTAssertNil(v["tankAzimuthAt"]); XCTAssertNil(v["tankAzimuthAcc"])
        // a typed value in the stored field (old or hand-edited JSON)
        v["tankAzimuth"] = .text("90.4")
        XCTAssertEqual(Tank.azimuth(v), 90)
    }
}

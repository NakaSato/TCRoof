import XCTest
@testable import TCRoofCore

/// C1 roof page (docs/ui/survey-c1): spans, ridge ↔ sheetDir, members, shapes, photo angles, posts, PV preview,
/// old jobs and completion unchanged.
final class RoofTests: XCTestCase {
    static let photo = Photo(fileName: "p.jpg", width: 400, height: 300)
    static let photos = (0...3).map { Photo(fileName: "p\($0).jpg", width: 400, height: 300) }
    func photo(_ n: Int) -> Photo { Self.photos[n] }

    func testOldRoofJSONDecodes() throws {
        // a roof saved before C1: obstacles without kind / canCover, free-text member and shape
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","type":"roof","name":"1 โรงกรอง","values":{"storage":{
          "spansX":{"text":{"_0":"1.5,4,4"}},"sheetDir":{"choice":{"_0":"แนวตั้ง","other":""}},
          "comp2":{"text":{"_0":"ไม้เนื้อแข็ง 2x6 ตามเดิม"}},"roofShape":{"choice":{"_0":"อื่นๆ","other":"ทรงมะนิลา"}},
          "obst":{"obstacles":{"_0":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","label":"ปล่อง","x":"1","y":"2","w":"1","h":"1"}]}}}}}
        """
        let m = try JSONDecoder().decode(SurveyModule.self, from: Data(json.utf8))
        let v = m.values
        XCTAssertEqual(v.obstacles("obst").first?.kind, "")
        XCTAssertEqual(v.obstacles("obst").first?.canCover, false)
        XCTAssertEqual(Roof.member(v, 2), "ไม้เนื้อแข็ง 2x6 ตามเดิม")
        XCTAssertEqual(Roof.shown(v, "roofShape", in: Roof.shapes), "ทรงมะนิลา")
        XCTAssertFalse(Roof.hasFrame(v))
        XCTAssertEqual(Roof.frame(v), .pratt)
        XCTAssertEqual(Roof.ridge(v), .h)
        XCTAssertTrue(Roof.memberOffList(v, 2))
        // the new obstacle fields round-trip
        var w = v
        Roof.addArea(&w, kind: Roof.skylightKind, x1: 2, y1: 1, x2: 2.8, y2: 5)
        Roof.toggleCover(&w, index: 1)
        let back = try JobStore.decoder.decode(Values.self, from: JobStore.encoder.encode(w))
        XCTAssertEqual(back.obstacles("obst")[1].kind, "sky")
        XCTAssertTrue(back.obstacles("obst")[1].canCover)
    }

    func testSpansRoundTripToCommaString() {
        var v = Values()
        XCTAssertEqual(Roof.spans(v, .x), [1.5, 4, 4, 4, 4, 1.5], "placeholder when empty")
        v["spansX"] = .text("1.5, 4,4.5")
        var s = Roof.spans(v, .x)
        s.insert(contentsOf: [s[1] / 2, s[1] / 2], at: 1); s.remove(at: 3)
        Roof.setSpans(&v, .x, s)
        XCTAssertEqual(v.text("spansX"), "1.5,2,2,4.5")
        Roof.setSpans(&v, .y, Array(repeating: 16.0 / 3, count: 3))
        XCTAssertEqual(v.text("spansY"), "5.333,5.333,5.333")
        XCTAssertEqual(parseSpans(v.text("spansY")).count, 3)
        Roof.setSpans(&v, .y, [])
        XCTAssertNil(v["spansY"])
        XCTAssertEqual(Roof.spanName(.x, 2), "3-4")
        XCTAssertEqual(Roof.spanName(.y, 1), "B-C")
    }

    func testRidgeAndSheetDir() {
        var v = Values()
        // nothing stored: the old plan draws ribs along x, so the ridge runs along y
        XCTAssertEqual(Roof.ridge(v), .v)
        v["sheetDir"] = .choice("แนวตั้ง", other: "")
        XCTAssertEqual(Roof.ridge(v), .h)
        Roof.setRidge(&v, .v)
        XCTAssertEqual(v.choice("sheetDir"), "แนวนอน")
        XCTAssertEqual(Roof.ridge(v), .v)
        Roof.setRidge(&v, .h)
        XCTAssertEqual(v.choice("sheetDir"), "แนวตั้ง")
        XCTAssertEqual(v.text("ridgeDir"), "h")
    }

    func testMembersStayInTheirSlots() {
        var v = Values()
        Roof.setFrame(&v, .pratt)
        XCTAssertEqual(RoofFrame.pratt.members.map(\.name), ["แป", "คอร์ดบน", "คอร์ดล่าง", "ตัวตั้ง", "ตัวทแยง", "เชิงชาย", "เสากลาง"])
        XCTAssertEqual(RoofFrame.rafterTie.members.map(\.name), ["แป", "จันทัน", "ขื่อรัด", "อเส", "ตัวค้ำ", "เชิงชาย", "เสากลาง"])
        XCTAssertEqual(RoofFrame.rafterTruss.members.map(\.name), ["แป", "คอร์ดบน", "คอร์ดล่าง", "ตัวทแยง", "T2 รับจันทัน", "เชิงชาย", "เสา"])
        XCTAssertEqual(RoofFrame.pratt.members[0].defaultSize, "C-100x50x20x3.2")
        XCTAssertEqual(RoofFrame.rafterTie.members[4].defaultSize, "-")
        XCTAssertTrue(RoofFrame.allCases.allSatisfy { $0.members.count == 7 && $0.members.allSatisfy { $0.sizes.first == "-" } })
        // row 3 (คอร์ดล่าง on Pratt) is stored in comp3, the schema's อเส slot
        Roof.setMember(&v, 3, size: "2C-150x50x20x3.2")
        XCTAssertEqual(v.text("comp3"), "2C-150x50x20x3.2")
        Roof.setMember(&v, 1, size: "C-100x50x20x3.2")
        XCTAssertEqual(v.text("comp1"), "C-100x50x20x3.2 @1.00M", "purlins get the usual spacing")
        Roof.setSpacing(&v, 1, spacing: "@1.20M")
        Roof.setMember(&v, 1, size: "C-125x50x20x3.2")
        XCTAssertEqual(v.text("comp1"), "C-125x50x20x3.2 @1.20M", "a new size keeps the spacing")
        Roof.setMember(&v, 5, size: "-")
        XCTAssertEqual(v.text("comp5"), "-")
        // a frame change keeps the stored value and only marks it
        Roof.setFrame(&v, .rafterTruss)
        XCTAssertEqual(v.text("comp3"), "2C-150x50x20x3.2")
        XCTAssertTrue(Roof.memberOffList(v, 3))
        XCTAssertEqual(Roof.profile("2C-150x50x20x3.2"), "2C")
        XCTAssertEqual(Roof.profile("ท่อกลม Ø1\" หนา 1.6"), "tube")
        XCTAssertEqual(Roof.profile("ค.ส.ล 0.20x0.40"), "rc")
        XCTAssertEqual(Roof.profile("H-150x150x7x10"), "other")
    }

    func testShapeAndMaterialMapToExistingChoices() {
        var v = Values()
        for o in Roof.shapes { if let s = o.stored { XCTAssertTrue(Options.roofShape.contains(s), s) } }
        for o in Roof.materials { if let s = o.stored { XCTAssertTrue(Options.roofMaterial.contains(s), s) } }
        Roof.choose(&v, "roofShape", Roof.shapes[3])
        XCTAssertEqual(v.choice("roofShape"), "อื่นๆ")
        XCTAssertEqual(v.other("roofShape"), "ทรงฟันเลื่อย")
        XCTAssertEqual(Roof.shown(v, "roofShape", in: Roof.shapes), "ทรงฟันเลื่อย")
        Roof.choose(&v, "roofMaterial", Roof.materials[3])
        XCTAssertEqual(v.choice("roofMaterial"), "กระเบื้องซีแพค")
        XCTAssertEqual(Roof.option(v, "roofMaterial", in: Roof.materials)?.name, "กระเบื้องคอนกรีต")
        v["roofMaterial"] = .choice("กระเบื้องลอนคู่/เดี่ยว", other: "")
        XCTAssertEqual(Roof.shown(v, "roofMaterial", in: Roof.materials), "กระเบื้องลอนคู่")
    }

    func testPhotoAnglesKeepTheirSlots() {
        var v = Values()
        XCTAssertEqual(Roof.missingShots(v).count, 6)
        Roof.setPhoto(&v, .side, photo(1))
        Roof.setPhoto(&v, .front, photo(2))
        Roof.setPhoto(&v, .joint, photo(3))
        XCTAssertEqual(v.photos("generalPhotos"), [photo(1), photo(2)])
        XCTAssertEqual(Roof.photo(v, .front), photo(2))
        XCTAssertEqual(Roof.photo(v, .joint), photo(3))
        XCTAssertNil(Roof.photo(v, .frame))
        Roof.setPhoto(&v, .side, nil)
        XCTAssertEqual(Roof.photo(v, .front), photo(2), "deleting one doesn't move the others")
        XCTAssertNil(Roof.photo(v, .side))
        XCTAssertEqual(Roof.statusLine(v), "ยังขาดภาพหลังคา: มุมสูง ภาพรวม · ด้านข้าง · ใต้หลังคา โครง · แผ่นมุง ระยะใกล้")
        // old photos without angles fill the slots in order; extra structure photos are kept
        var old = Values()
        old["structPhotos"] = .photos([photo(1), photo(2), photo(3)])
        XCTAssertEqual(Roof.photo(old, .frame), photo(1))
        XCTAssertEqual(Roof.photo(old, .joint), photo(2))
        XCTAssertEqual(Roof.extraStructPhotos(old), 1)
        Roof.setPhoto(&old, .frame, nil)
        XCTAssertEqual(old.photos("structPhotos"), [photo(2), photo(3)])
        XCTAssertEqual(Roof.photo(old, .joint), photo(2))
        XCTAssertNil(Roof.photo(old, .frame))
    }

    func testPostEdits() {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        // Pratt: posts on the inner x lines at the eave lines B and E
        XCTAssertEqual(Roof.posts(v).count, 10)
        XCTAssertTrue(Roof.posts(v).contains("1,1"))
        Roof.togglePost(&v, i: 1, j: 1)
        XCTAssertFalse(Roof.posts(v).contains("1,1"))
        Roof.togglePost(&v, i: 3, j: 2)
        XCTAssertEqual(Roof.posts(v).count, 10)
        Roof.togglePost(&v, i: 1, j: 1); Roof.togglePost(&v, i: 3, j: 2)
        XCTAssertNil(v["postGrid"], "back to the defaults stores nothing")
        Roof.setFrame(&v, .rafterTruss)
        XCTAssertEqual(Roof.posts(v).count, 5 * 4)
    }

    /// The design's default roof: 19 × 16 m, Pratt, ridge along x, portrait 2278 × 1134 modules and one no-cover
    /// skylight (the design's first, 0.8 m wide at 36 % along the ridge) → 84 modules.
    func testPVCountMatchesDesign() {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        let module = RoofPlan.Module(length: 2.278, width: 1.134, kW: 0.57)
        XCTAssertEqual(RoofPlan.pvCount(v, module: module), 90)
        let a = 19 * 0.36
        v["obst"] = .obstacles([Obstacle(x: fmt(a - 0.4), y: "1", w: "0.8", h: "6.6", kind: "sky"),
                                Obstacle(x: fmt(19 * 0.64 - 0.4), y: "8.4", w: "0.8", h: "6.6", kind: "sky", canCover: true)])
        XCTAssertEqual(RoofPlan.pvCount(v, module: module), 84)
        XCTAssertEqual(RoofPlan(v, mode: .pv, module: module).pv.kWp, 84 * 0.57, accuracy: 0.001)
        // a keep-out zone blocks more; landscape packs differently
        Roof.addArea(&v, kind: Roof.keepOutKind, x1: 14, y1: 9, x2: 18, y2: 12)
        XCTAssertLessThan(RoofPlan.pvCount(v, module: module), 84)
        XCTAssertNotEqual(RoofPlan.pvCount(v, portrait: false, module: module), RoofPlan.pvCount(v, module: module))
        // keep-out zones only show in the PV mode
        XCTAssertFalse(RoofPlan(v).layout.areas.contains { $0.area.kind == Roof.keepOutKind })
    }

    func testCompletionUnchanged() {
        var m = SurveyModule(type: .roof)
        let before = m.completion
        Roof.setFrame(&m.values, .warren); Roof.setRidge(&m.values, .v); Roof.setBays(&m.values, 9)
        Roof.togglePost(&m.values, i: 0, j: 0)
        Roof.setLength(&m.values, Roof.Key.overhang, 0.9)
        m.values["pvOrientation"] = .text("l")
        let after = m.completion
        // sheetDir is optional, so only the hidden fields and it changed: the counts stay the same
        XCTAssertEqual(before.filled, after.filled)
        XCTAssertEqual(before.total, after.total)
        Roof.setPhoto(&m.values, .front, Self.photo)
        XCTAssertEqual(m.completion.total, before.total)
    }

    func testSectionAndPlanDraw() throws {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h)
        for f in RoofFrame.allCases {
            Roof.setFrame(&v, f)
            let s = RoofSection(v)
            XCTAssertEqual(s.span, 16)
            XCTAssertEqual(s.bays, 8)
            XCTAssertEqual(s.rise, 8 * tan(f.slope * .pi / 180), accuracy: 1e-9)
            XCTAssertFalse(s.sketch.ops.isEmpty)
            let p = RoofPlan(v, chips: true)
            XCTAssertEqual(p.layout.chips.count, 11)
            XCTAssertEqual(p.layout.nodes.count, 7 * 6)
            if let dir = ProcessInfo.processInfo.environment["ROOF_SVG_DIR"] {
                try s.sketch.svg().write(toFile: "\(dir)/section-\(f.rawValue).svg", atomically: true, encoding: .utf8)
                try RoofPlan(v).sketch.svg().write(toFile: "\(dir)/plan-\(f.rawValue).svg", atomically: true, encoding: .utf8)
                try RoofPlan(v, mode: .pv).sketch.svg().write(toFile: "\(dir)/pv-\(f.rawValue).svg", atomically: true, encoding: .utf8)
            }
        }
        Roof.setBays(&v, 12)
        XCTAssertEqual(RoofSection(v).bays, 12)
        XCTAssertFalse(Roof.baysAreAuto(v))
        Roof.setBays(&v, nil)
        XCTAssertTrue(Roof.baysAreAuto(v))
    }

    // MARK: second hand-off (docs/ui/survey-c1, CLAUDE_CODE_TASK.md)

    func testPurlinSpacing() {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        XCTAssertEqual(Roof.purlinSpacing(v), 1.0)
        // 16 m across the ridge, 15°: 0.15 m off the ridge, then every cos 15° = 0.966 m; 9 lines a side
        let lines = Roof.purlinLines(v)
        XCTAssertEqual(lines.count, 18)
        XCTAssertEqual(lines[0], 7.85, accuracy: 1e-9)
        XCTAssertEqual(lines[2], 8 - 0.15 - cos(15 * .pi / 180), accuracy: 1e-9)
        XCTAssertEqual(Roof.purlinNote(v), "ข้างละ 9 แนว")
        Roof.setPurlinSpacing(&v, 0.4)
        XCTAssertEqual(v.text("purlinSpacing"), "0.60", "clamped to 0.60–1.50")
        Roof.setPurlinSpacing(&v, 1.234)
        XCTAssertEqual(Roof.purlinSpacing(v), 1.23)
        XCTAssertLessThan(Roof.purlinLines(v).count, lines.count)
        Roof.setPurlinSpacing(&v, nil)
        XCTAssertNil(v["purlinSpacing"])
    }

    func testEaveCeilingFrame() {
        let k = RoofFrame.eaveCeiling
        XCTAssertEqual(RoofFrame.ordered.map(\.label), ["ปกติ", "ถัก Pratt", "ถัก Warren", "ขื่อรัด", "จันทันถัก", "ชายคาฝ้า"])
        XCTAssertEqual(k.members.map(\.name), ["แป", "จันทัน", "ขื่อรัด", "คานหัวเสา", "โครงฝ้า", "เชิงชาย", "เสา"])
        XCTAssertTrue(k.isRafter); XCTAssertFalse(k.isTruss)
        XCTAssertEqual(k.slope, 15); XCTAssertEqual(k.heel, 0)
        var v = Values()
        Roof.setFrame(&v, k)
        XCTAssertEqual(Roof.overhang(v), 1.2)
        Roof.setLength(&v, Roof.Key.overhang, 0.9)
        XCTAssertEqual(Roof.overhang(v), 0.9)
    }

    func testStandards() {
        var v = Values()
        XCTAssertEqual(Roof.standards.map { $0.title() }, ["โรงกรอง 19 × 16 ม.", "อาคารสูบน้ำ 12 × 8 ม.", "อาคารสำนักงาน 16 × 10 ม.",
                                                            "อาคารเก็บสารเคมี 24 × 12 ม.", "โรงจอดรถ 30 × 20 ม."])
        XCTAssertEqual(Roof.standards[0].subtitle, "ถัก Pratt · ช่วงเสา 4 ม. · 7 × 6 กริด")
        Roof.togglePost(&v, i: 0, j: 0)
        Roof.setFrame(&v, .rafterTie); Roof.togglePost(&v, i: 0, j: 0)
        Roof.applyStandard(&v, Roof.standards[1])
        XCTAssertEqual(v.text("spansX"), "4,4,4"); XCTAssertEqual(v.text("spansY"), "1,3,3,1")
        XCTAssertEqual(Roof.frame(v), .rafterTie)
        XCTAssertEqual(v.choice("roofShape"), "หลังคาทรงจั่ว")
        XCTAssertEqual(v.text("roofStd"), "pump")
        XCTAssertNil(Roof.postEdits(v)["c"], "the standard's frame goes back to its default posts")
        XCTAssertNotNil(Roof.postEdits(v)["p"], "other frames keep their edits")
        XCTAssertEqual(Roof.matchingStandard(v, in: Roof.standards)?.id, "pump")
        XCTAssertEqual(Roof.standardLabel(v, in: Roof.standards), "อาคารสูบน้ำ 12×8")
        // a saved roof matches its purlin spacing too
        Roof.setPurlinSpacing(&v, 0.9)
        let mine = Roof.standard(from: v, id: "t-1", name: "โรงสูบน้ำ (พิจิตร)", by: "วิชัย", scope: "ทั้งทีม", date: "28 ก.ย.")
        XCTAssertEqual(mine.title(), "โรงสูบน้ำ 12 × 8 ม. (พิจิตร)")
        XCTAssertEqual(mine.subtitle, "ขื่อรัด · แป @0.90 · โดย วิชัย · 28 ก.ย. · ทั้งทีม")
        XCTAssertEqual(Roof.matchingStandard(v, in: [mine])?.id, "t-1")
        Roof.setPurlinSpacing(&v, 1.0)
        XCTAssertNil(Roof.matchingStandard(v, in: [mine]))
        Roof.setSpans(&v, .x, [4, 4, 4.5])
        XCTAssertNil(Roof.matchingStandard(v, in: Roof.standards))
        XCTAssertEqual(Roof.standardLabel(v, in: Roof.standards), "กำหนดเอง 12.5×8 ม.")
        let back = try? JSONDecoder().decode(Roof.Standard.self, from: JSONEncoder().encode(mine))
        XCTAssertEqual(back, mine)
    }

    func testNewHiddenFieldsKeepCompletion() {
        var m = SurveyModule(type: .roof)
        let before = m.completion
        Roof.setPurlinSpacing(&m.values, 0.9)
        Roof.setPV(&m.values, rows: 2, perTable: 4, gap: 0.5)
        m.values["roofStd"] = .text("filter")
        XCTAssertEqual(m.completion.filled, before.filled)
        XCTAssertEqual(m.completion.total, before.total)
        XCTAssertEqual(Roof.pvRows(m.values), 2); XCTAssertEqual(Roof.pvPerTable(m.values), 4); XCTAssertEqual(Roof.pvGap(m.values), 0.5)
        Roof.setPV(&m.values, rows: 0, perTable: 0)
        XCTAssertNil(m.values["pvRows"]); XCTAssertNil(m.values["pvPerTable"])
    }
}

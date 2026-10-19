import XCTest
@testable import TCRoofCore

final class RemarkSuggestionsTests: XCTestCase {
    func tank(_ name: String = "1", shade: String? = "มี", from: [String] = ["ต้นไม้"], dirs: [String] = ["W"]) -> SurveyModule {
        var m = SurveyModule(type: .tank, name: name)
        if let shade { m.values["shade"] = .choice(shade, other: "") }
        m.values["shadeFrom"] = .multi(from)
        m.values["shadeDir"] = .multi(dirs)
        return m
    }

    func testNothingFiresOnAnEmptyJob() {
        XCTAssertTrue(RemarkSuggestions.make(job: Job()).isEmpty)
        XCTAssertTrue(RemarkSuggestions.make(job: Job.new(template: JobTemplate.all[0])).isEmpty)
    }

    func testShadeOnATank() throws {
        var j = Job()
        j.modules = [tank()]
        let s = try XCTUnwrap(RemarkSuggestions.make(job: j).first)
        XCTAssertEqual(s.text, "ตัดแต่งต้นไม้ด้านตะวันตก ถังน้ำใส 1 ก่อนติดตั้ง")
        XCTAssertEqual(s.source, "D1")
        XCTAssertEqual(s.target, .module(j.modules[0].id))

        // the names and sides come from the job
        j.modules = [tank("3 (ใหม่)", from: ["อาคาร"], dirs: ["S", "SW"])]
        XCTAssertEqual(RemarkSuggestions.make(job: j).first?.text, "ระวังเงาบังจากอาคารด้านใต้/ตะวันตกเฉียงใต้ ถังน้ำใส 3 (ใหม่) ก่อนจัดแผง")

        // no shade, or shade with nothing named, doesn't fire
        j.modules = [tank(shade: "ไม่มี"), tank(shade: nil), tank(from: [])]
        XCTAssertTrue(RemarkSuggestions.make(job: j).isEmpty)

        // two tanks are numbered D1.1, D1.2
        j.modules = [tank("1"), tank("2", dirs: [])]
        XCTAssertEqual(RemarkSuggestions.make(job: j).map(\.source), ["D1.1", "D1.2"])
        XCTAssertEqual(RemarkSuggestions.make(job: j)[1].text, "ตัดแต่งต้นไม้ ถังน้ำใส 2 ก่อนติดตั้ง")
    }

    /// With a stored layout and the object's height, D1's simulation decides: quoted from 1 %, left out below.
    func testShadeQuotesTheSimulation() throws {
        var j = Job()
        var m = tank(dirs: ["S"])
        Tank.apply(&m.values, Tank.presets[0])
        TankLayout.save(&m.values, TankLayout.auto(m.values), off: [])
        m.values[TankShade.Key.height] = .text("16"); m.values[TankShade.Key.distance] = .text("1")
        j.modules = [m]
        let s = try XCTUnwrap(RemarkSuggestions.make(job: j).first)
        XCTAssertTrue(s.text.hasPrefix("ตัดแต่งต้นไม้ด้านใต้ ถังน้ำใส 1"), s.text)
        XCTAssertTrue(s.text.contains("(เงาทำให้เสีย "), s.text)
        // trees lower than the panels cost nothing: no line
        j.modules[0].values[TankShade.Key.height] = .text("2")
        XCTAssertTrue(RemarkSuggestions.make(job: j).isEmpty)
    }

    func testFlood() {
        var j = Job()
        j.values["floodHistory"] = .choice("ไม่เคย", other: "")
        XCTAssertNil(RemarkSuggestions.flood(j))
        j.values["floodHistory"] = .choice("เคย", other: "")
        // flooded but no depth: no level, so no height
        XCTAssertNil(RemarkSuggestions.flood(j))
        j.values["floodDepth"] = .text("80")
        let s = RemarkSuggestions.flood(j)
        XCTAssertEqual(s?.text, "ยก SMDB-PV และรีเลย์กันย้อนสูง ≥ \(Schema.recommendedEquipHeight(j.values)!) ซม. (MDB1 เคยน้ำท่วม 80 ซม.)")
        XCTAssertEqual(s?.text, "ยก SMDB-PV และรีเลย์กันย้อนสูง ≥ 130 ซม. (MDB1 เคยน้ำท่วม 80 ซม.)")
        XCTAssertEqual(s?.source, "A4")
        XCTAssertEqual(s?.target, .flood)
        j.values["floodDepth"] = .text("35")
        XCTAssertEqual(RemarkSuggestions.flood(j)?.text, "ยก SMDB-PV และรีเลย์กันย้อนสูง ≥ 90 ซม. (MDB1 เคยน้ำท่วม 35 ซม.)")
    }

    func testElectricalGaps() {
        var j = Job()
        XCTAssertNil(RemarkSuggestions.electrical(j))
        var t = Transformer(kva: "630")
        var board = Board(name: "MDP-1", isMain: true, at: "800")
        board.icu = "50"
        board.breakers = [Breaker(at: "100", ic: "", target: "อาคารสำนักงาน")]
        t.setBoards([board])
        j.values["trafos"] = .transformers([t])
        let s = RemarkSuggestions.electrical(j)
        XCTAssertEqual(s?.text, "ขอค่า IC ของ CB1 อาคารสำนักงาน และ %Z ของ TX1 ก่อนออกแบบ")
        XCTAssertEqual(s?.source, "A3")

        t.impedance = "4"
        j.values["trafos"] = .transformers([t])
        XCTAssertEqual(RemarkSuggestions.electrical(j)?.text, "ขอค่า IC ของ CB1 อาคารสำนักงาน ก่อนออกแบบ")

        board.breakers[0].ic = "25"
        t.setBoards([board])
        j.values["trafos"] = .transformers([t])
        XCTAssertNil(RemarkSuggestions.electrical(j))
    }

    func testZeroExport() {
        var j = Job()
        j.values["capacity"] = .text("120")
        var a = SurveyModule(type: .panel, name: "โรงสูบน้ำ"); a.values["loadKW"] = .text("85")
        var b = SurveyModule(type: .panel, name: "โรงกรอง"); b.values["loadKW"] = .text("22")
        j.modules = [a, b]
        let s = RemarkSuggestions.zeroExport(j)
        XCTAssertEqual(s?.text, "ต้องมีระบบกันย้อน (โหลดกลางวัน 107 kW < PV 120 kW)")
        XCTAssertEqual(s?.source, "B1")
        XCTAssertEqual(s?.target, .module(a.id))
        // load above PV, or no PV size: no rule
        j.values["capacity"] = .text("100")
        XCTAssertNil(RemarkSuggestions.zeroExport(j))
        j.values["capacity"] = nil
        XCTAssertNil(RemarkSuggestions.zeroExport(j))
    }

    func testAddedIsReadFromTheRemarks() {
        let a = RemarkSuggestion(text: "ตัดแต่งต้นไม้ด้านตะวันตก ถังน้ำใส 1 ก่อนติดตั้ง", source: "D1", target: .final)
        let b = RemarkSuggestion(text: "ยก SMDB-PV และรีเลย์กันย้อนสูง ≥ 130 ซม.", source: "A4", target: .flood)
        var r = RemarkSuggestions.appending([a], to: "")
        XCTAssertEqual(r, "1. " + a.text)
        XCTAssertTrue(RemarkSuggestions.isAdded(a, in: r))
        XCTAssertEqual(RemarkSuggestions.pending([a, b], remarks: r), [b])

        r = RemarkSuggestions.appending([b], to: r)
        XCTAssertEqual(r, "1. \(a.text)\n2. \(b.text)")
        XCTAssertTrue(RemarkSuggestions.pending([a, b], remarks: r).isEmpty)

        // renumbering or a note after the text keeps it added
        XCTAssertTrue(RemarkSuggestions.isAdded(b, in: "5) \(b.text) ตามแบบ"))
        // editing a number in it, or deleting the line, offers it again
        XCTAssertFalse(RemarkSuggestions.isAdded(b, in: r.replacingOccurrences(of: "130", with: "150")))
        XCTAssertEqual(RemarkSuggestions.pending([a, b], remarks: "1. \(a.text)"), [b])
    }

    func testAppendingNumbersAfterExistingLines() {
        let s = RemarkSuggestion(text: "ต้องมีระบบกันย้อน", source: "B1", target: .final)
        XCTAssertEqual(RemarkSuggestions.appending([s], to: "ลูกค้าขอให้ติดตั้งก่อนสิ้นปี"), "ลูกค้าขอให้ติดตั้งก่อนสิ้นปี\n1. ต้องมีระบบกันย้อน")
        XCTAssertEqual(RemarkSuggestions.appending([s], to: "1. ก\n3. ข\n"), "1. ก\n3. ข\n4. ต้องมีระบบกันย้อน")
        let t = RemarkSuggestion(text: "ขอค่า IC", source: "A3", target: .final)
        XCTAssertEqual(RemarkSuggestions.appending([s, t], to: "2) ก"), "2) ก\n3. ต้องมีระบบกันย้อน\n4. ขอค่า IC")
    }

    func testFinalCompletionUnchanged() {
        var j = Job()
        XCTAssertEqual(j.finalCompletion.total, 4)
        XCTAssertEqual(j.finalCompletion.filled, 0)
        // remarks stay optional: adding suggestions doesn't count
        j.values["remarks"] = .text(RemarkSuggestions.appending([RemarkSuggestion(text: "ก", source: "A4", target: .flood)], to: ""))
        XCTAssertEqual(j.finalCompletion.filled, 0)
        j.values["verdict"] = .choice(Options.verdict[1], other: "")
        j.values["customerName"] = .text("ผู้ประสานงาน")
        j.values["surveyorSign"] = .photo(Photo(fileName: "s.png", width: 10, height: 10))
        j.values["customerSign"] = .photo(Photo(fileName: "c.png", width: 10, height: 10))
        XCTAssertTrue(j.finalCompletion.isComplete)
        XCTAssertEqual(j.finalCompletion, Schema.final.completion(j.values))
    }

    func testOldJobJSONKeepsItsRemarks() throws {
        var j = Job.new(template: JobTemplate.all[0])
        j.values["remarks"] = .text("ข้อความเดิม ไม่มีเลขข้อ")
        j.values["verdict"] = .choice("ติดตั้งได้", other: "")
        let back = try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(j))
        XCTAssertEqual(back.values.text("remarks"), "ข้อความเดิม ไม่มีเลขข้อ")
        XCTAssertEqual(back.values.choice("verdict"), "ติดตั้งได้")
        XCTAssertEqual(back.finalCompletion, j.finalCompletion)
    }
}

final class FinalSummaryTests: XCTestCase {
    func testStatusLine() {
        var j = Job.new(template: JobTemplate.all[0])
        let others = FinalSummary.otherPages(j)
        XCTAssertFalse(others.isEmpty)
        XCTAssertEqual(FinalSummary.statusLine(j),
                       "ยังขาดในหน้านี้: ผลการประเมิน, ลายเซ็นวิศวกรผู้สำรวจ, ชื่อผู้ประสานงาน, ลายเซ็นผู้ประสานงาน · และอีก \(others.count) หน้า")

        // "with conditions" and no remarks: a warning, completion unchanged
        j.values["verdict"] = .choice(Options.verdict[1], other: "")
        j.values["customerName"] = .text("ผู้ประสานงาน")
        j.values["surveyorSign"] = .photo(Photo(fileName: "s.png", width: 10, height: 10))
        j.values["customerSign"] = .photo(Photo(fileName: "c.png", width: 10, height: 10))
        XCTAssertTrue(j.finalCompletion.isComplete)
        XCTAssertEqual(FinalSummary.pageGaps(j.values), ["ความเห็น / เงื่อนไข"])
        j.values["verdict"] = .choice(Options.verdict[0], other: "")
        XCTAssertTrue(FinalSummary.pageGaps(j.values).isEmpty)
        XCTAssertEqual(FinalSummary.statusLine(j),
                       "หน้านี้ครบแล้ว · ยังขาดอีก \(others.count) หน้า (\(others.map(FinalSummary.code).joined(separator: ", ")))")
        XCTAssertFalse(FinalSummary.isComplete(j))
        XCTAssertEqual(FinalSummary.code(MissingGroup(target: .site, title: "A2 ภาพสถานที่ติดตั้ง", items: [])), "A2")
    }

    func testComplete() {
        var j = Job()
        j.values["verdict"] = .choice(Options.verdict[0], other: "")
        j.values["customerName"] = .text("ผู้ประสานงาน")
        j.values["surveyorSign"] = .photo(Photo(fileName: "s.png", width: 10, height: 10))
        j.values["customerSign"] = .photo(Photo(fileName: "c.png", width: 10, height: 10))
        if FinalSummary.otherPages(j).isEmpty {
            XCTAssertEqual(FinalSummary.statusLine(j), "ครบทุกหน้าแล้ว · พร้อมส่งออก")
            XCTAssertTrue(FinalSummary.isComplete(j))
        }
    }
}

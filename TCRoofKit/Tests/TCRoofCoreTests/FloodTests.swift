import XCTest
@testable import TCRoofCore

final class FloodTests: XCTestCase {
    func testMinimumInstallLevel() {
        var v = Values()
        v["floodHistory"] = .choice("เคย", other: ""); v["floodDepth"] = .text("80")
        XCTAssertEqual(FloodCheck.minCm(v), 130)
        XCTAssertEqual(Schema.recommendedEquipHeight(v), 130)
        // unknown + GISTDA without a depth: estimated 50 cm
        v["floodHistory"] = .choice("ไม่ทราบ", other: "")
        XCTAssertEqual(FloodCheck.state(v), .unknownEmpty)
        XCTAssertNil(Schema.recommendedEquipHeight(v))
        v.setGistda(FloodGistda())
        XCTAssertEqual(FloodCheck.state(v), .unknownFetched)
        XCTAssertEqual(FloodCheck.level(v), 50)
        XCTAssertEqual(FloodCheck.minCm(v), 100)
        XCTAssertEqual(Schema.recommendedEquipHeight(v), 100)
        v["floodHistory"] = .choice("ไม่เคย", other: "")
        XCTAssertEqual(FloodCheck.minCm(v), 50)
        XCTAssertNil(Schema.recommendedEquipHeight(v))
        XCTAssertFalse(Schema.flooded(v))
    }

    func testCheckTable() {
        var job = Job()
        job.values["floodHistory"] = .choice("เคย", other: ""); job.values["floodDepth"] = .text("80")
        job.values["invFloorCm"] = .text("30")
        var inv = SurveyModule(type: .inverter); inv.values["inverterCount"] = .text("2")
        job.modules = [inv, SurveyModule(type: .backfeed), SurveyModule(type: .fts)]
        let r = job.floodCheck
        XCTAssertEqual(r.rows.map(\.id), ["floor", "inv", "smdb", "emg", "mdb"])
        XCTAssertEqual(r.rows[0].status, .belowWater(50))
        XCTAssertEqual(r.rows[1].name, "อินเวอร์เตอร์ × 2")
        XCTAssertEqual(r.rows[1].status, .pass)
        XCTAssertEqual(r.rows[4].status, .floodedHere(80))
        XCTAssertEqual(r.fails, 0)
        job.values["floodDepth"] = .text("120")
        XCTAssertEqual(job.floodCheck.fails, 3)
        XCTAssertTrue(FloodCheck.statusLine(job.floodCheck).hasPrefix("อุปกรณ์ต่ำกว่าเกณฑ์ 3 รายการ"))
        // sections the job doesn't have are left out; no water, no MDB row
        job.modules = []; job.values["floodHistory"] = .choice("ไม่เคย", other: "")
        XCTAssertTrue(job.floodCheck.rows.isEmpty)
        XCTAssertFalse(FloodSection.sketch(job).ops.isEmpty)
    }

    /// A job saved before the A4 wide page decodes, and "ไม่ทราบ" alone completes A4 like "ไม่เคย".
    func testOldJobAndUnknownCompletion() throws {
        let old = """
        {"created":780000000,"id":"\(UUID().uuidString)","modules":[],"updated":780000100,
         "values":{"storage":{"floodHistory":{"choice":{"_0":"เคย","other":""}},"floodYear":{"text":{"_0":"2554"}},
                              "floodDepth":{"text":{"_0":"80"}}}}}
        """
        var j = try JobStore.decoder.decode(Job.self, from: Data(old.utf8))
        XCTAssertEqual(Schema.flood.completion(j.values).total, 3)
        XCTAssertTrue(Schema.flood.completion(j.values).isComplete)
        XCTAssertNil(j.values.gistda)
        j.values["floodHistory"] = .choice("ไม่ทราบ", other: "")
        let c = Schema.flood.completion(j.values)
        XCTAssertEqual(c.total, 1)
        XCTAssertTrue(c.isComplete)
        // the stored lookup survives save / load
        var g = FloodGistda(); g.years = [.init(year: 2554, plots: 4)]; g.place = "ต.ยางซ้าย"
        j.values.setGistda(g)
        let back = try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(j))
        XCTAssertEqual(back.values.gistda?.years.first?.plots, 4)
    }

    /// Shaped like the real response of flood-freq with `y_2011=1&limit=1` (trimmed).
    func testLookupParsing() throws {
        let hit = """
        {"type":"FeatureCollection","numberMatched":227,"numberReturned":1,"features":[
          {"type":"Feature","geometry":{"type":"MultiPolygon","coordinates":[]},
           "properties":{"freq":1,"tb_tn":"ต.ยางซ้าย","ap_tn":"อ.เมืองสุโขทัย","pv_tn":"จ.สุโขทัย","y_2011":1}}]}
        """
        let one = try FloodLookup.parseYear(Data(hit.utf8))
        XCTAssertEqual(one.plots, 227)
        XCTAssertEqual(one.place, "ต.ยางซ้าย อ.เมืองสุโขทัย จ.สุโขทัย")
        XCTAssertEqual(try FloodLookup.parseYear(Data(#"{"features":[],"numberMatched":0,"numberReturned":0}"#.utf8)).plots, 0)
        XCTAssertThrowsError(try FloodLookup.parseYear(Data("<html>504</html>".utf8)))
        XCTAssertEqual(FloodLookup.gregorianYears.map { $0 + 543 }.first, FloodGistda.firstYear)

        var g = FloodGistda()
        g.years = [.init(year: 2554, plots: 227), .init(year: 2555, plots: 16), .init(year: 2558, plots: 0)]
        XCTAssertEqual(g.floodedYears.map(\.year), [2554, 2555])
        XCTAssertEqual(g.headline, "ท่วม 2 จาก 3 ปี (2554–2558)")
        XCTAssertEqual(g.detail, "ล่าสุดปี 2555 | ท่วมมากสุดปี 2554 (227 แปลง)")
        XCTAssertEqual(g.rows.map(\.label), ["สรุป", "จำนวนแปลงที่ท่วม", "ความลึกน้ำ"])
        XCTAssertEqual(g.rows[1].value, "2554 (227) | 2555 (16)")
        XCTAssertEqual(g.rows[0].tone, .warn)
        XCTAssertEqual(g.rows[2].value, "ไม่มีข้อมูลความลึก | ใช้ค่าประเมิน 50 ซม.")
        XCTAssertFalse(g.chart().ops.isEmpty)
        XCTAssertEqual(g.summary, "GISTDA: ท่วม 2 ปีในรัศมี 1 กม.")
        g.years = [.init(year: 2554, plots: 0)]
        XCTAssertEqual(g.rows[0].tone, .good)
        XCTAssertNil(g.detail)
        XCTAssertEqual(g.summary, "GISTDA: ไม่พบพื้นที่ท่วมซ้ำซาก")
        // "use the estimate" when the service does not answer
        let manual = FloodGistda.estimate()
        XCTAssertEqual(manual.rows.count, 1)
        XCTAssertEqual(manual.estimatedDepthCm, 50)
    }

    func testCacheKeepsAreaResults() throws {
        let defaults = UserDefaults(suiteName: "FloodTests-\(UUID().uuidString)")!
        let cache = FloodCache(defaults: defaults)
        var g = FloodGistda(); g.lat = 17.0062; g.lon = 99.8235; g.years = [.init(year: 2554, plots: 9)]
        g.fetchedAt = Date(timeIntervalSinceNow: -86_400)
        cache.store(g)
        // about 100 m away is the same area
        XCTAssertEqual(cache.lookup(lat: 17.0064, lon: 99.8232, fresh: true)?.years.first?.plots, 9)
        XCTAssertNil(cache.lookup(lat: 17.0200, lon: 99.8235, fresh: false))
        // a month on it is only a fallback
        XCTAssertNil(cache.lookup(lat: 17.0062, lon: 99.8235, fresh: true, now: Date(timeIntervalSinceNow: 40 * 86_400)))
        XCTAssertNotNil(cache.lookup(lat: 17.0062, lon: 99.8235, fresh: false, now: Date(timeIntervalSinceNow: 40 * 86_400)))
        // the surveyor's own estimate is not a GISTDA result
        cache.store(.estimate())
        XCTAssertNil(cache.lookup(lat: 0, lon: 0, radius: 0, fresh: false))
    }

    func testLookupNeedsKey() async {
        do { _ = try await FloodLookup(apiKey: " ").fetch(lat: 17, lon: 99.8); XCTFail() }
        catch { XCTAssertEqual(error as? FloodLookup.Failure, .noKey) }
    }

    // MARK: freeboard (docs/ui/survey-a4-ipad-v2 §4.1)

    func flooded(_ depth: String, freeboard: String? = nil) -> Values {
        var v = Values()
        v["floodHistory"] = .choice("เคย", other: ""); v["floodDepth"] = .text(depth)
        if let freeboard { v["floodFreeboard"] = .text(freeboard) }
        return v
    }

    /// A job with no freeboard answer computes as before the answer existed: level + 50, rounded up to 10.
    func testNoFreeboardAnswerKeepsTodaysResult() {
        for (depth, expected) in [("80", 130), ("75", 130), ("83", 140), ("0", 50)] {
            let v = flooded(depth)
            XCTAssertEqual(FloodCheck.freeboardCm(v), FloodCheck.defaultFreeboardCm)
            XCTAssertEqual(FloodCheck.minCm(v), expected, depth)
            XCTAssertEqual(Schema.recommendedEquipHeight(v), depth == "0" ? nil : expected)
        }
        XCTAssertNil(FloodCheck.roundedFrom(flooded("80")))
        // the field is hidden, so A4's completion is unchanged
        XCTAssertEqual(Schema.flood.completion(flooded("80", freeboard: "30")).total, Schema.flood.completion(flooded("80")).total)
    }

    /// The short labels are display only: each names an existing option, which stays what is stored.
    func testShortLabelsNameExistingOptions() {
        XCTAssertTrue(Set(Schema.floodSourceShort.keys).isSubset(of: Schema.floodSources))
        XCTAssertTrue(Set(Schema.floodHitShort.keys).isSubset(of: Schema.floodHits))
        XCTAssertEqual(Schema.floodSources.count, 5)
        XCTAssertEqual(Schema.floodHits.count, 5)
    }

    func testFreeboardRoundsUp() {
        let v = flooded("75", freeboard: "30")
        XCTAssertEqual(FloodCheck.freeboardCm(v), 30)
        XCTAssertEqual(FloodCheck.minCm(v), 110)
        XCTAssertEqual(FloodCheck.roundedFrom(v), 105)
        XCTAssertEqual(FloodCheck.cmText(FloodCheck.roundedFrom(v)!), "105")
        XCTAssertEqual(FloodCheck.cmText(82.5), "82.5")
    }

    func testZeroFreeboard() {
        let v = flooded("80", freeboard: "0")
        XCTAssertEqual(FloodCheck.freeboardCm(v), 0)
        XCTAssertEqual(FloodCheck.minCm(v), 80)
        XCTAssertNil(FloodCheck.roundedFrom(v))
        // a negative answer typed by hand counts as none above the water
        XCTAssertEqual(FloodCheck.freeboardCm(flooded("80", freeboard: "-20")), 0)
    }

    /// `ไม่เคย`: no water, so the minimum level is the freeboard alone (rounded up to 10).
    func testNeverIsTheFreeboardAlone() {
        var v = flooded("80", freeboard: "70")
        v["floodHistory"] = .choice("ไม่เคย", other: "")
        XCTAssertEqual(FloodCheck.level(v), 0)
        XCTAssertEqual(FloodCheck.minCm(v), 70)
        v["floodFreeboard"] = .text("35")
        XCTAssertEqual(FloodCheck.minCm(v), 40)
        XCTAssertEqual(FloodCheck.roundedFrom(v), 35)
        v["floodFreeboard"] = nil
        XCTAssertEqual(FloodCheck.minCm(v), 50)
    }

    /// The freeboard moves the check table, the result and the drawings' label; the PDF keeps its own drawing.
    func testFreeboardReachesTheCheckAndDrawings() {
        var job = Job()
        job.values = flooded("80", freeboard: "30")
        job.values["invFloorCm"] = .text("30")
        job.modules = [SurveyModule(type: .inverter), SurveyModule(type: .backfeed), SurveyModule(type: .fts)]
        let r = job.floodCheck
        XCTAssertEqual(r.freeboard, 30)
        XCTAssertEqual(r.minCm, 110)
        // floor and inverter share B2's number; the existing board (A3) isn't checked against the level
        XCTAssertEqual(FloodCheck.checkedTags(r), [r.rows[1].tag, r.rows[2].tag, r.rows[3].tag])
        XCTAssertFalse(FloodCheck.checkedTags(r).contains("A3"))
        func texts(_ s: Sketch) -> [String] { s.ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { return t }; return nil } }
        XCTAssertTrue(texts(FloodSection.sketch(job)).contains("ระยะเผื่อ 30"))
        XCTAssertEqual(texts(FloodSection.sketch(job)), texts(FloodSection.sketch(job, style: .report)))
        let screen = texts(FloodSection.sketch(job, style: .screen))
        XCTAssertTrue(screen.contains("เผื่อ 30"))
        XCTAssertTrue(screen.contains("+1.10"))
        XCTAssertTrue(screen.contains("+0.80"))
        XCTAssertTrue(screen.contains("+0.30"))
        XCTAssertTrue(screen.contains("±0.00"))
        // the minimum level's line is where the scale puts 110 cm
        let k = FloodSection.scale(job, style: .screen)
        XCTAssertTrue(FloodSection.sketch(job, style: .screen).ops.contains {
            if case let .line(a, b, _, _, dash) = $0 { return !dash.isEmpty && abs(a.y - (FloodSection.groundY - 110 * k)) < 0.01 && a.y == b.y }
            return false
        })
        XCTAssertEqual(FloodCheck.statusLine(r), "ครบช่องบังคับแล้ว | อุปกรณ์ใหม่ผ่านเกณฑ์ ≥ 110 ซม. | จุดต่อ MDB1 เคยน้ำท่วม")
        XCTAssertTrue(FloodCheck.statusLine(r, missing: 2).hasPrefix("ยังขาด 2 ช่องบังคับ | "))
    }
}

/// Calls the real service; runs only with `GISTDA_API_KEY` in the environment (never in CI, no key in the repo).
final class FloodLookupLiveTests: XCTestCase {
    func testLiveLookup() async throws {
        let key = ProcessInfo.processInfo.environment["GISTDA_API_KEY"] ?? ""
        try XCTSkipIf(key.isEmpty, "set GISTDA_API_KEY to call GISTDA")
        let g: FloodGistda
        do { g = try await FloodLookup(apiKey: key).fetch(lat: 17.0062, lon: 99.8235) }
        catch FloodLookup.Failure.http(504) { throw XCTSkip("GISTDA gateway timed out (504)") }
        for r in g.rows { print(r.label, "|", r.value) }
        print(g.footnote)
        XCTAssertEqual(g.years.count, 14)
        XCTAssertFalse(g.place.isEmpty)
    }
}

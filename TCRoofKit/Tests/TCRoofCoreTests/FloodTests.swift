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
        XCTAssertEqual(g.rows.map(\.label), ["ปีที่ท่วม รัศมี 1 กม.", "ความลึกน้ำ"])
        XCTAssertEqual(g.rows[0].value, "2554 (227) · 2555 (16)")
        XCTAssertEqual(g.rows[0].tone, .warn)
        XCTAssertEqual(g.rows[1].value, "ไม่มีในข้อมูลดาวเทียม · ใช้ค่าประเมิน 50 ซม.")
        XCTAssertEqual(g.summary, "GISTDA: ท่วม 2 ปีในรัศมี 1 กม.")
        g.years = [.init(year: 2554, plots: 0)]
        XCTAssertEqual(g.rows[0].tone, .good)
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

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
        var g = FloodGistda(); g.plots = 4; g.place = "ต.ยางซ้าย"
        j.values.setGistda(g)
        let back = try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(j))
        XCTAssertEqual(back.values.gistda?.plots, 4)
    }

    /// Shaped like the real response of flood-freq for a 25 m box with limit=1 (trimmed).
    func testLookupParsing() throws {
        let hit = """
        {"type":"FeatureCollection","numberMatched":2,"numberReturned":1,"features":[
          {"type":"Feature","geometry":{"type":"MultiPolygon","coordinates":[]},
           "properties":{"freq":6,"tb_tn":"ต.ยางซ้าย","ap_tn":"อ.เมืองสุโขทัย","pv_tn":"จ.สุโขทัย",
                         "y_2011":1,"y_2012":1,"y_2017":1,"y_2019":1,"y_2021":1,"y_2024":1,"y_2013":0}}]}
        """
        let g = try FloodLookup.parsePoint(Data(hit.utf8))
        XCTAssertTrue(g.insideRepeatArea)
        XCTAssertEqual(g.plots, 2)
        XCTAssertEqual(g.maxTimes, 6)
        XCTAssertEqual(g.pointYears, [2554, 2555, 2560, 2562, 2564, 2567])
        XCTAssertEqual(g.place, "ต.ยางซ้าย อ.เมืองสุโขทัย จ.สุโขทัย")
        XCTAssertEqual(g.rows.map(\.label), ["จุดติดตั้ง", "ความลึกน้ำ"])
        XCTAssertEqual(g.rows[0].tone, .bad)
        XCTAssertTrue(g.rows[0].value.contains("ท่วม 6 ครั้ง") && g.rows[0].value.hasSuffix("ย้อนหลังถึงปี 2554"))
        XCTAssertNil(g.depthCm)
        XCTAssertEqual(g.rows[1].value, "ไม่มีในข้อมูลดาวเทียม · ใช้ค่าประเมิน 50 ซม.")
        // nothing near the point
        let none = try FloodLookup.parsePoint(Data(#"{"features":[],"numberMatched":0,"numberReturned":0}"#.utf8))
        XCTAssertFalse(none.insideRepeatArea)
        XCTAssertEqual(none.rows[0].tone, .good)
        XCTAssertEqual(none.summary, "GISTDA: ไม่อยู่ในพื้นที่ท่วมซ้ำซาก")
        // "use the estimate" when the service does not answer
        let manual = FloodGistda.estimate()
        XCTAssertEqual(manual.rows.count, 1)
        XCTAssertEqual(manual.estimatedDepthCm, 50)
        XCTAssertThrowsError(try FloodLookup.parsePoint(Data("<html>504</html>".utf8)))
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
        XCTAssertFalse(g.place.isEmpty)
    }
}

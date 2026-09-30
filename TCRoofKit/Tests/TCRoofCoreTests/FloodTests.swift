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

    /// Shaped like the real responses of flood-freq and flood/30days (trimmed).
    func testLookupParsing() throws {
        let lat = 17.0062, lon = 99.8235
        func square(_ x: Double, _ y: Double, _ d: Double) -> String {
            "[[[\(x),\(y)],[\(x + d),\(y)],[\(x + d),\(y + d)],[\(x),\(y + d)],[\(x),\(y)]]]"
        }
        let freq = """
        {"type":"FeatureCollection","numberMatched":2,"numberReturned":2,"features":[
          {"type":"Feature","geometry":{"type":"MultiPolygon","coordinates":[\(square(99.8285, 17.0050, 0.002))]},
           "properties":{"freq":1,"tb_tn":"ต.ยางซ้าย","ap_tn":"อ.เมืองสุโขทัย","pv_tn":"จ.สุโขทัย","y_2011":1,"y_2012":0,"y_2024":0}},
          {"type":"Feature","geometry":{"type":"Polygon","coordinates":\(square(99.8300, 17.0000, 0.002))},
           "properties":{"freq":6,"y_2011":1,"y_2012":1,"y_2017":1,"y_2019":1,"y_2021":1,"y_2024":1}}]}
        """
        let g0 = try FloodLookup.parseFreq(Data(freq.utf8), lat: lat, lon: lon)
        XCTAssertFalse(g0.insideRepeatArea)
        XCTAssertEqual(g0.plots, 2)
        XCTAssertEqual(g0.maxTimes, 6)
        XCTAssertEqual(g0.nearestTimes, 1)
        XCTAssertEqual(g0.nearestYears, [2554])
        XCTAssertEqual(g0.nearestMeters.map { abs($0 - 530) < 30 }, true)
        XCTAssertEqual(g0.plotYears, [2554, 2555, 2560, 2562, 2564, 2567])
        XCTAssertEqual(g0.place, "ต.ยางซ้าย อ.เมืองสุโขทัย จ.สุโขทัย")
        // a plot around the point
        let inside = """
        {"features":[{"geometry":{"type":"Polygon","coordinates":\(square(99.8230, 17.0055, 0.001))},"properties":{"freq":3,"y_2011":1}}]}
        """
        let g1 = try FloodLookup.parseFreq(Data(inside.utf8), lat: lat, lon: lon)
        XCTAssertTrue(g1.insideRepeatArea)
        XCTAssertEqual(g1.nearestMeters, 0)
        XCTAssertEqual(g1.rows.first?.tone, .bad)

        var g = g0
        let recent = """
        {"features":[{"geometry":{"type":"MultiPolygon","coordinates":[\(square(99.8320, 17.0060, 0.0005))]},
          "properties":{"file_name":"S1D_20260910_0551, rd2_20260901_1811, S1C_20260928_0550","tb_tn":"ต.ยางซ้าย"}}]}
        """
        FloodLookup.parseRecent(Data(recent.utf8), lat: lat, lon: lon, into: &g)
        XCTAssertTrue(g.recentFound)
        XCTAssertEqual(g.rows.map(\.label), ["จุดติดตั้ง", "ความลึกน้ำ"])
        XCTAssertEqual(g.recentFrom, "1/9/2569")
        XCTAssertEqual(g.recentTo, "28/9/2569")
        XCTAssertEqual(g.recentMeters.map { abs($0 - 900) < 30 }, true)
        XCTAssertNil(g.depthCm)
        XCTAssertEqual(g.rows.last?.value, "ไม่มีในข้อมูลดาวเทียม · ใช้ค่าประเมิน 50 ซม.")
        XCTAssertThrowsError(try FloodLookup.parseFreq(Data("<html>504</html>".utf8), lat: lat, lon: lon))
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

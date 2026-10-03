import XCTest
@testable import TCRoofCore

/// B4 zero export (docs/ui/survey-b4): four required photos, the pole for HV, labels by level, the SLD crop and old jobs.
final class ZeroExportTests: XCTestCase {
    static let photo = Photo(fileName: "p.jpg", width: 400, height: 300)

    func module(_ level: String, photos n: Int) -> SurveyModule {
        var m = SurveyModule(type: .backfeed)
        m.values["level"] = .choice(level, other: "")
        for key in ZeroExport.photoKeys.prefix(n) { m.values[key] = .photo(Self.photo) }
        return m
    }

    func missing(_ m: SurveyModule) -> [String] {
        var j = Job(); j.modules = [m]
        return j.missingGroups.first { $0.target == .module(m.id) }?.items ?? []
    }

    func testLVWithTwoPhotosMissesTwo() {
        let m = module(ZeroExport.lv, photos: 2)
        XCTAssertEqual(ZeroExport.missingPhotos(m.values), 2)
        XCTAssertEqual(m.completion.total - m.completion.filled, 2)
        XCTAssertEqual(missing(m), ["ภาพป้ายพิกัดอุปกรณ์เดิม", "ภาพพื้นที่ทำงาน / ขนาดบัสบาร์"])
        XCTAssertEqual(ZeroExport.statusLine(m.values), "ยังขาด: ภาพประกอบอีก 2 ภาพ (ต้องมีอย่างน้อย 4 ภาพ)")
        XCTAssertFalse(ZeroExport.isComplete(m.values))
    }

    func testFourPhotosComplete() {
        let m = module(ZeroExport.lv, photos: 4)
        XCTAssertTrue(m.completion.isComplete)
        XCTAssertTrue(missing(m).isEmpty)
        XCTAssertEqual(ZeroExport.statusLine(m.values), "ครบช่องบังคับแล้ว · SLD และ B2 อัปเดตตามตำแหน่งกันย้อน")
        XCTAssertTrue(ZeroExport.isComplete(m.values))
    }

    func testPhotoDetailCountsThoughOptionalInSchema() {
        var m = module(ZeroExport.lv, photos: 4)
        m.values["photoDetail"] = nil
        XCTAssertFalse(m.completion.isComplete)
        XCTAssertEqual(missing(m), ["รายละเอียด (ภาพ)"])
    }

    func testHVWithoutPoleMissesPole() {
        var m = module(ZeroExport.hv, photos: 4)
        XCTAssertFalse(m.completion.isComplete)
        XCTAssertEqual(missing(m), ["เสา"])
        XCTAssertEqual(ZeroExport.statusLine(m.values), "ยังขาด: เสา")
        m.values["pole"] = .choice("เสาเดิม", other: "")
        XCTAssertTrue(m.completion.isComplete)
        XCTAssertTrue(ZeroExport.isComplete(m.values))
    }

    func testLabelsFollowTheLevel() {
        XCTAssertEqual(ZeroExport.photoLabel(0, hv: false, board: "MDP-2"), "ตู้ MDP-2 · วงจุดติดตั้ง CT")
        XCTAssertEqual(ZeroExport.photoLabel(3, hv: false, board: "MDP-2"), "บัสบาร์ขาออก ACB · วัดขนาดสำหรับ CT")
        XCTAssertEqual(ZeroExport.photoLabel(0, hv: true, board: "MDP-2"), "เสาหลังมิเตอร์ · จุด CT/VT")
        XCTAssertEqual(ZeroExport.photoLabel(2, hv: true, board: "MDP-2"), "ป้ายมิเตอร์ กฟภ. / CT-VT เดิม")
    }

    func testEquipmentUsesQuestionMarksWhenUnknown() {
        var j = Job()
        let lv = module(ZeroExport.lv, photos: 0)
        j.modules = [lv]
        let items = ZeroExport.equipment(j, lv.values, SingleLine.build(j))
        XCTAssertEqual(items.map(\.title), ["CT 3 ตัว", "รีเลย์กันย้อน (Zero export)", "สายสัญญาณควบคุม"])
        XCTAssertEqual(items[1].sub, "ในตู้ ?")
        var hv = module(ZeroExport.hv, photos: 0)
        hv.values["pole"] = .choice("เสาใหม่", other: "")
        j.modules = [hv]
        let h = ZeroExport.equipment(j, hv.values, SingleLine.build(j))
        XCTAssertEqual(h.map(\.title), ["CT/VT แรงสูง ? kV", "รีเลย์กันย้อนแรงสูง", "สายสัญญาณควบคุม"])
        XCTAssertEqual(h[1].sub, "ปักเสาใหม่")
    }

    /// LV and HV each expose a crop that holds B4's relay box.
    func testSLDCropBoxHoldsTheRelay() throws {
        for hv in [false, true] {
            let d = SingleLineLayout.draw(SingleLine.build(SingleLineTests.fixture(), hvOverride: hv))
            let b = try XCTUnwrap(d.zeroExportBox)
            let relay = try XCTUnwrap(d.hits.first { $0.target == .module(.backfeed) }).box
            XCTAssertTrue(b.x <= relay.x && relay.maxX <= b.maxX && b.y <= relay.y && relay.maxY <= b.maxY, "hv \(hv)")
            XCTAssertLessThanOrEqual(b.maxX, d.width)
        }
    }

    /// A B4 saved before the wide page: two photos, no `photoRating` / `photoAccess`.
    func testOldJobDecodes() throws {
        let mid = UUID()
        let ph = #"{"photo":{"_0":{"fileName":"a.jpg","height":300,"id":"\#(UUID().uuidString)","takenAt":812000000,"width":400}}}"#
        let old = """
        {"created":780000000,"id":"\(UUID().uuidString)","updated":780000100,
         "modules":[{"id":"\(mid.uuidString)","type":"backfeed","name":"","values":{"storage":{"photoArea":\(ph),"photoDetail":\(ph),
           "level":{"choice":{"_0":"กันย้อนที่แรงต่ำ","other":""}}}}}],
         "values":{"storage":{}}}
        """
        let j = try JobStore.decoder.decode(Job.self, from: Data(old.utf8))
        let v = j.modules[0].values
        XCTAssertNotNil(v.photo("photoDetail"))
        XCTAssertNil(v.photo("photoRating"))
        XCTAssertEqual(v.choice("level"), ZeroExport.lv)
        // intended: the two new photos now show as missing
        XCTAssertEqual(ZeroExport.missingPhotos(v), 2)
        XCTAssertFalse(j.modules[0].completion.isComplete)
    }
}

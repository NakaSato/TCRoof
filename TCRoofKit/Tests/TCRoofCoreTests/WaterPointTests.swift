import XCTest
@testable import TCRoofCore

/// B3 water point (docs/ui/survey-b3): one A2 `.water` mark per water module, old jobs unchanged.
final class WaterPointTests: XCTestCase {
    static let photo = Photo(fileName: "p.jpg", width: 400, height: 300)

    func job(waterModules n: Int) -> Job {
        var j = Job.new(template: JobTemplate.all[2])
        j.modules.removeAll { $0.type == .water }
        for i in 0..<n { j.modules.append(SurveyModule(type: .water, name: "จุด \(i + 1)")) }
        j.values["siteMarks"] = .marks([MapMark(kind: .trafo, x: 0.5, y: 0.5, value: "630")])
        return j
    }
    func waterMarks(_ j: Job) -> [MapMark] { j.values.marks("siteMarks").filter { $0.kind == .water } }

    func testTapCreatesThenMovesOneMark() throws {
        var j = job(waterModules: 1)
        let m = j.modules.first { $0.type == .water }!.id
        XCTAssertNil(WaterPoint.mark(j, module: m))
        WaterPoint.place(&j, module: m, x: 0.2, y: 0.3)
        XCTAssertEqual(waterMarks(j).count, 1)
        XCTAssertEqual(waterMarks(j)[0].module, m)
        let id = waterMarks(j)[0].id
        WaterPoint.place(&j, module: m, x: 0.7, y: 1.4)
        XCTAssertEqual(waterMarks(j).count, 1)
        XCTAssertEqual(waterMarks(j)[0].id, id)
        XCTAssertEqual(waterMarks(j)[0].x, 0.7, accuracy: 1e-9)
        XCTAssertEqual(waterMarks(j)[0].y, 1, accuracy: 1e-9)
        // A2's own symbols are untouched
        XCTAssertEqual(j.values.marks("siteMarks").filter { $0.kind == .trafo }.count, 1)
        // the link survives save / load
        let back = try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(j))
        XCTAssertEqual(WaterPoint.mark(back, module: m)?.id, id)
    }

    func testEachModuleKeepsItsOwnMark() {
        var j = job(waterModules: 2)
        let ids = j.modules.filter { $0.type == .water }.map(\.id)
        WaterPoint.place(&j, module: ids[1], x: 0.9, y: 0.9)
        WaterPoint.place(&j, module: ids[0], x: 0.1, y: 0.1)
        WaterPoint.place(&j, module: ids[1], x: 0.8, y: 0.8)
        XCTAssertEqual(waterMarks(j).count, 2)
        XCTAssertEqual(WaterPoint.mark(j, module: ids[0])?.x, 0.1)
        XCTAssertEqual(WaterPoint.mark(j, module: ids[1])?.x, 0.8)
        WaterPoint.remove(&j, module: ids[0])
        XCTAssertNil(WaterPoint.mark(j, module: ids[0]))
        XCTAssertEqual(waterMarks(j).count, 1)
    }

    /// A job saved before B3's page: a `.water` mark with no module link and a water module with the old answers.
    func testOldJobDecodesAndAdoptsItsMark() throws {
        let mid = UUID(), markID = UUID()
        let old = """
        {"created":780000000,"id":"\(UUID().uuidString)","updated":780000100,
         "modules":[{"id":"\(mid.uuidString)","type":"water","name":"","values":{"storage":{
            "waterMode":{"choice":{"_0":"ติดตั้งร่วมกับระบบน้ำเดิม","other":""}},"detail":{"text":{"_0":"ท่อ 1 นิ้ว"}}}}}],
         "values":{"storage":{"siteMarks":{"marks":{"_0":[{"id":"\(markID.uuidString)","kind":"water","x":0.4,"y":0.6,"value":""}]}}}}}
        """
        var j = try JobStore.decoder.decode(Job.self, from: Data(old.utf8))
        let w = j.modules[0]
        XCTAssertEqual(WaterPoint.mode(w.values), .existing)
        XCTAssertEqual(w.values.text("detail"), "ท่อ 1 นิ้ว")
        XCTAssertNil(j.values.marks("siteMarks")[0].module)
        // the unlinked mark is this module's pin; moving it links it and adds no second mark
        XCTAssertEqual(WaterPoint.mark(j, module: mid)?.id, markID)
        WaterPoint.place(&j, module: mid, x: 0.5, y: 0.5)
        XCTAssertEqual(waterMarks(j).map(\.id), [markID])
        XCTAssertEqual(waterMarks(j)[0].module, mid)
    }

    func testCompletionUnchanged() {
        var m = SurveyModule(type: .water)
        XCTAssertEqual(m.completion.total, 3)
        XCTAssertEqual(WaterPoint.missingPhotos(m.values), 2)
        XCTAssertEqual(WaterPoint.statusLine(m.values), "ยังขาดภาพประกอบอีก 2 ภาพ")
        m.values["photoArea"] = .photo(Self.photo)
        m.values["photoWide"] = .photo(Self.photo)
        m.values["waterMode"] = .choice(WaterPoint.Mode.new.rawValue, other: "")
        XCTAssertTrue(m.completion.isComplete)
        XCTAssertEqual(WaterPoint.statusLine(m.values), "ครบช่องบังคับแล้ว · จุดจ่ายน้ำแสดงบนภาพ A2 และรายงาน")
        // placing the pin is stored on the job, not the module, so the section's count doesn't move
        var j = job(waterModules: 0); j.modules.append(m)
        let before = j.completion
        WaterPoint.place(&j, module: m.id, x: 0.3, y: 0.3)
        XCTAssertEqual(j.completion, before)
    }

    func testSummary() {
        var j = job(waterModules: 1)
        j.modules.removeAll { $0.type == .roof || $0.type == .tank }
        XCTAssertEqual(WaterPoint.panelSummary(j), "—")
        j.modules.append(SurveyModule(type: .tank, name: "หลังคาถังน้ำใส 1", values: Values(["panelsBefore": .text("420"), "panelsCut": .text("4")])))
        j.values["capacity"] = .text("237.1")
        XCTAssertEqual(WaterPoint.roofNames(j), "หลังคาถังน้ำใส 1")
        XCTAssertEqual(WaterPoint.panelSummary(j), "416 แผง · 237.1 kWp")
    }
}

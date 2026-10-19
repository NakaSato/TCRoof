import XCTest
@testable import TCRoofCore

/// B5 Emergency button (docs/ui/survey-b5): one `.emergency` mark per B5 module, the height shared with A4,
/// completion on `photoEmg` alone, old jobs unchanged.
final class EmergencyButtonTests: XCTestCase {
    static let photo = Photo(fileName: "p.jpg", width: 400, height: 300)

    func job(ftsModules n: Int) -> Job {
        var j = Job()
        for _ in 0..<n { j.modules.append(SurveyModule(type: .fts)) }
        j.values["siteMarks"] = .marks([MapMark(kind: .office, x: 0.5, y: 0.5)])
        return j
    }
    func pins(_ j: Job) -> [MapMark] { j.values.marks("siteMarks").filter { $0.kind == .emergency } }

    func testTapCreatesThenMovesOneMark() throws {
        var j = job(ftsModules: 2)
        let a = j.modules[0].id, b = j.modules[1].id
        XCTAssertNil(EmergencyButton.mark(j, module: a))
        EmergencyButton.place(&j, module: a, x: 0.2, y: 0.3)
        EmergencyButton.place(&j, module: a, x: 0.6, y: 0.7)
        XCTAssertEqual(pins(j).count, 1)
        XCTAssertEqual(pins(j)[0].module, a)
        XCTAssertEqual(EmergencyButton.mark(j, module: a)?.x, 0.6)
        EmergencyButton.place(&j, module: b, x: 0.1, y: 0.1)
        XCTAssertEqual(pins(j).count, 2)
        XCTAssertEqual(EmergencyButton.mark(j, module: a)?.x, 0.6)
        // A2's own symbols are untouched; the kind stays off A2's palette but draws
        XCTAssertEqual(j.values.marks("siteMarks").filter { $0.kind == .office }.count, 1)
        XCTAssertFalse(MarkKind.palette.contains(.emergency))
        XCTAssertFalse(SiteMarks.symbol(.emergency, at: Pt(0, 0), radius: 10).isEmpty)
        XCTAssertTrue(SiteMarks.usedKinds(j.values.marks("siteMarks")).contains(.emergency))
        // survives save / load; removing the module drops its pin only
        let back = try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(j))
        XCTAssertEqual(pins(back).map(\.kind), [.emergency, .emergency])
        ModuleMarks.removeAll(&j, for: j.modules[0])
        XCTAssertNil(EmergencyButton.mark(j, module: a))
        XCTAssertNotNil(EmergencyButton.mark(j, module: b))
    }

    func testStepperWritesTheHeightA4Checks() {
        var j = job(ftsModules: 1)
        j.values["floodHistory"] = .choice("เคย", other: ""); j.values["floodDepth"] = .text("80")
        XCTAssertEqual(EmergencyButton.heightCm(j), FloodCheck.defaultEmergencyCm)
        XCTAssertTrue(EmergencyButton.isRecommended(EmergencyButton.heightCm(j)))
        for _ in 0..<5 { EmergencyButton.step(&j, by: 1) }
        XCTAssertEqual(j.values.number("emgMountCm"), 165)
        XCTAssertEqual(EmergencyButton.meters(165), "1.65 ม.")
        XCTAssertFalse(EmergencyButton.isRecommended(165))
        XCTAssertEqual(j.floodCheck.rows.first { $0.id == "emg" }?.height, "165 ซม.")
        // clamped to 0.80–1.80 m
        for _ in 0..<10 { EmergencyButton.step(&j, by: 1) }
        XCTAssertEqual(j.values.number("emgMountCm"), 180)
        for _ in 0..<40 { EmergencyButton.step(&j, by: -1) }
        XCTAssertEqual(j.values.number("emgMountCm"), 80)
        // A4 not flooded: the value stays stored and B5 still reads it
        j.values["floodHistory"] = .choice("ไม่เคย", other: "")
        XCTAssertEqual(EmergencyButton.heightCm(j), 80)
    }

    func testCompletionNeedsOnlyTheButtonPhoto() {
        var m = SurveyModule(type: .fts)
        XCTAssertEqual(m.completion.total, 1)
        XCTAssertFalse(m.completion.isComplete)
        m.values["photoEmg"] = .photo(Self.photo)
        XCTAssertTrue(m.completion.isComplete)
        // the FTS cabinet photo and the place text don't change the count
        m.values["photoFTS"] = .photo(Self.photo); m.values["emgPlace"] = .text("ผนังข้างประตู Site Office")
        XCTAssertEqual(m.completion.total, 1)
        var j = job(ftsModules: 0); j.modules = [m]
        XCTAssertEqual(EmergencyButton.statusLine(j, m.values), "ครบช่องบังคับแล้ว · ตำแหน่งแสดงบนภาพ A2 และ SLD")
        j.values["emgMountCm"] = .text("165")
        XCTAssertEqual(EmergencyButton.statusLine(j, m.values), "ความสูงปุ่มแนะนำ 1.10–1.50 ม.")
        m.values["photoEmg"] = nil
        XCTAssertEqual(EmergencyButton.statusLine(j, m.values), "ยังขาดภาพบังคับ 1 ภาพ")
        XCTAssertTrue(j.facts(m).contains("ผนังข้างประตู Site Office"))
    }

    /// A B5 saved before the wide page: both photos, no `emgPlace`, no `.emergency` mark.
    func testOldJobDecodes() throws {
        let mid = UUID()
        let ph = #"{"photo":{"_0":{"fileName":"a.jpg","height":300,"id":"\#(UUID().uuidString)","takenAt":812000000,"width":400}}}"#
        let old = """
        {"created":780000000,"id":"\(UUID().uuidString)","updated":780000100,
         "modules":[{"id":"\(mid.uuidString)","type":"fts","name":"","values":{"storage":{"photoFTS":\(ph),"photoEmg":\(ph)}}}],
         "values":{"storage":{"siteMarks":{"marks":{"_0":[{"id":"\(UUID().uuidString)","kind":"water","x":0.4,"y":0.6,"value":""}]}}}}}
        """
        let j = try JobStore.decoder.decode(Job.self, from: Data(old.utf8))
        XCTAssertNotNil(j.modules[0].values.photo("photoFTS"))
        XCTAssertTrue(j.modules[0].completion.isComplete)
        XCTAssertEqual(j.modules[0].values.text("emgPlace"), "")
        XCTAssertNil(EmergencyButton.mark(j, module: mid))
        XCTAssertEqual(EmergencyButton.heightCm(j), FloodCheck.defaultEmergencyCm)
    }

    /// The SLD exposes the FTS / Emergency crop round the button (B5's "ใน SLD" card); none without a connection board.
    func testSLDCropBox() throws {
        XCTAssertNil(SingleLineLayout.draw(SingleLine.build(job(ftsModules: 1))).ftsBox)
        // the fixture with its B5 (without one there is no FTS part: SingleLineTests.testFTSOnlyWithB5)
        var withB5 = SingleLineTests.fixture()
        if !withB5.modules.contains(where: { $0.type == .fts }) { withB5.modules.append(SurveyModule(type: .fts)) }
        let d = SingleLineLayout.draw(SingleLine.build(withB5))
        let b = try XCTUnwrap(d.ftsBox)
        XCTAssertGreaterThan(b.w, 300); XCTAssertGreaterThan(b.h, 100)
        XCTAssertLessThanOrEqual(b.maxX, d.width); XCTAssertLessThanOrEqual(b.maxY, d.height)
        let emg = try XCTUnwrap(d.hits.first { $0.target == .module(.fts) }).box
        XCTAssertTrue(b.x <= emg.x && emg.maxX <= b.maxX && b.y <= emg.y && emg.maxY <= b.maxY + 20)
    }
}

import XCTest
@testable import TCRoofCore

/// A2 v2 building models and undo / redo (docs/ui/survey-a2/CLAUDE_CODE_TASK_v2.md §2, §5).
final class SiteModelsTests: XCTestCase {
    /// A job saved before v2 has neither key: no models, not locked, and A2's completion is unchanged by adding them.
    func testOldJobWithoutModelsDecodes() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","created":0,"updated":0,"modules":[],
         "values":{"storage":{"siteNote":{"text":{"_0":"เก่า"}}}}}
        """
        let j = try JSONDecoder().decode(Job.self, from: Data(json.utf8))
        XCTAssertEqual(j.values.text("siteNote"), "เก่า")
        XCTAssertTrue(SiteModels.models(j.values).isEmpty)
        XCTAssertFalse(SiteModels.allLocked(j.values))

        var v = j.values
        let before = Schema.site.completion(v)
        SiteModels.setModels([SiteModel(id: "x", x: 0.5, y: 0.5)], in: &v)
        SiteModels.setAllLocked(true, in: &v)
        XCTAssertEqual(Schema.site.completion(v).total, before.total)
        XCTAssertEqual(Schema.site.completion(v).filled, before.filled)
    }

    /// A model stored with only an id still decodes; a full one round-trips through the job file.
    func testModelDecodesWithDefaultsAndRoundTrips() throws {
        let m = try JSONDecoder().decode(SiteModel.self, from: Data(#"{"id":"D1"}"#.utf8))
        XCTAssertEqual(m, SiteModel(id: "D1", x: 0.5, y: 0.5, rotation: 0, locked: false))
        var j = Job.new(template: JobTemplate.all[2])
        SiteModels.setModels([SiteModel(id: "a", x: 0.2, y: 0.7, rotation: 15, locked: true)], in: &j.values)
        let back = try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(j))
        XCTAssertEqual(SiteModels.models(back.values), [SiteModel(id: "a", x: 0.2, y: 0.7, rotation: 15, locked: true)])
    }

    /// The size is read live from the section: editing the tank's spans resizes its model.
    func testSizeFollowsSourceSection() {
        var tank = SurveyModule(type: .tank, name: "1")
        tank.values["spansX"] = .text("10,10,10,10")
        tank.values["spansY"] = .text("20,20")
        tank.values["panelsBefore"] = .text("400")
        var inv = SurveyModule(type: .inverter)
        inv.values["sizeLWH"] = .text("5 x 4")
        let b1 = SurveyModule(type: .panel, name: "MDB")
        var j = Job(modules: [b1, inv, tank])
        var s = SiteModels.sources(j)
        // PV areas first, then electrical buildings
        XCTAssertEqual(s.map(\.code), ["D1", "B1", "B2"])
        XCTAssertEqual(s[0].width, 40); XCTAssertEqual(s[0].length, 40)
        XCTAssertTrue(s[0].subtitle.contains("40 × 40 ม. · 400 แผง"))
        XCTAssertEqual(s[2].width, 5); XCTAssertEqual(s[2].length, 4)
        XCTAssertFalse(s[1].hasSize)
        XCTAssertEqual(s[1].sizeText, "ยังไม่มีขนาด")

        // a model 40 m wide on a picture 100 m across covers 40% of its width
        let model = SiteModel(id: tank.id.uuidString, x: 0.5, y: 0.5)
        let box = Box(0, 0, 1000, 600)
        var c = SiteModels.corners(model, width: s[0].width!, length: s[0].length!, in: box, metersAcross: 100)
        XCTAssertEqual(c[1].x - c[0].x, 400, accuracy: 0.001)

        j.modules[2].values["spansX"] = .text("10,10")
        s = SiteModels.sources(j)
        c = SiteModels.corners(model, width: s[0].width!, length: s[0].length!, in: box, metersAcross: 100)
        XCTAssertEqual(c[1].x - c[0].x, 200, accuracy: 0.001)

        // the B1 building takes its size once entered
        j.modules[0].values[SiteModels.buildingWidthKey] = .text("6")
        j.modules[0].values[SiteModels.buildingLengthKey] = .text("4")
        XCTAssertEqual(SiteModels.sources(j)[1].sizeText, "6 × 4 ม.")
    }

    /// The report draws placed models only when the picture has a scale.
    func testReportOpsNeedScale() {
        var tank = SurveyModule(type: .tank)
        tank.values["spansX"] = .text("40"); tank.values["spansY"] = .text("40")
        var j = Job(modules: [tank])
        SiteModels.setModels([SiteModel(id: tank.id.uuidString, x: 0.5, y: 0.5)], in: &j.values)
        XCTAssertTrue(SiteModels.reportOps(j, in: Box(0, 0, 500, 300)).isEmpty)
        j.values[SiteShapes.scaleKey] = .text("120")
        XCTAssertFalse(SiteModels.reportOps(j, in: Box(0, 0, 500, 300)).isEmpty)
        // a model whose section was deleted is skipped
        j.modules = []
        XCTAssertTrue(SiteModels.reportOps(j, in: Box(0, 0, 500, 300)).isEmpty)
    }

    func testRedoRestoresUndoneEditAndNewEditClearsIt() {
        var h = UndoStack<[Int]>()
        var state = [1]
        h.record(state); state.append(2)
        h.record(state); state.append(3)
        XCTAssertFalse(h.canRedo)

        state = h.undo(state)!
        XCTAssertEqual(state, [1, 2])
        XCTAssertTrue(h.canRedo)
        state = h.redo(state)!
        XCTAssertEqual(state, [1, 2, 3])
        XCTAssertNil(h.redo(state))

        state = h.undo(state)!
        XCTAssertTrue(h.canRedo)
        h.record(state); state.append(9)
        XCTAssertFalse(h.canRedo)
        XCTAssertNil(h.redo(state))
        XCTAssertEqual(h.undo(state), [1, 2])
    }
}

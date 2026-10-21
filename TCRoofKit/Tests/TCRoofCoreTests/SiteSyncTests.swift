import XCTest
@testable import TCRoofCore

final class SiteSyncTests: XCTestCase {
    private func job(marks: [MapMark], trafos: [Transformer] = [], modules: [SurveyModule] = []) -> Job {
        var v = Values()
        v["siteMarks"] = .marks(marks)
        if !trafos.isEmpty { v["trafos"] = .transformers(trafos) }
        return Job(values: v, modules: modules)
    }
    private func marks(_ j: Job) -> [MapMark] { j.values.marks("siteMarks") }
    private func trafos(_ j: Job) -> [Transformer] { j.values.transformers("trafos") }

    func testTrafoMarkFillsEmptyA3AndLinks() {
        var j = job(marks: [MapMark(kind: .trafo, x: 0.5, y: 0.5, value: "630", label: "TX 1")])
        let items = SiteSync.push(&j)
        XCTAssertEqual(trafos(j).map(\.kva), ["630"])
        XCTAssertEqual(marks(j)[0].link, "tr:\(trafos(j)[0].id)")
        XCTAssertEqual(items.map(\.status), [.filled])
        XCTAssertEqual(items[0].title, "หม้อแปลง TX 1 | 630 kVA")
        let once = j
        SiteSync.push(&j)
        XCTAssertEqual(j, once)
    }

    func testMdbMarkFillsMainBoardNameAndAT() {
        var j = job(marks: [MapMark(kind: .trafo, x: 0.2, y: 0.2, value: "630"),
                            MapMark(kind: .mdb, x: 0.4, y: 0.4, value: "800", label: "MDP-1")])
        SiteSync.push(&j)
        let t = trafos(j)[0]
        XCTAssertEqual(j.values.text("tr0_feed"), "MDP-1")
        XCTAssertEqual(t.boards.first?.at, "800")
        XCTAssertEqual(t.mdb[0], "800")
        XCTAssertEqual(marks(j)[1].link, "bd:\(t.boards[0].id)")
        XCTAssertTrue(SiteSync.badges(j).isSuperset(of: [.kva(0), .boardName(0, 0), .boardAT(0, 0)]))
    }

    func testDefaultMdbLabelTakesA3Name() {
        var tr = Transformer(kva: "630")
        tr.setBoards([Board(name: "", isMain: true, at: "800")])
        var j = job(marks: [MapMark(kind: .mdb, x: 0.4, y: 0.4, label: "MDB")], trafos: [tr])
        j.values["tr0_feed"] = .text("MDP-1")
        SiteSync.push(&j)
        XCTAssertEqual(marks(j)[0].label, "MDP-1")
        XCTAssertEqual(marks(j)[0].value, "800")
    }

    func testConflictIsKeptUntilResolved() {
        let base = job(marks: [MapMark(kind: .trafo, x: 0.5, y: 0.5, value: "630 kVA")], trafos: [Transformer(kva: "500")])
        var j = base
        let items = SiteSync.push(&j)
        XCTAssertEqual(items.first?.status, .conflict(a3: "500", a2: "630"))
        XCTAssertEqual(trafos(j)[0].kva, "500")

        var a2 = j
        SiteSync.useA2(&a2, mark: marks(j)[0].id)
        XCTAssertEqual(trafos(a2)[0].kva, "630")
        XCTAssertEqual(SiteSync.items(a2).first?.status, .same)

        var a3 = j
        SiteSync.keepA3(&a3, mark: marks(j)[0].id)
        XCTAssertEqual(trafos(a3)[0].kva, "500")
        XCTAssertEqual(marks(a3)[0].value, "500")
    }

    func testTypingOnA2KeepsFollowing() {
        var j = job(marks: [MapMark(kind: .trafo, x: 0.5, y: 0.5, value: "6")])
        SiteSync.push(&j)
        let before = marks(j)
        var m = before
        m[0].value = "63"
        j.values["siteMarks"] = .marks(m)
        SiteSync.push(&j, previous: before)
        XCTAssertEqual(trafos(j)[0].kva, "63")
    }

    func testLinkSurvivesTransformerDelete() {
        var j = job(marks: [MapMark(kind: .trafo, x: 0.1, y: 0.1, value: "630"),
                            MapMark(kind: .trafo, x: 0.2, y: 0.2, value: "250")])
        SiteSync.push(&j)
        var a = trafos(j)
        a.remove(at: 0)
        j.values["trafos"] = .transformers(a)
        j.values.shiftTransformerAnswers(removed: 0)
        let items = SiteSync.push(&j)
        XCTAssertEqual(trafos(j).map(\.kva), ["250"])
        XCTAssertEqual(marks(j)[1].link, "tr:\(trafos(j)[0].id)")
        XCTAssertEqual(items.map(\.status), [.skipped("ลบที่ A3 แล้ว"), .same])
    }

    func testSixthTransformerIsNotCreated() {
        let marks = (0..<6).map { MapMark(kind: .trafo, x: 0.1, y: Double($0) / 10, value: "100") }
        var j = job(marks: marks)
        let items = SiteSync.push(&j)
        XCTAssertEqual(trafos(j).count, 5)
        XCTAssertEqual(items.last?.status, .skipped("เกิน 5 ลูก"))
    }

    func testZeroExportLevel() {
        let b4 = SurveyModule(type: .backfeed)
        var j = job(marks: [MapMark(kind: .zeroExport, x: 0.3, y: 0.3, value: "MV", module: b4.id)], modules: [b4])
        SiteSync.push(&j)
        XCTAssertEqual(j.modules[0].values.choice(ZeroExport.levelKey), ZeroExport.hv)

        let b4b = SurveyModule(type: .backfeed)
        var lv = job(marks: [MapMark(kind: .zeroExport, x: 0.3, y: 0.3, value: "LV")], modules: [b4b])
        SiteSync.push(&lv)
        XCTAssertEqual(lv.modules[0].values.choice(ZeroExport.levelKey), ZeroExport.lv)
        XCTAssertEqual(marks(lv)[0].module, b4b.id)

        var none = job(marks: [MapMark(kind: .zeroExport, x: 0.3, y: 0.3, value: "MV")])
        XCTAssertEqual(SiteSync.push(&none).first?.status, .skipped("ยังไม่มีหน้า B4"))
    }

    func testMeterIsLinkedOnly() {
        var j = job(marks: [MapMark(kind: .meter, x: 0.5, y: 0.5), MapMark(kind: .inv, x: 0.6, y: 0.6)])
        let items = SiteSync.push(&j)
        XCTAssertEqual(items.map(\.symbol), ["PEA METER"])
        XCTAssertEqual(j.values.text("meterNo"), "")
        XCTAssertEqual(SiteSync.badges(j), [.meter])
    }

    func testOldMarkJSONDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"trafo","x":0.5,"y":0.25,"value":"630"}"#
        let m = try JSONDecoder().decode(MapMark.self, from: Data(json.utf8))
        XCTAssertNil(m.link)
        XCTAssertEqual(m.value, "630")
        let back = try JSONDecoder().decode(MapMark.self, from: JSONEncoder().encode(MapMark(kind: .mdb, x: 0, y: 0, link: "bd:x")))
        XCTAssertEqual(back.link, "bd:x")
    }

    func testPullCopiesA3EditOntoLinkedMark() {
        var j = job(marks: [MapMark(kind: .trafo, x: 0.5, y: 0.5, value: "630"),
                            MapMark(kind: .mdb, x: 0.4, y: 0.4, value: "800", label: "MDP-1")])
        SiteSync.push(&j)
        let before = j
        var a = trafos(j)
        a[0].kva = "800"
        var b = a[0].boards
        b[0].at = "1000"
        a[0].setBoards(b)
        j.values["trafos"] = .transformers(a)
        j.values["tr0_feed"] = .text("MDB-A")
        SiteSync.pull(&j, since: before)
        XCTAssertEqual(marks(j)[0].value, "800")
        XCTAssertEqual(marks(j)[1].value, "1000")
        XCTAssertEqual(marks(j)[1].label, "MDB-A")
    }

    func testInputsChangeOnlyWithWhatTheSummaryReads() {
        var j = job(marks: [MapMark(kind: .trafo, x: 0.5, y: 0.5, value: "630")], trafos: [Transformer(kva: "630")])
        let before = SiteSync.Inputs(j)
        j.values["meterNo"] = .text("020-123456")
        XCTAssertEqual(SiteSync.Inputs(j), before)
        var t = trafos(j)
        t[0].kva = "500"
        j.values["trafos"] = .transformers(t)
        XCTAssertNotEqual(SiteSync.Inputs(j), before)
        XCTAssertEqual(SiteSync.summary(j).items.first?.status, .conflict(a3: "500", a2: "630"))
    }

    func testZeroExportSymbolLine() {
        XCTAssertEqual(SiteMarks.zeroExportLine(MapMark(kind: .zeroExport, x: 0, y: 0, value: "lv")), "LV")
        XCTAssertEqual(SiteMarks.zeroExportLine(MapMark(kind: .zeroExport, x: 0, y: 0)), "MV")
    }
}

import XCTest
@testable import TCRoofCore

/// B1 building panels page (docs/ui/survey-b1 SPEC §6).
final class BuildingPanelsTests: XCTestCase {
    static let photo = Photo(fileName: "p.jpg", width: 400, height: 300)

    func module(_ job: Job, _ name: String) throws -> SurveyModule { try XCTUnwrap(job.modules.first { $0.name == name }) }
    func mdpBreakers(_ job: Job) -> [Breaker] { job.values.transformers("trafos")[0].boards[0].breakers }

    func testStatusPill() {
        var v = Values()
        XCTAssertEqual(BuildingPanels.pill(v).text, "0/2 ภาพ")
        v["photoWide"] = .photo(Self.photo)
        XCTAssertEqual(BuildingPanels.pill(v).text, "1/2 ภาพ")
        v["photoBreaker"] = .photo(Self.photo)
        XCTAssertEqual(BuildingPanels.pill(v), .noLoad)
        XCTAssertEqual(BuildingPanels.pill(v).text, "ยังไม่กรอกโหลด")
        v["loadKW"] = .text("85")
        XCTAssertEqual(BuildingPanels.pill(v).text, "ครบ")
        XCTAssertTrue(BuildingPanels.pill(v).ok)
    }

    func testOptionsAndLink() throws {
        var job = SingleLineTests.fixture()
        // old targets are plain text; clear them so the link is what writes them
        var trafos = job.values.transformers("trafos")
        for j in trafos[0].boards[0].breakers.indices { trafos[0].boards[0].breakers[j].target = "" }
        job.values["trafos"] = .transformers(trafos)

        let opts = BuildingPanels.options(job)
        XCTAssertEqual(opts.count, 3)
        XCTAssertEqual(opts[0].label, "MDP-1 · CB1 400 AT")
        XCTAssertEqual(opts[1].cbText, "CB2 · 250 AT")
        XCTAssertNil(opts[0].linkedTo)

        let pump = try module(job, "โรงสูบน้ำ")
        XCTAssertEqual(BuildingPanels.subLine(pump, in: job), "ยังไม่ผูก A3 · โหลด 85 kW")
        BuildingPanels.link(&job, panel: pump.id, to: opts[0].ref)
        let linked = try module(job, "โรงสูบน้ำ")
        XCTAssertEqual(linked.values.text("breakerAT"), "400")
        XCTAssertEqual(linked.values.text("a3Breaker"), opts[0].ref.key)
        XCTAssertEqual(mdpBreakers(job)[0].target, "ตู้ไฟฟ้า โรงสูบน้ำ (B1.1)")
        XCTAssertEqual(BuildingPanels.options(job)[0].linkedTo, pump.id)
        XCTAssertEqual(BuildingPanels.subLine(linked, in: job), "CB1 · 400 AT · โหลด 85 kW")

        // moving the link clears the old breaker
        BuildingPanels.link(&job, panel: pump.id, to: opts[1].ref)
        XCTAssertEqual(mdpBreakers(job)[0].target, "")
        XCTAssertEqual(mdpBreakers(job)[1].target, "ตู้ไฟฟ้า โรงสูบน้ำ (B1.1)")
        XCTAssertEqual(try module(job, "โรงสูบน้ำ").values.text("breakerAT"), "250")

        // another building taking the same breaker unlinks the first
        let office = try module(job, "อาคารสำนักงาน")
        BuildingPanels.link(&job, panel: office.id, to: opts[1].ref)
        XCTAssertEqual(try module(job, "โรงสูบน้ำ").values.text("a3Breaker"), "")
        XCTAssertEqual(mdpBreakers(job)[1].target, "ตู้ไฟฟ้า อาคารสำนักงาน (B1.3)")

        // rename follows to the target
        BuildingPanels.rename(&job, panel: office.id, to: "สำนักงานใหญ่")
        XCTAssertEqual(mdpBreakers(job)[1].target, "ตู้ไฟฟ้า สำนักงานใหญ่ (B1.3)")

        // deleting the building clears the target
        BuildingPanels.delete(&job, panel: office.id)
        XCTAssertNil(job.modules.first { $0.id == office.id })
        XCTAssertEqual(mdpBreakers(job)[1].target, "")
    }

    func testDaytimeNote() throws {
        let job = SingleLineTests.fixture()
        // โรงสูบน้ำ 85 + อาคารสำนักงาน 22, โรงกรอง missing; B2 has no sizes so PV = A1 120
        let n = try XCTUnwrap(BuildingPanels.daytimeNote(job))
        XCTAssertEqual(n.text, "โหลดกลางวันรวม 107 kW (ยังขาดโรงกรอง) · PV 120 kW → ต้องมีระบบกันย้อน (B4)")
        XCTAssertTrue(n.needsZeroExport)

        // B2 sizes win over A1
        var big = job
        let i = try XCTUnwrap(big.modules.firstIndex { $0.type == .inverter })
        big.modules[i].values["invSizes"] = .text("40,40")
        XCTAssertEqual(BuildingPanels.pvKW(big), 80)
        XCTAssertFalse(try XCTUnwrap(BuildingPanels.daytimeNote(big)).needsZeroExport)
        XCTAssertTrue(try XCTUnwrap(BuildingPanels.daytimeNote(big)).text.hasSuffix("โหลดมากกว่า PV · กันย้อนยังแนะนำตามเงื่อนไข กฟภ."))

        // no load yet: no note
        var empty = job
        for k in empty.modules.indices { empty.modules[k].values["loadKW"] = nil }
        XCTAssertNil(BuildingPanels.daytimeNote(empty))
    }

    func testNowChip() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 5))!
        XCTAssertEqual(BuildingPanels.nowTime(d, calendar: cal), "09:05")
        // old answers still pick their chip
        XCTAssertEqual(BuildingPanels.clockTime("10 น."), "10:00")
        XCTAssertEqual(BuildingPanels.clockTime("9.30"), "09:30")
        XCTAssertEqual(BuildingPanels.clockTime("14:00"), "14:00")
        XCTAssertNil(BuildingPanels.clockTime("ช่วงบ่าย"))
    }

    func testMissingStatus() throws {
        var job = SingleLineTests.fixture()
        let pump = try XCTUnwrap(job.modules.firstIndex { $0.name == "โรงสูบน้ำ" })
        let office = try XCTUnwrap(job.modules.firstIndex { $0.name == "อาคารสำนักงาน" })
        job.modules[pump].values["photoWide"] = .photo(Self.photo)
        job.modules[office].values["photoWide"] = .photo(Self.photo)
        job.modules[office].values["photoBreaker"] = .photo(Self.photo)
        XCTAssertEqual(BuildingPanels.statusLine(job), "ยังขาด: ภาพเบรกเกอร์ โรงสูบน้ำ · โรงกรอง ทั้ง 2 ภาพ · โหลด โรงกรอง")
        for k in job.modules.indices where job.modules[k].type == .panel {
            job.modules[k].values["photoWide"] = .photo(Self.photo); job.modules[k].values["photoBreaker"] = .photo(Self.photo)
            job.modules[k].values["loadKW"] = .text("10")
        }
        XCTAssertEqual(BuildingPanels.statusLine(job), "ครบทุกอาคาร")
    }

    func testSLDPrefersLink() throws {
        var job = SingleLineTests.fixture()
        // a target that names no building: only the link can find it
        var trafos = job.values.transformers("trafos")
        trafos[0].boards[0].breakers[0].target = "ตู้ย่อย"
        job.values["trafos"] = .transformers(trafos)
        func load(_ j: Job) -> [String] {
            SingleLine.build(j).transformers[0].boards[0].breakers.first { $0.number == 1 }?.destination.map(\.text) ?? []
        }
        XCTAssertEqual(load(job).last, "โหลด ? (B1)")
        let pump = try module(job, "โรงสูบน้ำ")
        job.modules[job.modules.firstIndex { $0.id == pump.id }!].values["a3Breaker"] = .text(BuildingPanels.options(job)[0].ref.key)
        XCTAssertEqual(load(job), ["ตู้ไฟฟ้า", "โรงสูบน้ำ", "โหลด 85 kW @10 น."])
        // an unlinked old job still matches by name
        XCTAssertEqual(load(SingleLineTests.fixture()).last, "โหลด 85 kW @10 น.")
    }

    func testOldJobsCountAsBefore() throws {
        let old = SurveyModule(type: .panel, name: "โรงสูบน้ำ",
                               values: Values(["breakerAT": .text("400"), "loadKW": .text("85"), "loadTime": .text("10 น.")]))
        let data = try JSONEncoder().encode(old)
        let back = try JSONDecoder().decode(SurveyModule.self, from: data)
        XCTAssertEqual(back.completion, old.completion)
        // the new fields are optional: filling them changes nothing in the count
        var linked = back
        linked.values["a3Breaker"] = .text("0/\(UUID().uuidString)/\(UUID().uuidString)")
        linked.values["pvPoint"] = .shapes([SiteShape(kind: .pvPoint, points: [ShapePoint(0.1, 0.1), ShapePoint(0.3, 0.3)])])
        linked.values["spareSlots"] = .text("2")
        XCTAssertEqual(linked.completion, old.completion)
        XCTAssertEqual(BuildingPanels.pointLabel(linked.values), "จุดเชื่อมต่อ PV · ช่องว่าง 2 ช่อง")
    }
}

import XCTest
@testable import TCRoofCore

/// Step 1's rules (docs/ui/iec62446-step1-setup-ipad), on the แพรกหนามแดง sample.
final class IECSetupTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    func testSlotsAreMPPTTimesTwo() throws {
        var r = try sample()
        XCTAssertEqual(r.inverters[0].slotsInUse, 20, "no MPPT count: the sheet's 10")
        r.setMPPT(6, inverter: 1)
        XCTAssertEqual(r.inverters[1].slotsInUse, 12)
        XCTAssertEqual(r.inverters[1].strings.count, 8, "the sample's INV 2 strings all sit in slots 1–12")
        // a slot past MPPT × 2 can't be used, and a smaller model empties the slots past it
        r.setSlot(13, used: true, modules: 16, inverter: 1)
        XCTAssertNil(r.inverters[1].slots[12])
        r.setMPPT(4, inverter: 1)
        XCTAssertEqual(r.inverters[1].strings.map(\.slot), [1, 3, 5, 7])
    }

    func testTheTotalsFollowTheToggles() throws {
        var r = try sample()
        XCTAssertEqual(r.setupTotals(r.inverters[0]), .init(used: 16, slots: 20, modules: 256, watts: 145_920))
        r.setSlot(3, used: false, modules: 16, inverter: 0)
        XCTAssertEqual(r.setupTotals(r.inverters[0]), .init(used: 15, slots: 20, modules: 240, watts: 136_800))
        r.setSlot(8, used: true, modules: 12, inverter: 0)
        r.setModules(14, slot: 8, inverter: 0)
        XCTAssertEqual(r.setupTotals(r.inverters[0]).modules, 254)
        r.setModules(0, slot: 8, inverter: 0)
        XCTAssertEqual(r.inverters[0].slots[7]?.modules, 1, "never under 1")
    }

    func testAddAndDeleteRenumber() throws {
        var r = try sample()
        let i = r.addInverter(model: "Growatt MAX 60KTL3 LV", ratedKW: 60, mppt: 6, serial: "SN3", modules: 16, photos: ["front": "f", "nameplate": "n"])
        XCTAssertEqual(i, 2)
        XCTAssertEqual(r.inverters[2].strings.count, 12, "every slot of the model starts used")
        XCTAssertEqual(r.inverters[2].strings.last.map { IECReport.label(inverter: 3, seq: $0.seq) }, "INV3ST12")
        // deleting INV 1 moves the others up and hands back its photos
        r.inverters[0].slots[0]?.photos["voltageBefore"] = "v"
        let gone = r.removeInverter(at: 0)
        XCTAssertEqual(gone, ["v"])
        XCTAssertEqual(r.inverters.map(\.serial), ["BUFUEXB009", "SN3"])
        // the last one stays
        _ = r.removeInverter(at: 0)
        XCTAssertTrue(r.removeInverter(at: 0).isEmpty)
        XCTAssertEqual(r.inverters.count, 1)
    }

    func testNextNeedsTheDiagramDateTesterAndAString() throws {
        var r = try sample()
        XCTAssertEqual(r.setupBlockers, ["แบบ SLD", "วันที่", "ผู้ทดสอบ"])
        r.sld = .init(name: "SLD.pdf", version: 1, at: .now); r.testDate = .now; r.tester = "ก"
        XCTAssertTrue(r.setupBlockers.isEmpty)
        for n in 1...20 { r.setSlot(n, used: false, modules: 0, inverter: 0); r.setSlot(n, used: false, modules: 0, inverter: 1) }
        XCTAssertEqual(r.setupBlockers, ["สตริง"])
    }

    func testOldReportsDecodeWithoutTheNewFields() throws {
        let old = try JSONDecoder().decode(IECReport.self, from: Data(#"{"inverters":[{"ratedKW":60,"slots":[{"modules":16}]}]}"#.utf8))
        XCTAssertNil(old.sld)
        XCTAssertNil(old.inverters[0].mppt)
        XCTAssertNil(old.inverters[0].model)
        XCTAssertTrue(old.inverters[0].photos.isEmpty)
        var r = try sample()
        r.sld = .init(name: "a.pdf", version: 2, at: Date(timeIntervalSinceReferenceDate: 1))
        r.inverters[0].model = "M"; r.inverters[0].mppt = 10; r.inverters[0].photos = ["front": "x"]
        XCTAssertEqual(try JSONDecoder().decode(IECReport.self, from: JSONEncoder().encode(r)), r)
    }

    func testASerialIsReadFromANameplate() {
        XCTAssertEqual(IECReport.serialCandidate(in: "GROWATT\nMAX 125KTL3-X LV\nS/N: GKLRF5N02R\nIP66"), "GKLRF5N02R")
        XCTAssertEqual(IECReport.serialCandidate(in: "Model 60KTL3\nBUFUEXB009"), "BUFUEXB009")
        XCTAssertNil(IECReport.serialCandidate(in: "Fluke 376\n600V"))
    }
}

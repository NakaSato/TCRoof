import XCTest
@testable import TCRoofCore

/// Step 2's rules (docs/ui/iec62446-step2-before-vi-ipad), on the แพรกหนามแดง sample.
final class IECBeforeVITests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    func testTheMedianIsPerModuleCountGroup() throws {
        let r = try sample()
        let inv2 = r.inverters[1]
        // INV 2 has 16- and 12-module strings: each against its own group
        XCTAssertEqual(r.vocMedians(inv2).map(\.modules), [16, 12])
        XCTAssertEqual(r.vocMedians(inv2)[0].median, 753.5, accuracy: 1e-9)
        XCTAssertEqual(r.vocMedians(inv2)[1].median, 560.9, accuracy: 1e-9)
        for s in inv2.strings { XCTAssertEqual(r.beforeVIStatus(inv2, slot: s.slot), .pass, "slot \(s.slot)") }
        XCTAssertEqual(r.vocMedians(r.inverters[0]).map(\.median), [753])
    }

    func testFivePercentPassesAndMoreFails() {
        // three 16-module strings, one per MPPT (slots 1, 3, 5, so ZN-110 has no pair), median 800: 840 is exactly
        // +5 %, 841 is over
        var inv = IECReport.Inverter(slots: [IECReport.Slot(modules: 16, polarityOK: true, vocV: 800, iBeforeA: 0), nil,
                                             IECReport.Slot(modules: 16, polarityOK: true, vocV: 760, iBeforeA: 0), nil,
                                             IECReport.Slot(modules: 16, polarityOK: true, vocV: 840, iBeforeA: 0)])
        let r = IECReport(inverters: [inv])
        XCTAssertEqual(r.vocPasses(inv, slot: 5), true, "exactly 5 % passes")
        XCTAssertEqual(r.beforeVIStatus(inv, slot: 3), .pass, "−5 % too")
        inv.slots[4]?.vocV = 841
        XCTAssertEqual(IECReport(inverters: [inv]).vocPasses(inv, slot: 5), false)
        XCTAssertEqual(IECReport(inverters: [inv]).beforeVIStatus(inv, slot: 5), .fail)
    }

    func testTheSamplesFailingStringSaysWhy() throws {
        var r = try sample()
        r.inverters[0].slots[4]?.vocV = 712
        let inv = r.inverters[0]
        XCTAssertEqual(r.beforeVIStatus(inv, slot: 5), .fail)
        // slot 6 shares MPPT 3 with it: 750 − 712 = 38 V, over ZN-110's 10 V, so both fail
        let pair = "MPPT 3 | Voc 2 สตริงต่างกัน 38.0 V (เกิน 10 V ก่อนต่อขนาน)"
        XCTAssertEqual(r.beforeVIFailures(inv, slot: 5), ["Voc 712.0 V ต่างจากมัธยฐาน −5.4% (เกณฑ์ ±5%)", pair])
        XCTAssertEqual(r.beforeVIFailures(inv, slot: 6), [pair])
        XCTAssertEqual(r.beforeVITally(inv), .init(done: 16, total: 16, failed: 2))
    }

    func testCurrentMustBeZeroBeforeTheConnection() throws {
        var r = try sample()
        XCTAssertTrue(IECReport.currentPassesBefore(0))
        XCTAssertFalse(IECReport.currentPassesBefore(0.01))
        r.inverters[0].slots[0]?.iBeforeA = 0.4
        XCTAssertEqual(r.beforeVIStatus(r.inverters[0], slot: 1), .fail)
        XCTAssertEqual(r.beforeVIFailures(r.inverters[0], slot: 1), ["กระแส 0.40 A | ก่อนออนต้องเป็น 0 A"])
    }

    func testPolarityFollowsTheVocSignUntilSetByHand() throws {
        var r = try sample()
        r.inverters[0].slots[0]?.polarityOK = nil
        r.setVoc(-753, inverter: 0, slot: 1)
        XCTAssertEqual(r.inverters[0].slots[0]?.vocV, 753, "kept as its absolute value")
        XCTAssertEqual(r.inverters[0].slots[0]?.polarityOK, false)
        r.setVoc(754, inverter: 0, slot: 1)
        XCTAssertEqual(r.inverters[0].slots[0]?.polarityOK, true)
        // the segment wins from then on
        r.setPolarity(false, inverter: 0, slot: 1)
        r.setVoc(755, inverter: 0, slot: 1)
        XCTAssertEqual(r.inverters[0].slots[0]?.polarityOK, false)
        XCTAssertEqual(r.beforeVIFailures(r.inverters[0], slot: 1), ["ขั้วสายกลับ"])
        // an empty slot takes nothing
        r.setVoc(700, inverter: 0, slot: 8)
        XCTAssertNil(r.inverters[0].slots[7])
    }

    func testCountsSkipAnEmptySlotInBetween() throws {
        var r = try sample()
        // slot 8 is empty in the sample; clear ST14's values (slot 15)
        r.inverters[0].slots[14]?.vocV = nil
        r.inverters[0].slots[14]?.iBeforeA = nil
        let inv = r.inverters[0]
        XCTAssertEqual(r.beforeVIStatus(inv, slot: 8), .empty)
        XCTAssertEqual(r.beforeVIStatus(inv, slot: 15), .todo)
        XCTAssertEqual(r.beforeVITally(inv), .init(done: 15, total: 16, failed: 0))
    }

    func testLabelsSkipEmptySlotsButColumnsFollowTheSlot() throws {
        let r = try sample()
        let st8 = r.inverters[0].strings.first { $0.seq == 8 }!
        XCTAssertEqual(st8.slot, 9, "INV1ST8 sits in slot 9, after the empty slot 8")
        XCTAssertEqual(IECReport.excelColumn(slot: st8.slot), "M")
        XCTAssertEqual(IECReport.excelColumn(slot: 1), "E")
        XCTAssertEqual(IECReport.excelColumn(slot: 20), "X")
        // the report: 3 strings a page after the cover, INV 2 after INV 1's 16
        XCTAssertEqual(r.reportPage(inverter: 0, seq: 1), 2)
        XCTAssertEqual(r.reportPage(inverter: 0, seq: 14), 6)
        XCTAssertEqual(r.reportPage(inverter: 1, seq: 1), 7)
    }

    func testTheMeterReadingSkipsLabels() {
        XCTAssertEqual(IECReport.meterReading(in: "INV1ST1\nV DC\n755.0"), 755.0)
        XCTAssertEqual(IECReport.meterReading(in: "A DC 0.00"), 0)
        XCTAssertEqual(IECReport.meterReading(in: "-753.0 V"), -753)
        XCTAssertEqual(IECReport.meterReading(in: "MPPT 8 F15 561,2"), 561.2)
        XCTAssertNil(IECReport.meterReading(in: "INV1ST1"))
        XCTAssertTrue(IECReport.differsFromReading(735, 755))
        XCTAssertFalse(IECReport.differsFromReading(756, 755))
    }

    func testOldSlotsDecodeWithoutTheHandFlag() throws {
        let s = try JSONDecoder().decode(IECReport.Slot.self, from: Data(#"{"modules":16,"polarityOK":true}"#.utf8))
        XCTAssertNil(s.polarityByHand)
    }
}

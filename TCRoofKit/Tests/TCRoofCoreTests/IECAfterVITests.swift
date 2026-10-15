import XCTest
@testable import TCRoofCore

/// Step 4's rules (docs/ui/iec62446-step4-after-vi-ipad), on the แพรกหนามแดง sample with Vmp ≈ Voc × 0.815.
final class IECAfterVITests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        var r = try IECReport(form: Data(contentsOf: url))
        for i in r.inverters.indices {
            for n in r.inverters[i].slots.indices where r.inverters[i].slots[n] != nil {
                let voc = r.inverters[i].slots[n]?.vocV ?? 0
                r.inverters[i].slots[n]?.vmpV = (voc * 0.815 * 10).rounded() / 10
                r.inverters[i].slots[n]?.impA = 12.5
            }
        }
        return r
    }

    func testTheVmpMedianIsPerModuleCountGroup() throws {
        let r = try sample()
        XCTAssertEqual(r.vmpMedians(r.inverters[1]).map(\.modules), [16, 12])
        for s in r.inverters[1].strings { XCTAssertEqual(r.viStatus(r.inverters[1], slot: s.slot, .after), .pass) }
    }

    func testFivePercentPassesAndMoreFails() {
        var inv = IECReport.Inverter(slots: [IECReport.Slot(modules: 16, vmpV: 600, impA: 12), IECReport.Slot(modules: 16, vmpV: 570, impA: 12),
                                             IECReport.Slot(modules: 16, vmpV: 630, impA: 12)])
        XCTAssertEqual(IECReport(inverters: [inv]).vmpPasses(inv, slot: 3), true, "exactly +5 %")
        inv.slots[2]?.vmpV = 631
        let r = IECReport(inverters: [inv])
        XCTAssertEqual(r.viStatus(inv, slot: 3, .after), .fail)
        XCTAssertEqual(r.viFailures(inv, slot: 3, .after).first?.hasPrefix("Vmp 631.0 V ต่างจากมัธยฐาน +5.2%"), true)
    }

    func testImpNeverFailsAndDoneNeedsBoth() throws {
        var r = try sample()
        r.inverters[0].slots[0]?.impA = 0
        XCTAssertEqual(r.viStatus(r.inverters[0], slot: 1, .after), .pass, "0 A after the connection isn't a fail here")
        r.inverters[0].slots[1]?.impA = nil
        XCTAssertEqual(r.viStatus(r.inverters[0], slot: 2, .after), .todo)
        XCTAssertEqual(r.viTally(r.inverters[0], .after), .init(done: 15, total: 16, failed: 0))
    }

    func testNoPolarityAfterTheConnection() throws {
        var r = try sample()
        r.inverters[0].slots[0]?.polarityOK = false
        XCTAssertEqual(r.viStatus(r.inverters[0], slot: 1, .after), .pass)
        XCTAssertEqual(r.viStatus(r.inverters[0], slot: 1, .before), .fail)
        r.inverters[0].slots[2]?.polarityOK = nil
        XCTAssertEqual(r.viTally(r.inverters[0], .after).done, 16, "polarity isn't needed after")
    }

    func testAfterPhotosGoAfterTheBeforePart() throws {
        let r = try sample()
        // 24 strings: the before cover and 8 pages, the after cover, then 3 a page
        XCTAssertEqual(r.reportPage(inverter: 0, seq: 1, .after), 11)
        XCTAssertEqual(r.reportPage(inverter: 0, seq: 5, .after), 12)
        XCTAssertEqual(r.reportPage(inverter: 1, seq: 1, .after), 16)
        XCTAssertEqual(r.reportPage(inverter: 0, seq: 1, .before), 2)
    }
}

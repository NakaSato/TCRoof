import XCTest
@testable import TCRoofCore

/// docs/specs/iec62446-excel-export-swift.md §2 and docs/forms/iec62446-pwa §5, on the แพรกหนามแดง sample.
final class IECReportTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    func testTheSampleReadsIntoSlots() throws {
        let r = try sample()
        XCTAssertEqual(r.inverters.count, 2)
        XCTAssertEqual(r.stringCount, 24)
        XCTAssertEqual(r.inverters[0].strings.map(\.slot), [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 17, 19])
        // Word counts the used strings, Excel the slots: INV2ST2 is slot 3, MPPT 2
        let inv2 = r.inverters[1].strings
        XCTAssertEqual(inv2[1].slot, 3)
        XCTAssertEqual(IECReport.label(inverter: 2, seq: inv2[1].seq), "INV2ST2")
        XCTAssertEqual(IECReport.mppt(slot: 3), 2)
        XCTAssertEqual(r.installedKWp, 209.76, accuracy: 1e-9)
        XCTAssertEqual(r.installedKWp(r.inverters[0]), 145.92, accuracy: 1e-9)
        XCTAssertEqual(r.installedKWp(r.inverters[1]), 63.84, accuracy: 1e-9)
        XCTAssertEqual(r.inverters[0].slots[0]?.polarityOK, true)
        XCTAssertEqual(r.inverters[0].slots[0]?.vocV, 755)
        XCTAssertEqual(r.inverters[0].remark, "กำลังผลิตถูกหรี่โดยโหลด")
    }

    /// The app computes Yf and PR from kWp (the form typed 2.93 / 0.69 for INV 1), each step rounded first.
    func testYieldAndPRAreComputedFromRoundedSteps() throws {
        var r = try sample()
        let (a, b) = (r.inverters[0], r.inverters[1])
        XCTAssertEqual(r.dailyKWh(a), 457.15)
        XCTAssertEqual(r.yf(a), 3.13)
        XCTAssertEqual(r.pr(a), 0.74)
        XCTAssertEqual(r.dailyKWh(b), 214.94)
        XCTAssertEqual(r.yf(b), 3.37)
        XCTAssertEqual(r.pr(b), 0.79)
        XCTAssertNil(r.efficiency(a), "no module area yet")
        r.module.areaM2 = 2.58
        XCTAssertEqual(r.efficiency(a), 0.16)
    }

    func testInsulationSummaryAndVocCheck() throws {
        var r = try sample()
        XCTAssertNil(r.irSummary(r.inverters[1]), "the sample has no MΩ readings")
        for (i, s) in r.inverters[1].slots.enumerated() where s != nil {
            r.inverters[1].slots[i]?.irPosMOhm = 250
            r.inverters[1].slots[i]?.irNegMOhm = 300
        }
        XCTAssertEqual(r.irSummary(r.inverters[1]), .normal)
        r.inverters[1].slots[0]?.irNegMOhm = 0.8
        XCTAssertEqual(r.irSummary(r.inverters[1]), .abnormal)

        // 16-module strings are compared with 16-module strings only (INV 2 has 16s and 12s)
        XCTAssertTrue(r.vocOutliers(r.inverters[1]).isEmpty)
        XCTAssertTrue(r.vocOutliers(r.inverters[0]).isEmpty)
        r.inverters[0].slots[8]?.vocV = 800
        XCTAssertEqual(r.vocOutliers(r.inverters[0]), [9])
        XCTAssertGreaterThan(r.vocDeviation(r.inverters[0], slot: 9) ?? 0, 0.05)
    }

    func testPassAndProgress() throws {
        var r = try sample()
        XCTAssertNil(r.passes(r.inverters[0], .before), "IR is still missing")
        XCTAssertEqual(r.passes(r.inverters[0], .after), true)
        XCTAssertEqual(r.passes(r.inverters[0], .after, prThreshold: 0.8), false)

        // the overview of docs/ui/iec62446-test screen 1: 48/120 readings
        XCTAssertEqual(r.readings, .init(48, 120))
        XCTAssertEqual(r.photos, .init(0, 121))
        XCTAssertEqual(r.tally(r.inverters[0], .vocAndCurrent), .init(16, 16))
        XCTAssertEqual(r.missing, [.insulation(strings: 24), .vmpAndImp(strings: 24), .moduleArea, .testRecord(3)])
        r.module.areaM2 = 2.58
        XCTAssertFalse(r.missing.contains(.moduleArea))
    }

    func testStationLineMustNameTheJob() throws {
        var r = try sample()
        XCTAssertTrue(r.namesAnotherStation(than: "โรงงานสยามแพ็คกิ้ง"), "the sample's line names แพรกหนามแดง")
        XCTAssertFalse(r.namesAnotherStation(than: "สถานีจ่ายน้ำแพรกหนามแดง"))
        XCTAssertFalse(r.namesAnotherStation(than: "  "), "a job without a name can't be checked")
        r.sampleName = "แพรกหนามแดง"
        XCTAssertFalse(r.namesAnotherStation(than: "โรงงานสยามแพ็คกิ้ง"), "example data says it's a sample instead")
        XCTAssertEqual(try JSONDecoder().decode(IECReport.self, from: JSONEncoder().encode(r)).sampleName, "แพรกหนามแดง")
    }

    func testOldAndShortJSONStillDecode() throws {
        let empty = try JSONDecoder().decode(IECReport.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.inverters.isEmpty)
        // an inverter saved with fewer slots is padded to 20
        let short = #"{"inverters":[{"ratedKW":60,"slots":[{"modules":16}]}]}"#
        let r = try JSONDecoder().decode(IECReport.self, from: Data(short.utf8))
        XCTAssertEqual(r.inverters[0].slots.count, IECReport.slotCount)
        XCTAssertEqual(r.inverters[0].slots[0]?.irTestV, nil)
        let back = try JSONDecoder().decode(IECReport.self, from: JSONEncoder().encode(try sample()))
        XCTAssertEqual(back, try sample())
    }
}

/// What every IEC screen pays per read and per saved keystroke: the job keeps the report as JSON.
final class IECReportPerformanceTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    func testDecodeAndEncode100Times() throws {
        let data = try JSONEncoder().encode(try sample())
        print("IEC report JSON: \(data.count) bytes")
        measuring([XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100 {
                let r = try! JSONDecoder().decode(IECReport.self, from: data)
                _ = try! JSONEncoder().encode(r)
            }
        }
    }

    func testDerivedValues100Times() throws {
        let r = try sample()
        measuring([XCTClockMetric(), XCTCPUMetric()]) {
            for _ in 0..<100 {
                _ = r.readings; _ = r.photos; _ = r.missing; _ = r.completion
                for inv in r.inverters {
                    _ = r.pr(inv); _ = r.irSummary(inv); _ = r.vocOutliers(inv)
                    for s in inv.strings { _ = r.vocDeviation(inv, slot: s.slot) }
                }
            }
        }
    }
}

#if os(Linux)
// swift-corelibs-xctest has no XCTMetric: time only.
private struct XCTClockMetric {}
private struct XCTCPUMetric {}
private struct XCTMemoryMetric {}
#endif

extension XCTestCase {
    #if os(Linux)
    fileprivate func measuring(_ metrics: [Any], _ block: () -> Void) { measure(block: block) }
    #else
    fileprivate func measuring(_ metrics: [XCTMetric], _ block: () -> Void) { measure(metrics: metrics, block: block) }
    #endif
}

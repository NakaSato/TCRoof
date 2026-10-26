import XCTest
@testable import TCRoofCore

/// Step 2 with the module maker's string test (rules phase 5), on the แพรกหนามแดง sample: Znshine 570 W, 34.3 °C air at
/// 1022 W/m², so the module is about 65 °C by NMOT and 16 modules should read 735.9 V.
final class IECStringTestTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    func testTheSamplePasses() throws {
        let r = try sample()
        XCTAssertEqual(r.catalogModule?.id, "ZXM7-UHLDD144-570")
        XCTAssertEqual(r.stringTestBasis, "แผง 65 °C (ประมาณจาก NMOT 44 °C)")
        for inv in r.inverters {
            XCTAssertTrue(r.stringTest(inv).validation.results.isEmpty)
            for s in inv.strings { XCTAssertNil(r.manualVocWarning(inv, slot: s.slot)) }
        }
        let cell: Double = 34.3 + 24.0 * 1022.0 / 800.0
        let perModule: Double = 51.1 * (1 - 0.0025 * (cell - 25))
        XCTAssertEqual(r.manualVoc(r.inverters[0], slot: 1)!.expectedV, 16 * perModule, accuracy: 1e-9)
        XCTAssertEqual(r.manualVoc(r.inverters[1], slot: 9)!.expectedV, 12 * perModule, accuracy: 1e-9)
    }

    func testAMeasuredModuleTemperature() throws {
        var r = try sample()
        r.before.moduleTempC = 58
        XCTAssertEqual(r.stringTestBasis, "แผง 58 °C (วัด)")
        XCTAssertEqual(r.manualVoc(r.inverters[0], slot: 1)!.expectedV, 16 * 51.1 * (1 - 0.0025 * 33), accuracy: 1e-9)
    }

    func testALowStringWarns() throws {
        var r = try sample()
        r.inverters[0].slots[0]?.vocV = 690
        XCTAssertEqual(r.manualVocWarning(r.inverters[0], slot: 1), "Voc ต่างจากคู่มือแผง −6.2% (คาด 735.9 V | ตรวจจุดต่อสาย)")
        XCTAssertEqual(r.stringTest(r.inverters[0]).validation.results.map(\.id), ["ZN-110", "ZN-132"])
    }

    func testAnotherModuleHasOnlyTheParallelCheck() throws {
        var r = try sample()
        r.module.brand = "Other"
        XCTAssertNil(r.catalogModule)
        XCTAssertNil(r.stringTestBasis)
        XCTAssertNil(r.manualVoc(r.inverters[0], slot: 1))
        r.inverters[0].slots[1]?.vocV = 700
        XCTAssertNotNil(r.parallelFailure(r.inverters[0], slot: 1))
    }

    func testTheModuleTemperatureIsKept() throws {
        var r = try sample()
        r.before.moduleTempC = 58.5
        let back = try JSONDecoder().decode(IECReport.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.before.moduleTempC, 58.5)
        let old = try JSONDecoder().decode(IECReport.Conditions.self, from: Data(#"{"ambientC":30,"irradianceWm2":900,"time":"10:00"}"#.utf8))
        XCTAssertNil(old.moduleTempC)
    }
}

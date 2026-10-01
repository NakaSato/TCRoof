import XCTest
@testable import TCRoofCore

final class PVModuleSpecTests: XCTestCase {
    func testBundledZNShineSeries() throws {
        let s = try XCTUnwrap(PVModuleCatalog.all.first { $0.id == "znshine-zxm7-uhldd144" })
        XCTAssertEqual(s.variants.count, 7)
        XCTAssertEqual(s.mechanical.lengthMm, 2278)
        XCTAssertEqual(s.mechanical.widthMm, 1134)
        XCTAssertEqual(s.mechanical.mountingHoles.first?.pitchAlongLengthMm, 1400)
        XCTAssertEqual(s.defaultRating?.pmaxW, 570)
        XCTAssertEqual(s.limits.maxSystemVoltageV, 1500)
    }

    func testLookupAndKWp() throws {
        let hit = try XCTUnwrap(PVModuleCatalog.variant("zxm7-uhldd144-580"))
        XCTAssertEqual(hit.variant.stc.vocV, 51.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PVModuleCatalog.kWp(panels: 416, variantID: "zxm7-uhldd144-580")), 241.28, accuracy: 0.001)
        XCTAssertNil(PVModuleCatalog.kWp(panels: 10, variantID: "nope"))
    }

    func testColdVocStringSizing() throws {
        let hit = try XCTUnwrap(PVModuleCatalog.variant("zxm7-uhldd144-580"))
        // 51.5 V × (1 + (−0.25 %/°C)(10 − 25)) = 53.43 V → 1100 V inverter takes 20 in series
        XCTAssertEqual(hit.spec.vocAt(cellC: 10, variant: hit.variant), 53.43, accuracy: 0.01)
        XCTAssertEqual(hit.spec.maxModulesPerString(inverterMaxVdc: 1100, variant: hit.variant), 20)
    }
}

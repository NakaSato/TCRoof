import XCTest
@testable import TCRoofCore

final class SteelSectionTests: XCTestCase {
    func kg(_ s: String) throws -> Double { try XCTUnwrap(SteelSection.parse(s), s).kgPerMetre }

    /// Within `pct` % of a published table value.
    func assertNear(_ size: String, _ table: Double, pct: Double = 1, file: StaticString = #filePath, line: UInt = #line) throws {
        let x = try kg(size)
        XCTAssertEqual(x, table, accuracy: table * pct / 100, "\(size): \(x) vs \(table)", file: file, line: line)
    }

    func testLippedChannelsMatchTheTables() throws {
        // มอก. 1228-2561 / JIS G 3350 lip channel table (Ruengrawin Steel catalogue, light-lip-channel.pdf):
        // 100x50x20x3.2 7.007 cm² 5.50 kg/m, 100x50x20x2.3 5.172 cm² 4.06, 75x45x15x2.3 4.137 cm² 3.25,
        // 125x50x20x3.2 6.13, 150x50x20x3.2 6.76, 150x65x20x3.2 7.51
        try assertNear("C-100x50x20x3.2", 5.50)
        try assertNear("C-100x50x20x2.3", 4.06)
        try assertNear("C-75x45x15x2.3", 3.25)
        try assertNear("C-125x50x20x3.2", 6.13)
        try assertNear("C-150x50x20x3.2", 6.76)
        try assertNear("C-150x65x20x3.2", 7.51)
        XCTAssertEqual(try XCTUnwrap(SteelSection.parse("C-100x50x20x3.2")).area, 700.7, accuracy: 0.5, "the table's 7.007 cm²")
        // two channels
        XCTAssertEqual(try kg("2C-150x50x20x3.2"), 2 * (try kg("C-150x50x20x3.2")), accuracy: 1e-9)
        XCTAssertEqual(try kg("C 100x50x20x3.2"), try kg("C-100x50x20x3.2"), accuracy: 1e-9)
    }

    func testTubesMatchTheTables() throws {
        // JIS G 3466 / มอก. 107 square tube: 100x100x3.2 12.13 cm² 9.52 kg/m, 75x75x3.2 7.01, 125x125x4.5 16.6
        try assertNear("□-100x100x3.2", 9.52)
        try assertNear("□-75x75x3.2", 7.01)
        try assertNear("□-125x125x4.5", 16.6)
    }

    func testPipesMatchTheTables() throws {
        // JIS G 3444 / มอก. 107 round pipe: 76.3x3.2 5.77 kg/m, 60.5x2.3 3.30; 34.0x1.6 (1") 1.28, 42.7x2.0 (1¼") 2.01,
        // 48.6x2.3 (1½") 2.63
        try assertNear("Ø-76.3x3.2", 5.77)
        try assertNear("Ø-60.5x2.3", 3.30)
        try assertNear("ท่อกลม Ø1\" หนา 1.6", 1.28)
        try assertNear("ท่อกลม Ø1¼\" หนา 2.0", 2.01)
        try assertNear("ท่อกลม Ø1½\" หนา 2.3", 2.63)
        XCTAssertEqual(try kg("ท่อกลม Ø1 1/4\" หนา 2.0"), try kg("ท่อกลม Ø1¼\" หนา 2.0"), accuracy: 1e-9)
        XCTAssertNil(SteelSection.parse("ท่อกลม Ø7\" หนา 2.0"), "no outside diameter for 7\"")
    }

    func testHAndAnglesMatchTheTables() throws {
        // JIS G 3192 H: 200x100x5.5x8 26.67 cm² 20.9 kg/m, 150x150x7x10 31.5, 100x100x6x8 17.2; I 200x100x7x10 26.0
        try assertNear("H-200x100x5.5x8", 20.9)
        try assertNear("H-150x150x7x10", 31.5)
        try assertNear("H-100x100x6x8", 17.2)
        try assertNear("I-200x100x7x10", 26.0, pct: 3)
        // JIS G 3192 equal angle: 50x50x5 3.77 kg/m, 65x65x6 5.91
        try assertNear("L-50x50x5", 3.77, pct: 2)
        try assertNear("L-65x65x6", 5.91, pct: 2)
    }

    func testWhatIsNotSteelHasNoWeight() {
        for s in ["ไม้ 1\"x8\"", "ไม้ 1½\"x3\"", "ไฟเบอร์ซีเมนต์ 1\"x8\"", "ค.ส.ล. (เดิม)", "ค.ส.ล 0.20x0.40", "T2 ลึก 1.00 ท่อ Ø1\"",
                  "โครงคร่าวเหล็กชุบสังกะสี", "C 10x5x2", "□ 10x10", "H 20x10", "", "-", "ไม่ระบุขนาด", "C-100x50", "C-100x50x20x0",
                  "□-10x10x6", "ตามแบบวิศวกร"] {
            XCTAssertNil(SteelSection.parse(s), s)
        }
    }
}

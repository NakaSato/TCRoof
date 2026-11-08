import XCTest

final class LocalizationTests: XCTestCase {
    private var appBundle: Bundle {
        let testBundle = Bundle(for: LocalizationTests.self)
        // TCRoofTests.xctest is located inside TCRoof.app/PlugIns/
        let appURL = testBundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: appURL) ?? Bundle.main
    }

    func testThaiLocalizationStrings() {
        guard let thPath = appBundle.path(forResource: "th", ofType: "lproj"),
              let thBundle = Bundle(path: thPath) else {
            XCTFail("Failed to find Thai lproj bundle in TCRoof.app at \(appBundle.bundlePath)")
            return
        }

        XCTAssertEqual(thBundle.localizedString(forKey: "หน้าแรก", value: nil, table: nil), "หน้าแรก")
        XCTAssertEqual(thBundle.localizedString(forKey: "บันทึก", value: nil, table: nil), "บันทึก")
        XCTAssertEqual(thBundle.localizedString(forKey: "ยกเลิก", value: nil, table: nil), "ยกเลิก")
        XCTAssertEqual(thBundle.localizedString(forKey: "โครงการ", value: nil, table: nil), "โครงการ")
        XCTAssertEqual(thBundle.localizedString(forKey: "โครงการ PWA", value: nil, table: nil), "โครงการ PWA")
        XCTAssertEqual(thBundle.localizedString(forKey: "ผังติดตั้ง", value: nil, table: nil), "ผังติดตั้ง")
        XCTAssertEqual(thBundle.localizedString(forKey: "แผนก่อสร้าง", value: nil, table: nil), "แผนก่อสร้าง")
    }

    /// The UI is Thai only until every screen is translated: 83 English strings among ~1,400 Thai ones gave a mixed
    /// screen on an English device (CHA-48). The translations are in git history (57c98ee6) for when it is done.
    func testNoPartialEnglishShips() {
        XCTAssertNil(appBundle.path(forResource: "en", ofType: "lproj"),
                     "TCRoof.app has an en.lproj: the UI would mix English and Thai on an English device")
    }
}

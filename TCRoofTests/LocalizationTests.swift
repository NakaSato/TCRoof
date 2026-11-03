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
    }

    func testEnglishLocalizationStrings() {
        guard let enPath = appBundle.path(forResource: "en", ofType: "lproj"),
              let enBundle = Bundle(path: enPath) else {
            XCTFail("Failed to find English lproj bundle in TCRoof.app at \(appBundle.bundlePath)")
            return
        }

        XCTAssertEqual(enBundle.localizedString(forKey: "หน้าแรก", value: nil, table: nil), "Home")
        XCTAssertEqual(enBundle.localizedString(forKey: "บันทึก", value: nil, table: nil), "Save")
        XCTAssertEqual(enBundle.localizedString(forKey: "ยกเลิก", value: nil, table: nil), "Cancel")
        XCTAssertEqual(enBundle.localizedString(forKey: "โครงการ", value: nil, table: nil), "Projects")
        XCTAssertEqual(enBundle.localizedString(forKey: "ลงชื่อเข้าใช้ด้วย Google", value: nil, table: nil), "Sign in with Google")
        XCTAssertEqual(enBundle.localizedString(forKey: "วิศวกรผู้ควบคุมงาน", value: nil, table: nil), "Supervising Engineer")
        XCTAssertEqual(enBundle.localizedString(forKey: "ซิงก์แล้ว", value: nil, table: nil), "Synced")
        XCTAssertEqual(enBundle.localizedString(forKey: "ยังไม่บันทึก", value: nil, table: nil), "Unsaved")
    }
}

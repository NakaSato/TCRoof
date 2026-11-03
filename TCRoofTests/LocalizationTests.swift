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

    func testEnglishLocalizationStrings() {
        guard let enPath = appBundle.path(forResource: "en", ofType: "lproj"),
              let enBundle = Bundle(path: enPath) else {
            XCTFail("Failed to find English lproj bundle in TCRoof.app at \(appBundle.bundlePath)")
            return
        }

        // Navigation & Core
        XCTAssertEqual(enBundle.localizedString(forKey: "หน้าแรก", value: nil, table: nil), "Home")
        XCTAssertEqual(enBundle.localizedString(forKey: "บันทึก", value: nil, table: nil), "Save")
        XCTAssertEqual(enBundle.localizedString(forKey: "ยกเลิก", value: nil, table: nil), "Cancel")
        XCTAssertEqual(enBundle.localizedString(forKey: "โครงการ", value: nil, table: nil), "Projects")
        XCTAssertEqual(enBundle.localizedString(forKey: "ลงชื่อเข้าใช้ด้วย Google", value: nil, table: nil), "Sign in with Google")
        XCTAssertEqual(enBundle.localizedString(forKey: "วิศวกรผู้ควบคุมงาน", value: nil, table: nil), "Supervising Engineer")
        XCTAssertEqual(enBundle.localizedString(forKey: "ซิงก์แล้ว", value: nil, table: nil), "Synced")
        XCTAssertEqual(enBundle.localizedString(forKey: "ยังไม่บันทึก", value: nil, table: nil), "Unsaved")

        // Dashboard & Project Tracking
        XCTAssertEqual(enBundle.localizedString(forKey: "โครงการ PWA", value: nil, table: nil), "PWA Projects")
        XCTAssertEqual(enBundle.localizedString(forKey: "งานติดตั้ง", value: nil, table: nil), "Installation")
        XCTAssertEqual(enBundle.localizedString(forKey: "งานสำรวจ", value: nil, table: nil), "Survey")
        XCTAssertEqual(enBundle.localizedString(forKey: "ผังติดตั้ง", value: nil, table: nil), "Key Plan")
        XCTAssertEqual(enBundle.localizedString(forKey: "แผนก่อสร้าง", value: nil, table: nil), "Construction Plan")
        XCTAssertEqual(enBundle.localizedString(forKey: "คำขอรายสัปดาห์", value: nil, table: nil), "Weekly Requests")
        XCTAssertEqual(enBundle.localizedString(forKey: "ตั้งค่าโครงการ", value: nil, table: nil), "Project Settings")
        XCTAssertEqual(enBundle.localizedString(forKey: "ยังไม่มีแผน MP", value: nil, table: nil), "No MP Plan")
        XCTAssertEqual(enBundle.localizedString(forKey: "เสร็จสมบูรณ์", value: nil, table: nil), "Completed")
        XCTAssertEqual(enBundle.localizedString(forKey: "กำลังดำเนินการ", value: nil, table: nil), "In Progress")

        // Actions & Feedback
        XCTAssertEqual(enBundle.localizedString(forKey: "แตะบนผังเพื่อวาง", value: nil, table: nil), "Tap on plan to place")
        XCTAssertEqual(enBundle.localizedString(forKey: "วางครบทุกจุดแล้ว", value: nil, table: nil), "All points placed")
        XCTAssertEqual(enBundle.localizedString(forKey: "เตรียมข้อมูลบัญชีไม่สำเร็จ", value: nil, table: nil), "Account Setup Failed")
    }
}

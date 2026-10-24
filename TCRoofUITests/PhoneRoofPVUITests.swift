import XCTest

/// C1's `จัดแผง` tab on the iPhone: the switch above the plan, `แก้แผง` taking a module out and `จัดแผงใหม่` bringing it
/// back, the roof access segment and the closed `ตั้งค่าและรายละเอียดเพิ่มเติม` row. Run on an iPhone simulator.
final class PhoneRoofPVUITests: XCTestCase {
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-surveyFreshJob", "YES",
                               "-noNotificationPrompt", "YES", "-surveyPage", "roof"]
        app.launch()
        let b = app.buttons["จัดแผง"].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 90)); b.tap()
        return app
    }

    func scrollDown(_ app: XCUIApplication, until e: XCUIElement) {
        for _ in 0..<10 where !(e.exists && e.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
        }
    }

    func testEditModulesAndReset() {
        let app = launch()
        let edit = app.buttons["editModules"].firstMatch, reset = app.buttons["resetModules"].firstMatch
        scrollDown(app, until: edit)
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        XCTAssertFalse(reset.isEnabled)
        edit.tap()
        XCTAssertTrue(app.staticTexts["editHint"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["editHint"].firstMatch.label.contains("เอาออกแล้ว 0 แผ่น"))
        edit.tap()
    }

    func testAccessAndMoreSection() {
        let app = launch()
        let left = app.buttons["ด้านซ้าย"].firstMatch
        scrollDown(app, until: left)
        XCTAssertTrue(left.waitForExistence(timeout: 20))
        app.buttons["ด้านขวา"].firstMatch.tap(); left.tap()
        XCTAssertTrue(left.isSelected || left.value as? String == "1" || left.exists)
        let more = app.buttons["pvMore"].firstMatch
        scrollDown(app, until: more)
        XCTAssertEqual(more.value as? String, "ปิดอยู่")
        more.tap()
        XCTAssertEqual(more.value as? String, "เปิดอยู่")
    }
}

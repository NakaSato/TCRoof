import XCTest

/// The iPad install tracking page's `Weekly Report` tab (docs/ui/install-tracking-ipad-weekly-report) on the board's
/// example (`-installDemo YES -installTab weekly`, nothing saved), on an iPad simulator:
/// `-only-testing:TCRoofUITests/InstallWeeklyReportUITests`.
final class InstallWeeklyReportUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    override class func setUp() {
        super.setUp()
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-installDemo", "YES",
                               "-installTab", "weekly", "-noNotificationPrompt", "YES"]
        app.launch()
        _ = app.buttons["กลับหน้ารายการงาน"].waitForExistence(timeout: 300)
        app.terminate()
    }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-installDemo", "YES",
                               "-installTab", "weekly", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["กลับหน้ารายการงาน"].waitForExistence(timeout: slow))
        return app
    }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// The rail selects slide 4, whose chip reads `รอข้อมูล` (Friday isn't signed); `ไปแก้` opens `รายงานประจำวัน`.
    func testRailAndFix() {
        let app = launch()
        let tile = app.buttons["สไลด์ 4 งานรายวัน"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        XCTAssertEqual(tile.value as? String, "รอข้อมูล")
        tile.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "สไลด์ 4/", "งานรายวัน")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "รอข้อมูล")).firstMatch.exists)
        let fix = app.buttons.matching(NSPredicate(format: "label == %@", "ไปแก้")).firstMatch
        XCTAssertTrue(fix.exists)
        fix.tap()
        XCTAssertTrue(waitGone(app.buttons["สไลด์ 4 งานรายวัน"]), "ไปแก้ should open รายงานประจำวัน")
    }

    /// `ดาวน์โหลด` shows `.pptx` and `PDF`; `.pptx` opens the sheet and `ปิด` closes it.
    func testDownloadAndPptxSheet() {
        let app = launch()
        let download = app.buttons["ดาวน์โหลด"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()
        let pptx = app.buttons["ดาวน์โหลด .pptx"]
        XCTAssertTrue(pptx.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ดาวน์โหลด PDF"].exists)
        pptx.tap()
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "ปิด")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8), "the .pptx sheet")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Weekly Report สัปดาห์ที่")).firstMatch.exists)
        close.tap()
        XCTAssertTrue(waitGone(app.buttons["ดาวน์โหลด .pptx"]))
    }

    /// With every report signed the send button is on; `‹` moves to the week before, which was sent.
    func testReadyAndPreviousWeek() {
        let app = launch(["-installReportState", "ready"])
        let send = app.buttons["weeklySend"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertTrue(send.isEnabled, "every check passes")
        let week = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "สัปดาห์ที่ ")).firstMatch
        let before = week.label
        app.buttons["สัปดาห์ก่อน"].tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: week)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["ส่งแล้ว · อ่านอย่างเดียว"].waitForExistence(timeout: 5), "the week before was sent")
    }
}

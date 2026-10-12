import XCTest

/// docs/ui/tcroof-home-iphone-v3, on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/PhoneHomeFeedUITests -derivedDataPath <scratch>`.
/// On the demo feed: a filter chip narrows the posts, `รับทราบ` adds the viewer to the count and takes them off again,
/// `แก้แล้ว` and `เปิดอีกครั้ง` swap, and the modules that left the home are on the `เครื่องมือ` tab.
final class PhoneHomeFeedUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeFeed", "demo", "-homeNoAppointments", "YES", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    func testAcknowledgeTogglesTheCount() {
        let app = launch()
        let ack = app.buttons["รับทราบ"].firstMatch
        XCTAssertTrue(ack.waitForExistence(timeout: slow))
        XCTAssertTrue(app.staticTexts["5 คนรับทราบ"].exists)
        ack.tap()
        XCTAssertTrue(app.staticTexts["คุณและอีก 5 คนรับทราบ"].waitForExistence(timeout: 8))
        ack.tap()
        XCTAssertTrue(app.staticTexts["5 คนรับทราบ"].waitForExistence(timeout: 8))
    }

    func testFilterAndIssueRoundTrip() {
        let app = launch()
        let home = app.buttons["งานบ้าน 2"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: slow))
        home.tap()
        XCTAssertTrue(home.isSelected)
        XCTAssertFalse(app.staticTexts["รายงานวันนี้"].exists, "งานบ้าน should hide the PWA daily report")
        let fix = app.buttons["แก้แล้ว"].firstMatch
        XCTAssertTrue(fix.waitForExistence(timeout: 8))
        fix.tap()
        let reopen = app.buttons["เปิดอีกครั้ง"].firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 8))
        reopen.tap()
        XCTAssertTrue(app.buttons["แก้แล้ว"].firstMatch.waitForExistence(timeout: 8))
    }

    func testModulesMovedToTheToolsTab() {
        let app = launch()
        let tools = app.buttons["เครื่องมือวัด"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: slow))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "สแกนอุปกรณ์")).firstMatch.exists)
        tools.tap()
        for title in ["สแกนอุปกรณ์", "บันทึกงานติดตั้ง", "การประปา"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.waitForExistence(timeout: 8), title)
        }
    }
}

import XCTest

/// docs/ui/tcroof-home-iphone-v3, on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/PhoneHomeFeedUITests -derivedDataPath <scratch>`.
/// On the demo feed: a filter chip narrows the posts, `รับทราบ` adds the viewer to the count and takes them off again,
/// `แก้แล้ว` and `เปิดอีกครั้ง` swap, the `เอกสาร` tab opens the document library, and the modules that left the dock
/// are behind the settings sheet's `เครื่องมือวัด` row.
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
        // the issue post starts under the dock: bring its button clear of it first
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        let fix = app.buttons["แก้แล้ว"].firstMatch
        XCTAssertTrue(fix.waitForExistence(timeout: 8))
        fix.tap()
        let reopen = app.buttons["เปิดอีกครั้ง"].firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 8))
        reopen.tap()
        XCTAssertTrue(app.buttons["แก้แล้ว"].firstMatch.waitForExistence(timeout: 8))
    }

    /// A tap on a post's text opens its record, as its link does: the summary opens the install records.
    func testTappingAPostOpensItsRecord() {
        let app = launch()
        let text = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "สรุปวันที่")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: slow))
        text.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["รับทราบ"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 8), .completed, "the tap should push the record over the feed")
    }

    func testDocsTabOpensTheLibrary() {
        let app = launch()
        let docs = app.buttons["เอกสาร"].firstMatch
        XCTAssertTrue(docs.waitForExistence(timeout: slow))
        docs.tap()
        XCTAssertTrue(docs.isSelected)
        XCTAssertTrue(app.staticTexts["คลังเอกสาร"].firstMatch.waitForExistence(timeout: 8))
    }

    func testModulesMovedToSettings() {
        let app = launch()
        let settings = app.buttons["ตั้งค่า"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: slow))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "สแกนอุปกรณ์")).firstMatch.exists)
        // กปภ. is a tab of its own now, not a row
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "กปภ.")).firstMatch.exists)
        settings.tap()
        let done = app.buttons["เสร็จ"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        // `เครื่องมือวัด` is the last row of the settings list: scroll the sheet to it
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        for _ in 0..<4 { from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))) }
        let tools = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "เครื่องมือวัด")).firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 8))
        tools.tap()
        for title in ["แผนก่อสร้าง", "สแกนอุปกรณ์", "บันทึกงานติดตั้ง"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.waitForExistence(timeout: 8), title)
        }
    }
}

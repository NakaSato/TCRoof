import XCTest

/// A complete PWA survey moves to installation from its card, and stays editable (iPad):
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MoveToInstallUITests -derivedDataPath <scratch>`.
/// Each run starts on a new survey filled to 100% (`-surveyCompleteJob YES`, docNo `UITEST-MOVE`).
final class MoveToInstallUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-noNotificationPrompt", "YES", "-surveyHomeTab", "projects", "-surveyHomeType", "all"] + args
        app.launch()
        return app
    }

    /// The card of the test survey.
    func card(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ทดสอบย้ายติดตั้ง")).firstMatch
    }

    func testMoveFromCard() {
        var app = launch(["-surveyCompleteJob", "YES"])
        let c = card(app)
        XCTAssertTrue(c.waitForExistence(timeout: slow))
        XCTAssertTrue(c.label.contains("ย้ายไปงานติดตั้ง"), "a complete survey offers the move: \(c.label)")
        c.tap()
        let move = app.buttons["ย้าย ทดสอบย้ายติดตั้ง ไปงานติดตั้ง"]
        XCTAssertTrue(move.waitForExistence(timeout: 10))
        move.tap()
        // the card turns into an install-phase card: ติดตั้ง, กำลังทำ <the first install step>
        let moved = NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "ติดตั้ง กำลังทำ", "ย้ายไปงานติดตั้ง")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: moved, object: c)], timeout: 10), .completed, c.label)
        XCTAssertFalse(c.label.contains("ล็อก"), "a moved survey isn't locked")

        // after a relaunch the card is still an installation (the move was saved)
        app.terminate()
        app = launch()
        var again = card(app)
        XCTAssertTrue(again.waitForExistence(timeout: slow))
        XCTAssertTrue(again.label.contains("ติดตั้ง กำลังทำ"), again.label)

        // the install overview has it under ยังไม่มีแผน MP (it has no MP plan yet)
        app.terminate()
        app = launch(["-surveyHomeType", "install"])
        let noPlan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ยังไม่มีแผน MP")).firstMatch
        XCTAssertTrue(noPlan.waitForExistence(timeout: slow), "the overview offers ยังไม่มีแผน MP")
        noPlan.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ทดสอบย้ายติดตั้ง")).firstMatch.waitForExistence(timeout: 10),
                      "the moved survey is listed there")
        app.terminate()
        app = launch()
        again = card(app)
        XCTAssertTrue(again.waitForExistence(timeout: slow))

        // and its survey still opens editable, from the card's menu
        again.press(forDuration: 1.2)
        let report = app.buttons["ดูรายงานสำรวจ"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ตรวจรูปทั้งหมด")).firstMatch.waitForExistence(timeout: 15),
                      "the survey editor opens")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "งดแก้ไข")).firstMatch.waitForExistence(timeout: 8))
    }
}

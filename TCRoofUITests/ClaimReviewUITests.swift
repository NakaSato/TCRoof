import XCTest

/// ตรวจใบเบิกของทีม (`ClaimReviewScreen`, calendar-travel-expenses-swift.md §B5) on its demo, as a manager (iPad or
/// iPhone): a waiting month opens with its total and is approved, another is sent back only with a reason, and the
/// manager's own month offers no decision. The demo keeps the decisions in memory.
final class ClaimReviewUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "claimreview", "-claimReviewDemo", "YES", "-role", "manager", "-noNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    func tapFilter(_ app: XCUIApplication, _ prefix: String) {
        let seg = app.segmentedControls["review.filter"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(seg.waitForExistence(timeout: 10))
        seg.tap()
    }

    func testApproveSendBackAndOwnMonth() {
        let app = launch()
        let somchai = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'สมชาย ใจดี'")).firstMatch
        XCTAssertTrue(somchai.waitForExistence(timeout: slow))
        somchai.tap()
        // the month's total from its days and expenses: mileage 1,173.00 + 60 + 800 + 240
        let total = app.staticTexts["review.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 20))
        XCTAssertTrue(total.label.hasSuffix(" บาท"))
        // sending it back needs a reason
        app.buttons["review.return"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["ส่งกลับ"].tap()
        XCTAssertTrue(app.staticTexts["ใส่เหตุผลที่ส่งกลับ"].waitForExistence(timeout: 5))
        // approve it
        app.buttons["review.approve"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["อนุมัติ"].tap()
        XCTAssertTrue(app.staticTexts["อนุมัติแล้ว"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["review.approve"].exists, "an approved month can only be sent back")
        app.navigationBars.buttons.firstMatch.tap()
        tapFilter(app, "อนุมัติแล้ว")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'สมชาย ใจดี'")).firstMatch.waitForExistence(timeout: 10))
        // the one already sent back shows its reason in the list
        tapFilter(app, "ส่งกลับ")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'ไม่ชัด'")).firstMatch.waitForExistence(timeout: 10))
        // the manager's own month
        tapFilter(app, "รออนุมัติ")
        let own = app.buttons.matching(NSPredicate(format: "label CONTAINS '(ของฉัน)'")).firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10))
        own.tap()
        XCTAssertTrue(app.staticTexts["อนุมัติใบเบิกของตัวเองไม่ได้ · ให้ผู้จัดการคนอื่นตรวจ"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["review.approve"].exists)
        XCTAssertFalse(app.buttons["review.return"].exists)
    }
}

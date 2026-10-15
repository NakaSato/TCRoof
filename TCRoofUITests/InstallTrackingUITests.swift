import XCTest

/// The iPad install tracking page's overview end (docs/ui/install-tracking-ipad §C), on an iPad simulator with the board's
/// example: `-only-testing:TCRoofUITests/InstallTrackingUITests`. The KPI cell `ต้องดำเนินการ` opens the open items and a
/// row pushes its screen; a document tile opens its list and a line pushes its screen; back returns to the page.
final class InstallTrackingUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-installDemo", "YES",
                               "-installScrollEnd", "YES", "-noNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    func pageBack(_ app: XCUIApplication) -> XCUIElement { app.buttons["กลับหน้ารายการงาน"] }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Back from a pushed screen (its iPad header's `กลับหน้าหลัก`) to the page.
    func back(_ app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label == %@", "กลับหน้าหลัก")).firstMatch.tap()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: 8), "back should return to the page")
    }

    func testActionsSheetOpensAnItem() {
        let app = launch()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ต้องดำเนินการ")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8))
        cell.tap()
        // the KPI cell's note names the items too: match the sheet's row by its priority chip
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "กลาง", "Weekly Report W40")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the KPI cell should open the open items")
        row.tap()
        XCTAssertTrue(waitGone(pageBack(app)), "an item should push its screen")
        back(app)
        XCTAssertFalse(row.exists, "the sheet should be closed after opening an item")
    }

    func testDocumentTileListsItsItems() {
        let app = launch()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Daily Report")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8))
        tile.tap()
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DR-007")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 8), "the tile should list its reports")
        app.buttons["ปิด"].firstMatch.tap()
        XCTAssertTrue(waitGone(line), "ปิด should close the list")
        tile.tap()
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        line.tap()
        XCTAssertTrue(waitGone(pageBack(app)), "a report should open its daily report")
        back(app)
    }

    func testSitePanelTabs() {
        let app = launch()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let risk = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ความเสี่ยง")).firstMatch
        XCTAssertTrue(risk.waitForExistence(timeout: 8))
        risk.tap()
        XCTAssertTrue(app.staticTexts["จากคำขอรายสัปดาห์นี้"].waitForExistence(timeout: 8), "ความเสี่ยง should list the week's risks")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "แรงงาน")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "สะสม 44 man-day")).firstMatch.waitForExistence(timeout: 8),
                      "แรงงาน should show the crew chart")
    }
}

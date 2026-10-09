import XCTest

/// docs/ui/home-navbar-ipad, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/HomeNavbarUITests -derivedDataPath <scratch>`.
/// The bell and the account button each open their panel and close the other; the search field opens the job search.
final class HomeNavbarUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeDemo", "YES", "-noNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    func bell(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "การแจ้งเตือน")).firstMatch
    }

    /// The panel's close button stands for the open notifications panel (`อ่านทั้งหมด` hides once all are read).
    func notificationsPanel(_ app: XCUIApplication) -> XCUIElement { app.buttons["ปิด"] }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Bell opens the popover; the account button closes it and opens settings.
    func testBellThenAccount() {
        let app = launch()
        let bell = bell(app)
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        XCTAssertTrue(notificationsPanel(app).waitForExistence(timeout: 8), "the bell should open the notifications")

        app.buttons["ตั้งค่าและบัญชี"].tap()
        XCTAssertTrue(waitGone(notificationsPanel(app)), "the account button should close the notifications")
        XCTAssertTrue(app.buttons["เสร็จ"].waitForExistence(timeout: 8), "the account button should open settings")
    }

    /// Bell toggles: a second tap closes the popover.
    func testBellToggles() {
        let app = launch()
        let bell = bell(app)
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        XCTAssertTrue(notificationsPanel(app).waitForExistence(timeout: 8))
        bell.tap()
        XCTAssertTrue(waitGone(notificationsPanel(app)), "a second tap on the bell should close the notifications")
    }

    /// `อ่านทั้งหมด` clears the count: VoiceOver drops `· ใหม่ n` (states/04 hides the badge).
    /// The read state stays on the simulator, so a second run finds everything read already.
    func testAllReadDropsCount() {
        let app = launch()
        let bell = bell(app)
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        let panel = notificationsPanel(app)
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let readAll = app.buttons["อ่านทั้งหมด"]
        if readAll.exists { readAll.tap() }
        panel.tap()
        XCTAssertTrue(waitGone(panel))
        XCTAssertEqual(self.bell(app).label, "การแจ้งเตือน")
    }

    /// The search field opens the survey list with its search field focused.
    func testSearchOpensJobSearch() {
        let app = launch()
        let search = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ค้นหาเลขที่")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: slow))
        search.tap()
        let field = app.textFields["ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the survey list's search should open")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "its search field should be focused")
    }
}

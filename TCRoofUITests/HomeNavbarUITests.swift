import XCTest

/// docs/ui/home-navbar-ipad and docs/ui/tcroof-home-ipad-v2, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/HomeNavbarUITests -derivedDataPath <scratch>`.
/// The bell and the dock's `ตั้งค่า` each open their panel and close the other; the search field opens the job search.
/// The bar has no account button: settings are in the dock.
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

    /// Bell opens the popover; the dock's `ตั้งค่า` closes it and opens settings.
    func testBellThenSettings() {
        let app = launch()
        let bell = bell(app)
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        XCTAssertTrue(notificationsPanel(app).waitForExistence(timeout: 8), "the bell should open the notifications")

        let settings = app.buttons.matching(NSPredicate(format: "label == %@", "ตั้งค่าและบัญชี"))
        XCTAssertEqual(settings.count, 1, "settings should be in the dock only, not in the bar")
        settings.firstMatch.tap()
        XCTAssertTrue(waitGone(notificationsPanel(app)), "the dock's settings button should close the notifications")
        XCTAssertTrue(app.buttons["เสร็จ"].waitForExistence(timeout: 8), "the dock's settings button should open settings")
    }

    /// A dock button opens its tab under the same dock; a screen pushed there covers the dock; `หน้าหลัก` returns.
    /// Every opened tab keeps its own dock (the others are not on screen), so the dock's buttons are matched by
    /// name with `firstMatch` and "the dock is gone" means none of them can be tapped.
    func testDockSwitchesTabs() {
        let app = launch()
        let plan = app.buttons.matching(NSPredicate(format: "label == %@", "แผนงาน"))
        XCTAssertTrue(plan.firstMatch.waitForExistence(timeout: slow))
        XCTAssertTrue(app.staticTexts["ฟีดโครงการ"].exists, "the right column should be the project feed")
        plan.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["แผนก่อสร้าง"].waitForExistence(timeout: 10), "the plan calendar should open")
        let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == true", "แผนงาน"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 8), "the dock should stay, with the plan tab selected")
        func dockShown() -> Bool { selected.allElementsBoundByIndex.contains { $0.isHittable } }
        XCTAssertTrue(dockShown())

        app.buttons["ดูรายการแผนก่อสร้าง"].tap()
        XCTAssertTrue(app.staticTexts["รายการแผนก่อสร้าง"].firstMatch.waitForExistence(timeout: 8) || app.buttons["กลับหน้าหลัก"].firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        XCTAssertFalse(dockShown(), "the dock should be hidden on a pushed screen")
        app.buttons.matching(NSPredicate(format: "label == %@", "กลับหน้าหลัก")).firstMatch.tap()
        sleep(1)
        XCTAssertTrue(dockShown(), "the dock should return on the tab's root")

        app.buttons.matching(NSPredicate(format: "label == %@", "หน้าหลัก")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ฟีดโครงการ"].waitForExistence(timeout: 8), "the home tab should return")
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

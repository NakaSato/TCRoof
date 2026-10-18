import XCTest

/// docs/ui/pwa-solar-survey-iphone-v3, on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/PhonePWAHomeUITests -derivedDataPath <scratch>`.
/// The PWA home sits under the main dock; its nav pushes แผนงาน and selects บำรุงรักษา, the bell opens the
/// notifications, the filter's ประเภทงาน picks the view and ล้าง resets it, a maintenance row opens its station and
/// the settings sheet has ตั้งค่าโครงการ PWA.
final class PhonePWAHomeUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(tab: String = "projects", _ more: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyHomeTab", tab, "-noNotificationPrompt", "YES"] + more
        app.launch()
        return app
    }

    func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    func waitGone(_ element: XCUIElement, _ message: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 8), .completed, message)
    }

    /// The main dock with กปภ. selected; แผนงาน pushes the plan over the dock and comes back.
    func testDockAndPlan() {
        let app = launch()
        let pwa = button(app, "กปภ."), projects = app.buttons["โครงการ"].firstMatch, plan = app.buttons["แผนงาน"].firstMatch
        XCTAssertTrue(pwa.waitForExistence(timeout: slow))
        XCTAssertTrue(pwa.isSelected)
        XCTAssertTrue(app.staticTexts["โครงการ PWA"].exists)
        XCTAssertTrue(projects.isSelected)
        XCTAssertTrue(button(app, "งานบ้าน").exists, "the dock should be the main one")

        plan.tap()
        XCTAssertTrue(app.staticTexts["แผนงาน PWA"].waitForExistence(timeout: 8), "แผนงาน should push the plan page")
        waitGone(pwa, "a pushed screen should cover the dock")
        app.buttons["ย้อนกลับ"].firstMatch.tap()
        XCTAssertTrue(pwa.waitForExistence(timeout: 8))
        XCTAssertTrue(projects.isSelected, "แผนงาน is a link: the segment stays")
    }

    func testBellOpensNotifications() {
        let app = launch()
        let bell = button(app, "การแจ้งเตือน")
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        let close = app.buttons["ปิด"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8), "the bell should open the notifications")
        close.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 8))
    }

    /// ประเภทงาน picks the view and closes the popover; ล้าง goes back to the project list.
    func testFilterTypes() {
        let app = launch(["-surveyHomeDemo", "maintenance"])
        let filter = button(app, "กรอง"), maintenance = app.buttons["บำรุงรักษา"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: slow))
        XCTAssertTrue(filter.label.hasPrefix("กรองและเรียงงาน"))

        filter.tap()
        let row = button(app, "บำรุงรักษา 6 สถานี")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(button(app, "งานทั้งหมด ").exists, "the project list has its status tiles")
        row.tap()
        waitGone(row, "picking a type should close the popover")
        XCTAssertTrue(maintenance.isSelected, "the nav follows the filter's type")
        XCTAssertTrue(filter.label.hasPrefix("กรองงาน: บำรุงรักษา"))

        filter.tap()
        let reset = app.buttons["ล้างตัวกรองและการเรียง"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 8))
        XCTAssertFalse(button(app, "งานทั้งหมด ").exists, "an overview has only ประเภทงาน")
        reset.tap()
        XCTAssertTrue(button(app, "งานทั้งหมด ").waitForExistence(timeout: 8), "ล้าง should return to the project list")
    }

    func testMaintenanceRowOpensItsStation() {
        let app = launch(tab: "maintenance", ["-surveyHomeDemo", "maintenance", "-pwaMaintenanceFilter", "all"])
        let row = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "เปิดหน้าสถานี")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: slow))
        row.tap()
        waitGone(button(app, "กปภ."), "the row should push the station's screen over the dock")
    }

    func testSettingsRow() {
        let app = launch()
        let settings = app.buttons["ตั้งค่า"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: slow))
        settings.tap()
        let row = button(app, "ตั้งค่าโครงการ PWA")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.staticTexts["PWA Setting"].waitForExistence(timeout: 8))
    }

    /// The header's gear button pushes PWA Setting and the back button returns to PWA home.
    func testHeaderSettingsShortcut() {
        let app = launch()
        let gear = app.buttons["pwaHome.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: slow))
        gear.tap()
        XCTAssertTrue(app.staticTexts["PWA Setting"].waitForExistence(timeout: 8))
        let back = app.buttons["ย้อนกลับ"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        back.tap()
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
    }
}

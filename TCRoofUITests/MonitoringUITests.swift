import XCTest

/// `Monitoring ทุกสถานี` (issue #259) on an iPad simulator, from the dock's `Monitor` tab with the board's example
/// fleet (`-monitoringDemo YES`, nothing saved):
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MonitoringUITests -derivedDataPath <scratch>`.
/// The filter narrows the rows, the table turns into cards, `ตั้งค่า Monitoring` saves only a change and only for a
/// manager, and a row opens its station page.
final class MonitoringUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "monitor", "-homeBoard", "YES", "-monitoringDemo", "YES",
                               "-noNotificationPrompt", "YES"] + extra
        app.launchInThai()
        return app
    }

    func row(_ app: XCUIApplication, _ mp: Int) -> XCUIElement { app.buttons["monitoring.row.demo-mp\(mp)"] }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func testFilterAndCards() {
        let app = launch()
        XCTAssertTrue(row(app, 25).waitForExistence(timeout: slow), "the table lists the example stations")
        XCTAssertTrue(app.staticTexts["ต้องดำเนินการ"].exists)
        // the dock's tab counts the stations in alarm or offline (MP 25, MP 44), not the three actions
        XCTAssertTrue(app.buttons["Monitor | ต้องดูแล 2"].firstMatch.exists)

        app.buttons["มีปัญหา 3"].tap()
        XCTAssertTrue(waitGone(row(app, 52)), "a normal station with nothing listed leaves `มีปัญหา`")
        XCTAssertTrue(row(app, 12).exists, "the app's own string check keeps MP 12 under `มีปัญหา`")

        app.buttons["ออฟไลน์ 1"].tap()
        XCTAssertTrue(waitGone(row(app, 25)))
        XCTAssertTrue(row(app, 44).exists)

        app.buttons["การ์ด"].tap()
        XCTAssertTrue(waitGone(row(app, 44)), "cards in place of the table")
    }

    func testSettingsSaveOnlyAChange() {
        let app = launch(["-role", "manager"])
        let open = app.buttons["monitoring.settings"]
        XCTAssertTrue(open.waitForExistence(timeout: slow))
        open.tap()
        let save = app.buttons["monitoring.settings.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertFalse(save.isEnabled, "nothing changed yet")
        app.buttons["10 นาที"].tap()
        XCTAssertTrue(save.isEnabled)
        app.buttons["ยกเลิก"].firstMatch.tap()
        XCTAssertTrue(waitGone(save))
    }

    func testSettingsAreReadOnlyForTheTeam() {
        let app = launch(["-role", "internal"])
        let open = app.buttons["monitoring.settings"]
        XCTAssertTrue(open.waitForExistence(timeout: slow))
        open.tap()
        XCTAssertTrue(app.staticTexts["ดูได้อย่างเดียว · แก้ได้เฉพาะผู้จัดการ"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["monitoring.settings.save"].exists)
    }

    func testARowOpensItsStation() {
        let app = launch()
        let r = row(app, 25)
        XCTAssertTrue(r.waitForExistence(timeout: slow))
        r.tap()
        XCTAssertTrue(waitGone(app.buttons["monitoring.settings"], timeout: 15), "the station page covers the monitoring page")
    }
}

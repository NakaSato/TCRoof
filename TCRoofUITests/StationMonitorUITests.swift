import XCTest

/// `Monitoring สถานี` (CHA-73) on an iPad simulator with the example fleet (`-monitoringDemo YES`, acknowledgements kept
/// in memory only):
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/StationMonitorUITests -derivedDataPath <scratch>`.
/// A row opens the page, every tab opens, the `สถานี` picker switches station in place, an inverter and an alarm are
/// selected, `รับทราบ` lowers the `ประวัติแจ้งเตือน` badge, the compare tab refuses a third unit, and `‹` returns.
final class StationMonitorUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "monitor", "-homeBoard", "YES", "-monitoringDemo", "YES",
                               "-noNotificationPrompt", "YES"] + extra
        app.launchInThai()
        return app
    }

    func tab(_ app: XCUIApplication, _ key: String) -> XCUIElement { app.buttons["station.tab." + key] }

    func testEveryTabStationPickerAndAcknowledge() {
        let app = launch()
        let row = app.buttons["monitoring.row.demo-mp25"]
        XCTAssertTrue(row.waitForExistence(timeout: slow))
        row.tap()
        XCTAssertTrue(tab(app, "ov").waitForExistence(timeout: 15), "the station page opens")
        XCTAssertTrue(app.staticTexts["สถานีผลิตน้ำนครชัยศรี"].exists)
        XCTAssertTrue(app.otherElements["station.flow"].exists || app.staticTexts["การไหลของพลังงาน"].exists)

        for key in ["inv", "log", "mt", "wx", "cmp", "ev", "ov"] {
            tab(app, key).tap()
            XCTAssertTrue(tab(app, key).isSelected, "tab \(key) is selected")
        }

        // an inverter
        tab(app, "inv").tap()
        let inv2 = app.buttons["station.inverter.INV 2"]
        XCTAssertTrue(inv2.waitForExistence(timeout: 5))
        inv2.tap()
        XCTAssertTrue(inv2.isSelected)

        // compare: kW and V are fine, A is a third unit
        tab(app, "cmp").tap()
        let volts = app.buttons["station.compare.metric.R-PHASE VOLTAGE"]
        XCTAssertTrue(volts.waitForExistence(timeout: 5) || app.buttons["แรงดัน"].exists)
        app.buttons["แรงดัน"].firstMatch.tap()
        app.buttons["station.compare.metric.R-PHASE VOLTAGE"].tap()
        app.buttons["กระแส"].firstMatch.tap()
        app.buttons["station.compare.metric.R-PHASE CURRENT"].tap()
        XCTAssertTrue(app.staticTexts["station.compare.note"].label.contains("หน่วยต่างกันได้"))
        XCTAssertFalse(app.buttons["station.compare.metric.R-PHASE CURRENT"].isSelected, "the third unit is refused")

        // an alarm, acknowledged
        tab(app, "ev").tap()
        let badgeBefore = tab(app, "ev").label
        let line = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'station.alarm.demo-mp25'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()
        XCTAssertTrue(line.isSelected)
        let ack = app.buttons["station.alarm.ack"]
        XCTAssertTrue(ack.isEnabled)
        ack.tap()
        XCTAssertFalse(app.buttons["station.alarm.ack"].isEnabled, "acknowledged")
        XCTAssertNotEqual(tab(app, "ev").label, badgeBefore, "the badge goes down")

        // another station in place
        app.buttons["station.picker"].tap()
        let mp44 = app.buttons.matching(NSPredicate(format: "label CONTAINS 'MP 44'")).firstMatch
        XCTAssertTrue(mp44.waitForExistence(timeout: 5))
        mp44.tap()
        XCTAssertTrue(app.staticTexts["สถานีผลิตน้ำสามพราน"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab(app, "log").label.contains("ขาดการติดต่อ"), "an offline station's logger tab says so")

        // back
        app.buttons["station.back"].tap()
        XCTAssertTrue(app.buttons["monitoring.settings"].waitForExistence(timeout: 10))
    }

    func testDebugFlagsOpenAStationOnATab() {
        let app = launch(["-monitoringStation", "12", "-monitoringStationTab", "wx"])
        XCTAssertTrue(tab(app, "wx").waitForExistence(timeout: slow))
        XCTAssertTrue(tab(app, "wx").isSelected)
        XCTAssertTrue(app.staticTexts["สถานีผลิตน้ำบางเลน"].exists)
    }
}

import XCTest

/// The daily report's module checklist (docs/specs/module-install-rules.md §7.3, iPad): with a bolt at 22 N·m the
/// engineer can't sign, and the card and sheet say why (`-dailyModuleDemo YES`, nothing saved).
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/DailyModuleUITests -derivedDataPath <path>`.
final class DailyModuleUITests: XCTestCase {
    func testABlockStopsSignOff() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "daily", "-noNotificationPrompt", "YES", "-role", "manager", "-dailyModuleDemo", "YES"]
        app.launch()
        let card = app.buttons["dailyModuleCheck"]
        XCTAssertTrue(card.waitForExistence(timeout: 90))
        XCTAssertTrue(card.label.contains("ห้าม"), card.label)
        let sign = app.buttons["dailySign"].firstMatch
        XCTAssertTrue(sign.waitForExistence(timeout: 10))
        sign.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "S551-torque")).firstMatch.waitForExistence(timeout: 5),
                      "the toast names the rule")
        XCTAssertFalse(app.navigationBars["ตรวจ & ลงนาม"].waitForExistence(timeout: 2), "no sign sheet")
        card.tap()
        XCTAssertTrue(app.staticTexts["S551-torque"].waitForExistence(timeout: 10), "the sheet lists the block")
    }
}

import XCTest

/// C1 แผงบนหลังคา's installation checks (`-surveyC1 pvrules`, iPad; docs/specs/module-install-rules.md §7.2): the
/// layout's rails sit outside ZNSHINE's clamp zone, and `ใช้ช่วงจับตาม ZNSHINE ในงานนี้` lays them out again inside it.
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/RoofRulesUITests -derivedDataPath <path>`.
final class RoofRulesUITests: XCTestCase {
    func testTheClampZoneButtonMovesTheRails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-noNotificationPrompt", "YES", "-surveyDemo", "YES", "-surveyFreshJob", "YES",
                               "-surveyDemoSection", "YES", "-surveyWideA1", "YES", "-surveyPage", "roof", "-surveyC1", "pvrules"]
        app.launch()
        let zone = app.staticTexts["S553-zone"]
        XCTAssertTrue(zone.waitForExistence(timeout: 90), "the layout's rails are outside the zone")
        XCTAssertTrue(app.staticTexts["ZN-106"].exists, "22 modules at 1100 V is too many")
        let fix = app.buttons["ใช้ช่วงจับตาม ZNSHINE ในงานนี้"]
        XCTAssertTrue(fix.waitForExistence(timeout: 5))
        fix.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: zone)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 30), .completed, "laid out again inside the zone")
        XCTAssertTrue(app.staticTexts["ZN-106"].exists, "the string check stays")
    }
}

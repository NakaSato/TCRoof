import XCTest

/// D1 sub-step 2 with a hardware keyboard on a standard design (`-surveyD1 design`, iPad; docs/specs/standard-designs.md
/// §3.2): Tab selects the next point. Return (ตรงแบบ) and ⌫ (ไม่มีจริง) go through the same `KeyCatcher`, but XCUITest's
/// `typeKey` doesn't deliver them to a view that isn't a text field, so they are checked by hand on a device.
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/TankKeyboardUITests -derivedDataPath <path>`.
final class TankKeyboardUITests: XCTestCase {
    func testTabSelectsTheNextPoint() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-noNotificationPrompt", "YES", "-surveyDemo", "YES", "-surveyFreshJob", "YES",
                               "-surveyDemoSection", "YES", "-surveyWideA1", "YES", "-surveyPage", "tank", "-surveyD1", "design"]
        app.launch()
        let point = { (n: Int) in app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "จุด V\(n) ")).firstMatch }
        // the design state selects V3
        XCTAssertTrue(point(3).waitForExistence(timeout: 90))
        // the first key after launch only wakes the simulated keyboard
        app.typeKey("z", modifierFlags: .command)
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        XCTAssertTrue(point(4).waitForExistence(timeout: 5), "Tab selected the next point")
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        XCTAssertTrue(point(5).waitForExistence(timeout: 5))
    }
}

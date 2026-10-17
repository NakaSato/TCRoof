import XCTest

/// The login page (`LoginView`) on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/LoginUITests -derivedDataPath <scratch>`.
/// `เข้าสู่ระบบไม่ได้?` opens and closes its help, and at the largest text sizes the page scrolls to its footer.
final class LoginUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "login", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func testHelpOpensAndCloses() {
        let app = launch()
        XCTAssertTrue(app.buttons["เข้าสู่ระบบด้วย Google"].waitForExistence(timeout: slow))
        let help = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "เข้าสู่ระบบไม่ได้?")).firstMatch
        let line = app.staticTexts["ต้องต่ออินเทอร์เน็ตตอนเข้าสู่ระบบ"]
        XCTAssertFalse(line.exists)
        help.tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the help should open under the button")
        help.tap()
        XCTAssertTrue(waitGone(line), "a second tap should close the help")
    }

    /// Accessibility L with the help open is taller than the screen: the footer must be reachable by scrolling.
    func testLargeTextScrollsToFooter() {
        let app = launch(["-loginState", "help", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(app.buttons["เข้าสู่ระบบด้วย Google"].waitForExistence(timeout: slow))
        let footer = app.staticTexts["เฉพาะสมาชิกทีม TC Renewable"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        for _ in 0..<4 where !footer.isHittable { app.swipeUp() }
        XCTAssertTrue(footer.isHittable, "the footer should scroll into view")
    }
}

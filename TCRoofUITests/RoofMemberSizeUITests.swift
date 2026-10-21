import XCTest

/// C1's `ขนาดชิ้นส่วน 1–7` on the demo job: each row's picker opens, takes `-` and then its standard size, and the row
/// shows it. `-only-testing:TCRoofUITests/RoofMemberSizeUITests` (iPad or iPhone). On a device this picker crashed a Debug
/// build (its view type nested too deep for the stack), which the simulator's larger stack hides: run it on a device too.
final class RoofMemberSizeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func row(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "เลือกขนาด \(n) ")).firstMatch
    }

    func open(_ app: XCUIApplication, _ n: Int) {
        let r = row(app, n)
        for _ in 0..<6 where !r.isHittable { app.swipeUp() }
        r.tap()
        XCTAssertTrue(app.buttons["ปิด"].firstMatch.waitForExistence(timeout: 5), "row \(n) opens its picker")
    }

    func testPickingMemberSizes() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-surveyPage", "roof", "-noNotificationPrompt", "YES"]
        app.launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: 90), "C1 shows the member rows")
        for n in 1...7 {
            open(app, n)
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "-  (ไม่มี")).firstMatch.tap()
            XCTAssertTrue(row(app, n).waitForExistence(timeout: 5))
            XCTAssertTrue(row(app, n).label.hasSuffix(" -"), "row \(n) shows - : \(row(app, n).label)")
            open(app, n)
            app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", มาตรฐาน")).firstMatch.tap()
            XCTAssertTrue(row(app, n).waitForExistence(timeout: 5))
            XCTAssertFalse(row(app, n).label.hasSuffix(" -") || row(app, n).label.hasSuffix("ยังไม่เลือก"), "row \(n) shows its size")
        }
    }
}

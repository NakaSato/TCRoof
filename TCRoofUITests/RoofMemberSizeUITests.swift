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

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-surveyPage", "roof", "-noNotificationPrompt", "YES"]
        app.launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: 90), "C1 shows the member rows")
        return app
    }

    /// `ขนาดอื่น ›` › a section › a size, then `ระยะห่าง ▾` › a spacing, on row 2.
    func testOtherSizeAndSpacing() {
        let app = launch()
        open(app, 2)
        app.buttons["ขนาดอื่น ›"].firstMatch.tap()
        let group = app.buttons["เหล็ก H / I"].firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5), "ขนาดอื่น › lists the sections")
        group.tap()
        let size = app.buttons["H-150x150x7x10"].firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 5), "a section lists its sizes")
        size.tap()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, 2).label.contains("H-150x150x7x10"), "row 2 shows the other size: \(row(app, 2).label)")
        XCTAssertEqual(app.state, .runningForeground)

        open(app, 2)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ระยะห่าง")).firstMatch.tap()
        let spacing = app.buttons["@1.20M"].firstMatch
        XCTAssertTrue(spacing.waitForExistence(timeout: 5), "the spacing menu opens")
        spacing.tap()
        if app.buttons["ปิด"].firstMatch.waitForExistence(timeout: 2) { app.buttons["ปิด"].firstMatch.tap() }
        let marked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "เลือกขนาด 2 ", "H-150x150x7x10")).firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["H-150x150x7x10 @1.20M"].firstMatch.waitForExistence(timeout: 5), "row 2 shows the spacing")
    }

    /// `ขนาดอื่น ›` › `พิมพ์เอง…`: a typed size, a typed size the steel table can't read, and cancel.
    func testTypedSize() {
        let app = launch()
        for (text, n) in [("C-125x50x20x2.3", 1), ("ไม้เก่า 2x4 ผุ", 5)] {
            open(app, n)
            app.buttons["ขนาดอื่น ›"].firstMatch.tap()
            let typed = app.buttons["พิมพ์เอง…"].firstMatch
            XCTAssertTrue(typed.waitForExistence(timeout: 5))
            typed.tap()
            let field = app.alerts.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "พิมพ์เอง… asks for the size")
            field.tap()
            field.press(forDuration: 1.0)
            if app.menuItems["Select All"].waitForExistence(timeout: 1) { app.menuItems["Select All"].tap() }
            field.typeText(XCUIKeyboardKey.delete.rawValue + text)
            app.alerts.buttons["ตกลง"].tap()
            XCTAssertTrue(row(app, n).waitForExistence(timeout: 5))
            XCTAssertTrue(row(app, n).label.contains(text), "row \(n) shows the typed size: \(row(app, n).label)")
            XCTAssertEqual(app.state, .runningForeground)
        }
        open(app, 3)
        app.buttons["ขนาดอื่น ›"].firstMatch.tap()
        app.buttons["พิมพ์เอง…"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        let before = row(app, 3).label
        app.alerts.buttons["ยกเลิก"].tap()
        XCTAssertEqual(row(app, 3).label, before, "cancel keeps the size")
    }
}

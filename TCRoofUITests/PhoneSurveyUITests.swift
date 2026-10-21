import XCTest

/// Taps through the iPhone survey pages. Run on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath <scratch>`.
/// The app opens straight into a demo job with the DEBUG launch arguments of CLAUDE.md; its first start in the simulator is slow, so waits are long.
final class PhoneSurveyUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(page: String? = nil, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-noNotificationPrompt", "YES"]
            + (page.map { ["-surveyPage", $0] } ?? []) + extra
        app.launch()
        return app
    }

    func button(_ app: XCUIApplication, beginsWith text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// True once `element` is no longer on screen (`waitForExistence` returns at once while it still is).
    func disappears(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// One drag from low on the page to its middle. `swipeUp()` starts at the screen centre, which is the map on A1.
    func scrollUp(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    /// Scrolls up until `element` is on screen and clear of the bottom bar (the page is one long scroll view under it).
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let barTop = app.frame.height - 110
        var n = 0
        while (!element.isHittable || element.frame.maxY > barTop) && n < 12 { scrollUp(app); n += 1 }
        XCTAssertTrue(element.isHittable && element.frame.maxY <= barTop, "\(element) never cleared the bottom bar (frame \(element.frame))")
    }

    // MARK: A1

    /// docs/ui/survey-a1-iphone states 04–06: idle → saved → green outline, and an edit puts it back to idle.
    func testA1SaveButtonStatesAndEditReset() {
        let app = launch()
        let yes = app.buttons["มี"], no = app.buttons["ไม่มี"]
        XCTAssertTrue(no.waitForExistence(timeout: slow))
        // the demo job keeps its answer between runs, so change to whichever one is not chosen
        let other = no.isSelected ? yes : no
        let again = no.isSelected ? no : yes
        other.tap()

        let dirty = app.buttons["บันทึกแบบร่าง | มีการแก้ไขที่ยังไม่ได้บันทึก"]
        XCTAssertTrue(dirty.waitForExistence(timeout: 5), "an edit should mark the draft as unsaved")
        dirty.tap()

        let saved = app.buttons["บันทึกล่าสุดแล้ว | ยังไม่มีการแก้ไขใหม่"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8), "the button should show the saved state")

        again.tap()
        XCTAssertTrue(dirty.waitForExistence(timeout: 5), "editing a field should return the button to idle")
    }

    /// `คัดลอก` copies the station address and then disappears, so it never overwrites an office address.
    func testA1CopyAddressHidesButton() {
        // a new job each run: the copy fills the office address, which would hide the button on the demo job for good
        let app = launch(page: nil, ["-surveyFreshJob", "YES"])
        let copy = app.buttons["คัดลอกที่อยู่สถานี"]
        XCTAssertTrue(copy.waitForExistence(timeout: slow))
        reveal(copy, in: app)
        XCTAssertGreaterThanOrEqual(copy.frame.height, 44, "the copy button should be a 44-pt tap target")
        copy.tap()
        XCTAssertTrue(disappears(copy), "คัดลอก should hide once the office address is filled")
    }

    // MARK: A2

    /// Tapping the picture preview opens the full-screen editor, and "เสร็จ" closes it.
    func testA2PreviewOpensFullScreenEditor() {
        let app = launch(page: "site", ["-surveyAutofill", "fill"])
        let preview = app.buttons["ภาพสถานที่ติดตั้ง"]
        XCTAssertTrue(preview.waitForExistence(timeout: slow))
        preview.tap()
        // the toolbar's full-screen button and the header's "เสร็จ" share this name
        let exit = app.buttons.matching(identifier: "ออกจากเต็มจอ").firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 10))
        exit.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
    }

    // MARK: A3

    /// Adding an outgoing breaker on the main board opens its sheet; "เสร็จ" closes it and the row shows in the list.
    func testA3AddBreakerOpensSheet() {
        let app = launch(page: "electrical", ["-surveyAutofill", "fill"])
        let add = app.buttons["+ เพิ่ม CB ลูกย่อย"]
        XCTAssertTrue(add.waitForExistence(timeout: slow))
        reveal(add, in: app)
        add.tap()
        let delete = app.buttons["ลบ CB ลูกย่อยนี้"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "the breaker sheet should open")
        app.buttons["เสร็จ"].tap()
        XCTAssertTrue(disappears(delete), "เสร็จ should close the sheet")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ยี่ห้อ ?")).firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: single line diagram

    /// The B4 toggle switches between the two choices.
    func testSLDToggleSwitchesBackfeedLevel() {
        let app = launch(page: "sld")
        let low = button(app, beginsWith: "แรงต่ำ")
        let high = button(app, beginsWith: "แรงสูง")
        XCTAssertTrue(low.waitForExistence(timeout: slow))
        high.tap()
        XCTAssertTrue(high.isSelected)
        low.tap()
        XCTAssertTrue(low.isSelected)
    }
}

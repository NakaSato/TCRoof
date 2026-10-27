import XCTest

/// docs/ui/survey-a4-ipad-v2, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/PadA4FloodUITests -derivedDataPath <scratch>`.
/// Starts from a fresh job with `-surveyA4 flooded` (เคย, 80 cm, the default freeboard 50) in the landscape layout.
final class PadA4FloodUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func waitFor(_ e: XCUIElement, label contains: String, timeout: TimeInterval = 10) {
        let p = NSPredicate(format: "label CONTAINS %@", contains)
        wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout)
    }

    /// A typed level moves the result tile, + on the freeboard moves it by 10, and `ไม่เคย` hides the cards.
    func testLevelFreeboardAndNever() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyFreshJob", "YES", "-surveyDemoSection", "YES",
                               "-surveyWideA1", "YES", "-surveyPage", "flood", "-surveyA4", "flooded", "-noNotificationPrompt", "YES"]
        app.launch()

        let result = app.descendants(matching: .any)["a4.result"]
        XCTAssertTrue(result.waitForExistence(timeout: slow))
        waitFor(result, label: "ติดตั้งต่ำสุด 130 ซม.")

        // 95 + 50 = 145, rounded up to 150
        let field = app.textFields["a4.level"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // tap the right end so the deletes clear "80" (a tap in the middle puts the caret first)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "95\n")
        waitFor(result, label: "ติดตั้งต่ำสุด 150 ซม.")
        XCTAssertTrue(result.label.contains("ปัดขึ้นจาก 145"), result.label)

        // the freeboard's + adds 10: 95 + 60 = 155 → 160
        let plus = app.buttons["a4.freeboard.plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        waitFor(result, label: "ติดตั้งต่ำสุด 160 ซม.")

        // the level's − steps back 5: 90 + 60 = 150
        app.buttons["a4.level.minus"].tap()
        waitFor(result, label: "ติดตั้งต่ำสุด 150 ซม.")

        // ไม่เคย: the cards go, and the note uses the same freeboard
        app.buttons["ไม่เคย"].firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        wait(for: [XCTNSPredicateExpectation(predicate: gone, object: result),
                   XCTNSPredicateExpectation(predicate: gone, object: app.staticTexts["จุดที่ได้รับผลกระทบ"]),
                   XCTNSPredicateExpectation(predicate: gone, object: app.staticTexts["ความถี่ | สาเหตุ"])], timeout: 10)
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "ระยะเผื่อจากพื้น 60 ซม.")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
    }
}

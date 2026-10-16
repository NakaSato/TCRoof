import XCTest

/// Time to open each survey page on iPad: the demo job (`-surveyDemo YES`), `ถัดไป` through every step, the time from
/// the tap until the next page's bar is up. Debug build and XCTest's accessibility snapshots make the figures
/// pessimistic; compare pages with each other, not with a release build. The timings go to the test log as
/// `PAGE <ms> <from> → <to>`. iPad simulator: `-only-testing:TCRoofUITests/SurveyPagesPerformanceUITests`.
final class SurveyPagesPerformanceUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func testWalkEveryPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-noNotificationPrompt", "YES"]
        app.launch()
        let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ถัดไป")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: slow), "a page with its bar")
        sleep(2)
        var seen = Set<String>()
        for _ in 0..<24 {
            guard next.exists, next.isEnabled else { break }
            let from = next.label
            guard seen.insert(from).inserted else { break }
            let start = Date()
            next.tap()
            // the next page is up when its bar's ถัดไป names another step (or the last page has none)
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR label != %@", from), object: next)
            XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 30), .completed, "past \(from)")
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            print("PAGE \(ms) \(from) → \(next.exists ? next.label : "(end)")")
        }
        XCTAssertGreaterThan(seen.count, 5, "walked the steps")
    }

    /// Typing on A1: 30 characters into its first text field, one `typeText` per character so each is a keystroke.
    /// Logged as `TYPE <ms per key>`.
    func testTypeOnA1() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-noNotificationPrompt", "YES"]
        app.launch()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: slow))
        field.tap()
        sleep(3)
        let text = Array("ทดสอบความเร็วการพิมพ์ 1234567")
        let start = Date()
        for c in text { app.typeText(String(c)) }
        let ms = Date().timeIntervalSince(start) * 1000 / Double(text.count)
        print("TYPE \(Int(ms)) ms per key over \(text.count) keys")
    }
}

import XCTest

/// C1 on a roof filled from a team design (`-surveyC1 design`, iPad): a skylight dragged on the plan to where it is on
/// site counts as ต่างจากแบบ (docs/specs/standard-designs.md §3.2).
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/RoofDesignDragUITests -derivedDataPath <path>`.
final class RoofDesignDragUITests: XCTestCase {
    func testDraggingASkylightMakesItDiffer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-noNotificationPrompt", "YES", "-surveyDemo", "YES", "-surveyFreshJob", "YES",
                               "-surveyDemoSection", "YES", "-surveyWideA1", "YES", "-surveyPage", "roof", "-surveyC1", "design"]
        app.launch()
        // the design's counts: the purlins already differ
        let counts = { (n: Int) in app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ต่างจากแบบ \(n) |")).firstMatch }
        XCTAssertTrue(counts(1).waitForExistence(timeout: 90))
        // the plan is above the card the demo scrolls to
        let skylight = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "แผ่นใส")).firstMatch
        for _ in 0..<4 where !skylight.isHittable { app.swipeDown() }
        XCTAssertTrue(skylight.isHittable, "a skylight on the plan")
        let from = skylight.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 60, dy: 0)))
        for _ in 0..<4 where !counts(2).exists { app.swipeUp() }
        XCTAssertTrue(counts(2).waitForExistence(timeout: 10), "the moved skylight differs from the design")
    }
}

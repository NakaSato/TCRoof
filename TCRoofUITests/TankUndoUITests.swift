import XCTest

/// D1's `↶ เลิกทำ` (docs/specs/tank-drawing-swift.md §4.3), on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/TankUndoUITests -derivedDataPath <scratch>`.
/// Sub-step 3 of `-surveyD1 layout`: a panel switched off in `แก้แผง` is back after undo and off again after redo.
final class TankUndoUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func testUndoAndRedoAPanelEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-surveyWideA1", "YES",
                               "-surveyPage", "tank", "-surveyD1", "layout", "-noNotificationPrompt", "YES"]
        app.launch()

        let plan = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "ผังแผง ")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: slow))
        // let the seeding settle into its own undo step
        sleep(2)
        let before = plan.label

        app.buttons["แก้แผง"].firstMatch.tap()
        plan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: plan)], timeout: 10)
        let edited = plan.label
        sleep(1)

        app.buttons["เลิกทำ"].firstMatch.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", before), object: plan)], timeout: 10)

        app.buttons["ทำซ้ำ"].firstMatch.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", edited), object: plan)], timeout: 10)
    }
}

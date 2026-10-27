import XCTest

/// docs/ui/survey-a2-ipad-v3, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/PadA2LayoutUITests -derivedDataPath <scratch>`.
/// `-surveyWideA1 YES` gives the landscape layout (the symbol rail left of the picture); `-surveyAutofill fill` gives
/// the fresh job a site picture, so the toolbar and full screen are there. With `TEST_RUNNER_A2_SHOTS=<folder>` the
/// full screen with the panel closed and open is also saved there (`05-fullscreen.png`, `06-fullscreen-buildings.png`).
final class PadA2LayoutUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["A2_SHOTS"] else { return }
        sleep(1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// The rail arms a tool; full screen opens with the building panel closed, the bar's toggle opens it, and
    /// `ออกจากเต็มจอ` returns to the page.
    func testRailAndFullScreenBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyFreshJob", "YES", "-surveyDemoSection", "YES",
                               "-surveyWideA1", "YES", "-surveyPage", "site", "-surveyAutofill", "fill", "-noNotificationPrompt", "YES"]
        app.launch()
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }

        // the rail's tile keeps the grid's label (title + detail) and arms its tool
        let office = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Site Office")).firstMatch
        XCTAssertTrue(office.waitForExistence(timeout: slow))
        XCTAssertFalse(office.isSelected)
        office.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: office)], timeout: 10)
        office.tap()   // disarm again

        // full screen: the panel is closed until the toggle opens it
        let enter = app.buttons["ดูภาพเต็มจอ"].firstMatch
        XCTAssertTrue(enter.waitForExistence(timeout: 15))
        enter.tap()
        let toggle = app.buttons["a2.panelToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(toggle.label.hasPrefix("อาคารในโครงการ"), toggle.label)
        let panel = app.descendants(matching: .any)["a2.modelPanel"]
        XCTAssertFalse(panel.exists)
        shot("05-fullscreen")
        toggle.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertTrue(toggle.isSelected)
        shot("06-fullscreen-buildings")
        toggle.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)], timeout: 10)

        // the bar's pill leaves full screen
        app.buttons["a2.fullExit"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toggle)], timeout: 10)
        XCTAssertTrue(enter.waitForExistence(timeout: 10))
    }
}

import XCTest

/// D1 sub-step 2 on iPad (docs/ui/survey-d1-obstacles-ipad), on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/TankShadeUITests -derivedDataPath <scratch>`.
final class TankShadeUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-surveyWideA1", "YES",
                               "-surveyPage", "tank", "-surveyD1", state, "-noNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    /// `บนหลังคา` with `แถว` on V9: a step of `ห่างผนังบน` moves the whole row (V3 and V10 too) by the same step, and
    /// `เลิกทำ` puts it back.
    func testRowMovesTogetherAndUndoes() throws {
        let app = launch("obstmoverow")
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the two-column sub-step is iPad only")
        func point(_ label: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label + " ")).firstMatch
        }
        let v3 = point("V3"), v10 = point("V10")
        XCTAssertTrue(v3.waitForExistence(timeout: slow))
        XCTAssertTrue(app.buttons["ย้ายพร้อมกัน แถว"].waitForExistence(timeout: 10))
        sleep(2)  // the seeding settles into its own undo step
        let before3 = v3.value as? String ?? "", before10 = v10.value as? String ?? ""

        app.buttons["เพิ่มห่างผนังบน"].firstMatch.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before3), object: v3)], timeout: 10)
        XCTAssertNotEqual(v10.value as? String, before10, "the row moves together")
        sleep(1)

        app.buttons["obstacleUndo"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", before3), object: v3)], timeout: 10)
        XCTAssertEqual(v10.value as? String, before10)
    }
}

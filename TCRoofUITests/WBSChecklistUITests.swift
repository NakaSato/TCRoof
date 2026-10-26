import XCTest

/// A task sheet's `งานย่อย WBS` (docs/specs/project-plan-wbs.md, step 2), on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/WBSChecklistUITests -derivedDataPath <scratch>`.
/// `-installWBS YES` gives the first installing station the first plan file's (P3-001) rows with no ticks; `-installStage 1` opens
/// its first task's sheet. A sub-task is ticked and taken back, so the station ends with no ticks.
final class WBSChecklistUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func testTickAndTakeBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-installOpen", "YES", "-installWBS", "YES",
                               "-installStage", "1", "-noNotificationPrompt", "YES"]
        app.launch()

        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wbs.")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: slow), "the task sheet should list its WBS sub-tasks")
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "งานย่อย WBS 0/")).firstMatch
        XCTAssertTrue(count.exists, "nothing ticked yet")
        XCTAssertEqual(first.value as? String, "ยังไม่เสร็จ")

        first.tap()
        let one = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "งานย่อย WBS 1/")).firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 5), "the tick should count")
        XCTAssertEqual(first.value as? String, "เสร็จแล้ว")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "เสร็จ ")).firstMatch.exists,
                      "the row should say when it was done")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "wbs-checklist"; shot.lifetime = .keepAlways
        add(shot)

        first.tap()
        XCTAssertTrue(count.waitForExistence(timeout: 5), "taking it back should uncount it")
        XCTAssertEqual(first.value as? String, "ยังไม่เสร็จ")
    }
}

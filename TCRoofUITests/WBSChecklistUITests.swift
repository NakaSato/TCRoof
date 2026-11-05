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

    func testInternalCanEditWBSSubtask() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-installOpen", "YES", "-installWBS", "YES",
                               "-installStage", "1", "-role", "internal", "-noNotificationPrompt", "YES"]
        app.launch()

        let editButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wbs.edit.")).firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: slow), "internal role should see WBS edit button")
        editButton.tap()

        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "แก้ไข WBS")).firstMatch.waitForExistence(timeout: 5),
                      "tapping edit button should open WBSItemEditSheet")
        let cancel = app.buttons["wbsEdit.cancel"]
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        } else if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.buttons["ยกเลิก"].tap()
        }
    }

    func testExternalCanOpenDialogToUpdateWBS() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-installOpen", "YES", "-installWBS", "YES",
                               "-installStage", "1", "-role", "external", "-noNotificationPrompt", "YES"]
        app.launch()

        let updateButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wbs.update.")).firstMatch
        XCTAssertTrue(updateButton.waitForExistence(timeout: slow), "external role should see WBS update button")
        updateButton.tap()

        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "อัปเดต WBS")).firstMatch.waitForExistence(timeout: 5),
                      "tapping update button should open WBSTickUpdateSheet")
        let docField = app.textFields["wbsTick.document"]
        if docField.waitForExistence(timeout: 3) {
            docField.tap()
            docField.typeText("MOM-001")
        }
        app.buttons["wbsTick.save"].tap()

        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "งานย่อย WBS 1/")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "saving update should tick WBS item")
    }
}

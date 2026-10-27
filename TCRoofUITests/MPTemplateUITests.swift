import XCTest

/// ตั้งค่าแผน's `เริ่มจากแม่แบบ` on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MPTemplateUITests -derivedDataPath <scratch>`.
/// From an empty plan (`-mpClear YES`), station P3-028 (LV, ≥ 200 kVA), found by search, becomes the first job's plan moved
/// to its kickoff, with its file kept for export; the second test starts it from an install case (`แม่แบบตามกรณี`, LV,
/// ≥ 200 kVA). The first job keeps the last plan.
final class MPTemplateUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    /// The picked case, as `LabeledContent` reads it (its code and title in one label).
    func caseShown(_ app: XCUIApplication, _ code: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", code)).firstMatch
    }

    func testStartFromATemplate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        let setup = app.buttons["ตั้งค่าแผน"].firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: slow), "an empty plan should offer ตั้งค่าแผน")
        setup.tap()
        let template = app.buttons["mpSetup.template"].firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 10), "ตั้งค่าแผน should offer the templates")
        template.tap()

        // the stations show once their files are read; search finds P3-028
        XCTAssertTrue(app.buttons["mpTemplate.row.P3-001"].firstMatch.waitForExistence(timeout: 20), "the stations should load")
        let search = app.textFields["mpTemplate.search"].firstMatch
        search.tap()
        search.typeText("P3-028")
        let row = app.buttons["mpTemplate.row.P3-028"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "search should find P3-028")
        XCTAssertFalse(app.buttons["mpTemplate.row.P3-001"].firstMatch.exists, "the others are filtered out")
        row.tap()
        XCTAssertTrue(caseShown(app, "P3-028").waitForExistence(timeout: 5), "the plan should be P3-028's")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "template-sheet"; shot.lifetime = .keepAlways
        add(shot)

        app.buttons["mpTemplate.apply"].firstMatch.tap()
        // back on ตั้งค่าแผน with the template's file and its 18 tasks
        let fromFile = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "แม่แบบ P3-028")).firstMatch
        XCTAssertTrue(fromFile.waitForExistence(timeout: 30), "the plan should come from the template's file")
        XCTAssertTrue(app.buttons["mpSetup.task.1.5"].firstMatch.exists, "พค.2 is in a ≥ 200 kVA plan")
        app.buttons["บันทึก"].firstMatch.tap()

        // the plan screen: the file can be exported
        let menu = app.buttons["ไฟล์ Excel"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the plan should show")
        menu.tap()
        let export = app.buttons["ส่งออกไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(export.isEnabled, "the template's file should be kept for export")
    }

    /// `แม่แบบตามกรณี`: the demo station has no file of its own, so the sheet opens on the case its facts point to; the
    /// pickers change it, and the case becomes the plan moved to the kickoff (the file's name says which case).
    func testStartFromAnInstallCase() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        let setup = app.buttons["ตั้งค่าแผน"].firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: slow), "an empty plan should offer ตั้งค่าแผน")
        setup.tap()
        app.buttons["mpSetup.template"].firstMatch.tap()

        // a case is picked from the start; LV and ≥ 200 kVA pick the matching one
        XCTAssertTrue(caseShown(app, "P9-0").waitForExistence(timeout: 20), "the station without a file should start on a case")
        app.segmentedControls["mpTemplate.caseBackfeed"].buttons["กันย้อน LV"].tap()
        app.segmentedControls["mpTemplate.caseSize"].buttons["ตั้งแต่ 200 kVA (พค.2)"].tap()
        let shown = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                                          "กันย้อน LV", "≥ 200 kVA")).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "the case should follow the pickers")
        XCTAssertFalse(app.switches["mpTemplate.keepFile"].firstMatch.isEnabled, "a case always moves to the kickoff")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "case-section"; shot.lifetime = .keepAlways
        add(shot)

        app.buttons["mpTemplate.apply"].firstMatch.tap()
        let fromFile = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "แม่แบบ P9-0")).firstMatch
        XCTAssertTrue(fromFile.waitForExistence(timeout: 30), "the plan should come from the case's file")
        XCTAssertTrue(app.buttons["mpSetup.task.1.5"].firstMatch.exists, "พค.2 is in a ≥ 200 kVA plan")
    }
}

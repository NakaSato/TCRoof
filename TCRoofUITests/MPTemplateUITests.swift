import XCTest

/// ตั้งค่าแผน's `เริ่มจากแม่แบบ` on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MPTemplateUITests -derivedDataPath <scratch>`.
/// From an empty plan (`-mpClear YES`), the ถังน้ำใส · LV · ≥ 200 kVA case (P9-012) becomes the first job's plan, with
/// its file kept for export. The first job keeps that plan.
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

        // the first case shows once the templates are read; then ถังน้ำใส · LV · ≥ 200 kVA
        XCTAssertTrue(caseShown(app, "P9-001").waitForExistence(timeout: 15), "the templates should load")
        app.buttons["mpTemplate.site"].firstMatch.tap()
        let tank = app.buttons["ถังน้ำใส"].firstMatch
        XCTAssertTrue(tank.waitForExistence(timeout: 5), "the site menu should list ถังน้ำใส")
        tank.tap()
        app.buttons["LV"].firstMatch.tap()
        app.buttons["ตั้งแต่ 200 kVA"].firstMatch.tap()
        XCTAssertTrue(caseShown(app, "P9-012").waitForExistence(timeout: 5), "the case should be P9-012")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "template-sheet"; shot.lifetime = .keepAlways
        add(shot)

        app.buttons["mpTemplate.apply"].firstMatch.tap()
        // back on ตั้งค่าแผน with the template's file and its 18 tasks
        let fromFile = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "แม่แบบ P9-012")).firstMatch
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
}

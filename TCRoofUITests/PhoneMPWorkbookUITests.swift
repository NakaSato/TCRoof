import XCTest

/// A station's plan file on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/PhoneMPWorkbookUITests -derivedDataPath <scratch>`.
/// The same flags as `MPWorkbookUITests` stand in for the file picker. With `TEST_RUNNER_MP_SHOTS=<folder>` each screen
/// is also saved there as a PNG, for checking the layouts. The first job keeps the imported plan.
final class PhoneMPWorkbookUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TCRoofKit/Tests/ExcelExportTests/Fixtures/mp-weekly-bangsai.xlsx").standardized
    }
    let exported = URL(fileURLWithPath: "/private/tmp/TCRoofUITests-phone-mp-export.xlsx")

    func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MP_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// Import with the station warning, edit a task's weight, book a week, export through the toolbar menu.
    func testImportEditBookAndExport() throws {
        try? FileManager.default.removeItem(at: exported)
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-mpWeek", "2024-11-03",
                               "-mpImportFile", fixture.path, "-mpExportFile", exported.path, "-noNotificationPrompt", "YES"]
        app.launch()

        let importButton = app.buttons["นำเข้าไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: slow), "an empty plan should offer the import")
        shot("1-empty")
        importButton.tap()
        let confirm = app.alerts["ไฟล์นี้อาจเป็นของสถานีอื่น"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        shot("2-warning")
        confirm.buttons["นำเข้าที่สถานีนี้"].tap()
        XCTAssertTrue(app.staticTexts["ทำได้ 0%"].firstMatch.waitForExistence(timeout: 10))
        shot("3-plan")

        // ตั้งค่าแผน › 2.3's weight
        app.buttons["ตั้งค่าแผน"].firstMatch.tap()
        let row = app.buttons["mpSetup.task.2.3"]
        if !row.waitForExistence(timeout: 5) { app.swipeUp() }
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        shot("4-setup")
        row.tap()
        let weight = app.textFields["mpTask.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        shot("5-task")
        weight.tap()
        weight.doubleTap()
        weight.typeText("12")
        app.buttons["ตกลง"].tap()
        app.buttons["บันทึก"].firstMatch.tap()

        // book the week of 3 พ.ย. 2567
        let update = app.buttons["อัปเดต"].firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 10))
        update.tap()
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        for _ in 0..<4 { stepper.buttons.element(boundBy: 1).tap() }
        shot("6-progress")
        app.buttons["บันทึก"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ทำได้ 0.6%"].firstMatch.waitForExistence(timeout: 10), "20% of 1.4's 3 points")

        // export from the toolbar's menu
        app.buttons["ไฟล์ Excel"].firstMatch.tap()
        let export = app.buttons["ส่งออกไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        shot("7-menu")
        export.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30))
        shot("8-share")
        let data = try Data(contentsOf: exported)
        XCTAssertEqual(data.prefix(2), Data("PK".utf8))
    }
}

import XCTest

/// A station's plan file through แผนงาน MP, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MPWorkbookUITests -derivedDataPath <scratch>`.
/// `-mpClear YES` starts the first job with no plan; `-mpImportFile` hands the import the package's fixture (the picker
/// can't be driven) and `-mpExportFile` copies the export where the test reads it. The first job keeps the imported plan.
final class MPWorkbookUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TCRoofKit/Tests/ExcelExportTests/Fixtures/mp-weekly-bangsai.xlsx").standardized
    }
    let exported = URL(fileURLWithPath: "/private/tmp/TCRoofUITests-mp-export.xlsx")

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Import the file on an empty plan, book progress in one of its weeks, export: the share sheet opens with the
    /// file, which is the original with the progress written in.
    func testImportBookAndExport() throws {
        try? FileManager.default.removeItem(at: exported)
        let original = try Data(contentsOf: fixture)
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-mpWeek", "2024-11-03",
                               "-mpImportFile", fixture.path, "-mpExportFile", exported.path, "-noNotificationPrompt", "YES"]
        app.launch()

        // import from the empty plan
        let importButton = app.buttons["นำเข้าไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: slow), "an empty plan should offer the import")
        importButton.tap()
        // the demo job isn't บางไทร: the import warns, names both, and still lets it in here
        let confirm = app.alerts["ไฟล์นี้อาจเป็นของสถานีอื่น"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "a file for another station should warn first")
        XCTAssertTrue(confirm.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ไฟล์: สถานีผลิตน้ำประปาบางไทร")).firstMatch.exists)
        XCTAssertTrue(confirm.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "18 งาน")).firstMatch.exists)
        confirm.buttons["นำเข้าที่สถานีนี้"].tap()

        // the file's own weights (2.4 Firefighter switch 7.5) and nothing done yet
        XCTAssertTrue(app.staticTexts["7.5%"].firstMatch.waitForExistence(timeout: 10), "the plan should take the file's weights")
        let nothingDone = app.staticTexts["ทำได้ 0%"].firstMatch
        XCTAssertTrue(nothingDone.waitForExistence(timeout: 5))

        // book the week of 3 พ.ย. 2567: the first task planned then up 20%
        app.buttons["อัปเดตสัปดาห์ที่เลือก"].firstMatch.tap()
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "the week should have tasks to book")
        let increment = stepper.buttons.element(boundBy: 1)
        for _ in 0..<4 { increment.tap() }
        app.buttons["บันทึก"].firstMatch.tap()
        XCTAssertTrue(waitGone(nothingDone), "the booked progress should show")

        // export: the share sheet, and the file with the progress written in
        let menu = app.buttons["ไฟล์ Excel"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let export = app.buttons["ส่งออกไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5), "the menu should offer the export")
        export.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30),
                      "the export should open the share sheet")
        let data = try Data(contentsOf: exported)
        XCTAssertEqual(data.prefix(2), Data("PK".utf8), "an .xlsx package")
        XCTAssertNotEqual(data, original, "the progress should be written into the file")
    }

    /// ตั้งค่าแผน on an imported plan: 2.3's weight goes from 10 to 12, the total shows it's off 100, and the plan and the
    /// exported file take it (the test run reads E33 = 12 in the copied export).
    func testEditOneImportedTask() throws {
        try? FileManager.default.removeItem(at: exported)
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-mpWeek", "2024-11-03",
                               "-mpImportFile", fixture.path, "-mpExportFile", exported.path, "-noNotificationPrompt", "YES"]
        app.launch()
        let importButton = app.buttons["นำเข้าไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: slow))
        importButton.tap()
        app.alerts["ไฟล์นี้อาจเป็นของสถานีอื่น"].buttons["นำเข้าที่สถานีนี้"].tap()

        let setup = app.buttons["ตั้งค่าแผน"].firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        setup.tap()
        let row = app.buttons["mpSetup.task.2.3"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "an imported plan's tasks should open their editor")
        row.tap()
        let weight = app.textFields["mpTask.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        // a double tap selects the old value, the typing replaces it
        weight.tap()
        weight.doubleTap()
        weight.typeText("12")
        XCTAssertEqual(weight.value as? String, "12")
        app.buttons["ตกลง"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "รวมน้ำหนัก 102%")).firstMatch.waitForExistence(timeout: 5),
                      "the total should show the change")
        app.buttons["บันทึก"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["12%"].firstMatch.waitForExistence(timeout: 10), "the plan should take the new weight")

        app.buttons["ไฟล์ Excel"].firstMatch.tap()
        app.buttons["ส่งออกไฟล์แผน (Excel)"].firstMatch.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
    }

    /// The app's own export comes back unedited after the app booked 20% more: รับเฉพาะความก้าวหน้า finds nothing changed
    /// in the file since the export (the record it keeps), so the later booking stays, and the plan stays.
    func testReimportTakesOnlyTheProgress() throws {
        try? FileManager.default.removeItem(at: exported)
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-mpWeek", "2024-11-03",
                               "-mpImportFile", fixture.path, "-mpExportFile", exported.path, "-noNotificationPrompt", "YES"]
        app.launch()
        let importButton = app.buttons["นำเข้าไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: slow))
        importButton.tap()
        app.alerts["ไฟล์นี้อาจเป็นของสถานีอื่น"].buttons["นำเข้าที่สถานีนี้"].tap()

        let done = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ทำได้ ")).firstMatch
        func book() {
            // a copy of the screen can sit off screen while a sheet closes: tap the one on screen
            var update: XCUIElement?
            for _ in 0..<20 where update == nil {
                update = app.buttons.matching(identifier: "อัปเดตสัปดาห์ที่เลือก").allElementsBoundByIndex.first { $0.isHittable }
                if update == nil { usleep(500_000) }
            }
            XCTAssertNotNil(update, "the update button should be on screen")
            update?.tap()
            let stepper = app.steppers.firstMatch
            XCTAssertTrue(stepper.waitForExistence(timeout: 10))
            for _ in 0..<4 { stepper.buttons.element(boundBy: 1).tap() }
            app.buttons["บันทึก"].firstMatch.tap()
        }
        book()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let exportedFigure = done.label
        app.buttons["ไฟล์ Excel"].firstMatch.tap()
        app.buttons["ส่งออกไฟล์แผน (Excel)"].firstMatch.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))

        // the app moves on; then the exported copy comes back
        app.terminate()
        app.launchArguments = ["-screen", "mp", "-mpWeek", "2024-11-03", "-mpImportFile", exported.path, "-noNotificationPrompt", "YES"]
        app.launch()
        XCTAssertTrue(done.waitForExistence(timeout: slow))
        book()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", exportedFigure), object: done)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "the second booking should move the figure")
        let appFigure = done.label

        app.buttons["ไฟล์ Excel"].firstMatch.tap()
        app.buttons["นำเข้าไฟล์แผน (Excel)…"].firstMatch.tap()
        // the export wrote this station into the file's PROJECT line (`ProjectSetup`), so it no longer warns that the
        // file is another station's; either confirmation offers รับเฉพาะความก้าวหน้า
        let confirm = app.alerts.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ไม่มีช่องที่เปลี่ยนตามไฟล์")).firstMatch.exists,
                      "the confirmation should say the file wasn't changed since the export")
        confirm.buttons["รับเฉพาะความก้าวหน้า"].tap()
        let report = app.alerts["รับความก้าวหน้าแล้ว"]
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        report.buttons["ตกลง"].tap()
        let kept = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", appFigure), object: done)
        XCTAssertEqual(XCTWaiter().wait(for: [kept], timeout: 5), .completed, "the booking made after the export should stay")
        XCTAssertTrue(app.staticTexts["7.5%"].firstMatch.exists, "the plan's weights stay")
    }
}

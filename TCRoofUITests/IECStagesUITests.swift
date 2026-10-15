import XCTest

/// The IEC test's steps keep their result: confirmed steps and the closed test survive a relaunch, a closed test is
/// read only until `แก้ไข`. iPad simulator: `-only-testing:TCRoofUITests/IECStagesUITests`. It replaces the first
/// installing station's test with the full sample (`-iecDemo full`: every step done, none confirmed).
final class IECStagesUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES"] + extra
        app.launch()
        return app
    }

    func gone(_ e: XCUIElement, _ what: String) {
        let x = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        XCTAssertEqual(XCTWaiter.wait(for: [x], timeout: 10), .completed, what)
    }

    /// `TEST_RUNNER_IEC_SHOTS=<folder>` on xcodebuild keeps the states as PNGs there (for docs/ui/iec62446-test/screenshots).
    func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["IEC_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func confirmed(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ยืนยันแล้ว"))
    }

    func testStepsAndTheResultSurviveARelaunch() {
        var app = launch(["-iecDemo", "full"])
        let first = app.buttons["ยืนยันขั้น ตั้งค่าระบบ"]
        XCTAssertTrue(first.waitForExistence(timeout: slow), "every step is done, none confirmed")
        first.tap()
        app.buttons["ยืนยันขั้น ก่อนออน · แรงดัน / กระแส"].tap()
        XCTAssertTrue(confirmed(app).element(boundBy: 1).waitForExistence(timeout: 10))

        // the confirmations are kept
        app.terminate()
        app = launch()
        XCTAssertTrue(confirmed(app).firstMatch.waitForExistence(timeout: slow), "kept after a relaunch")
        XCTAssertEqual(confirmed(app).count, 2)
        app.swipeUp()
        shot("steps-confirmed")
        XCTAssertFalse(app.buttons["ยืนยันขั้น ตั้งค่าระบบ"].exists)

        // เสร็จ closes the test and confirms the rest
        let finish = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "เสร็จ")).firstMatch
        XCTAssertTrue(finish.isEnabled)
        finish.tap()
        XCTAssertTrue(app.staticTexts["ปิดการทดสอบแล้ว · แก้ไขไม่ได้"].waitForExistence(timeout: 10))
        gone(app.buttons["ยืนยันขั้น ก่อนออน · ฉนวน (IR)"], "closing confirms every step")

        // still closed after a relaunch, and the string table is read only
        app.terminate()
        app = launch()
        XCTAssertTrue(app.staticTexts["ปิดการทดสอบแล้ว · แก้ไขไม่ได้"].waitForExistence(timeout: slow), "the result is kept")
        sleep(1); shot("test-closed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ตั้งค่า")).firstMatch.exists, "no set-up on a closed test")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ก่อนการเชื่อมต่อระบบ")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ปิดการทดสอบแล้ว · ดูได้อย่างเดียว")).firstMatch
            .waitForExistence(timeout: 10), "the table says it's read only")
        shot("table-read-only")
        app.buttons["กลับ"].firstMatch.tap()

        // แก้ไข reopens it
        let edit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "แก้ไข")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        app.sheets.buttons["แก้ไข"].firstMatch.exists ? app.sheets.buttons["แก้ไข"].firstMatch.tap()
            : app.buttons.matching(NSPredicate(format: "label == %@", "แก้ไข")).element(boundBy: 1).tap()
        gone(app.staticTexts["ปิดการทดสอบแล้ว · แก้ไขไม่ได้"], "reopened")
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
    }

    /// A reading typed on the pad is kept when the app goes to the background and is closed there (no ถัดไป). The
    /// after phase's pad (the before phase is step 2's page on iPad, `IECStep2UITests`).
    func testThePadKeepsAReadingWhenTheAppIsClosed() {
        var app = launch(["-iecDemo", "reset"])
        openFirstString(app)
        // Vmp, typed and left there
        for c in "321" { app.buttons[String(c)].tap() }
        XCTAssertTrue(app.buttons["บันทึกร่างตอนนี้"].isEnabled, "a draft waits")
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app = launch()
        openFirstString(app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "321")).firstMatch.waitForExistence(timeout: 10),
                      "Vmp 321 was saved on the way to the background")
        XCTAssertTrue(app.buttons["บันทึกแล้ว"].exists, "nothing left unsaved")
    }

    /// Through the screens, as a tester: the after table, its first string, `เปิดสตริงนี้`.
    func openFirstString(_ app: XCUIApplication) {
        let band = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "หลังการเชื่อมต่อระบบ")).firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: slow), "the overview")
        band.tap()
        let slot = app.buttons["ป้ายรูป (Word) ช่อง 1"]
        XCTAssertTrue(slot.waitForExistence(timeout: 10), "the after table")
        slot.tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "เปิดสตริงนี้ ›")).firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "ถัดไป ›")).firstMatch.waitForExistence(timeout: 10), "the pad")
    }

    /// `เสร็จ` on a real test (the full sample made the job's own by `-iecStationLine`) books the MP plan's
    /// `3.1 Pre-Commissioning Test` as done, and the install page's IEC line shows the result.
    func testClosingARealTestBooksTheMPTask() {
        let app = launch(["-iecDemo", "full", "-iecStationLine", "โรงงานสยามแพ็คกิ้ง ขนาดกำลังผลิต 199.8 kWp"])
        let finish = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "เสร็จ")).firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: slow))
        finish.tap()
        XCTAssertTrue(app.staticTexts["ปิดการทดสอบแล้ว · แก้ไขไม่ได้"].waitForExistence(timeout: 10))
        app.buttons["กลับ"].firstMatch.tap()

        let task = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "3.1 ")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10), "the plan's test task on the install page")
        XCTAssertTrue(task.label.contains("· 100%"), task.label)

        // reopened, so the station's test is left editable for the other tests
        app.terminate()
        let again = launch()
        let edit = again.buttons.matching(NSPredicate(format: "label CONTAINS %@", "แก้ไข")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: slow))
        edit.tap()
        again.buttons.matching(NSPredicate(format: "label == %@", "แก้ไข")).element(boundBy: 1).tap()
        gone(again.staticTexts["ปิดการทดสอบแล้ว · แก้ไขไม่ได้"], "reopened")
    }
}

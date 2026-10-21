import XCTest

/// The IEC test's steps keep their result: confirmed steps and the closed test survive a relaunch, a closed test is
/// read only until `แก้ไข`. A test closes in two taps: `ส่งผลให้ทีม` (the contractor), then `ปิดการทดสอบ` (the team). iPad simulator: `-only-testing:TCRoofUITests/IECStagesUITests`. It replaces the first
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

    func submitButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ส่งผลให้ทีม")).firstMatch
    }

    /// `ส่งผลให้ทีม` locks the test until the team's `ปิดการทดสอบ` closes it.
    func sendAndClose(_ app: XCUIApplication) {
        let submit = submitButton(app)
        XCTAssertTrue(submit.waitForExistence(timeout: slow))
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "ส่งผลให้ทีมแล้ว | รอทีมภายในปิด")).firstMatch
            .waitForExistence(timeout: 10), "sent, waiting for the team")
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "ปิดการทดสอบ")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.staticTexts["ปิดการทดสอบแล้ว | แก้ไขไม่ได้"].waitForExistence(timeout: 10))
    }

    func confirmed(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ยืนยันแล้ว"))
    }

    func testStepsAndTheResultSurviveARelaunch() {
        var app = launch(["-iecDemo", "full"])
        let first = app.buttons["ยืนยันขั้น ตั้งค่าระบบ"]
        XCTAssertTrue(first.waitForExistence(timeout: slow), "every step is done, none confirmed")
        first.tap()
        app.buttons["ยืนยันขั้น ก่อนออน | แรงดัน / กระแส"].tap()
        XCTAssertTrue(confirmed(app).element(boundBy: 1).waitForExistence(timeout: 10))

        // the confirmations are kept
        app.terminate()
        app = launch()
        XCTAssertTrue(confirmed(app).firstMatch.waitForExistence(timeout: slow), "kept after a relaunch")
        XCTAssertEqual(confirmed(app).count, 2)
        app.swipeUp()
        shot("steps-confirmed")
        XCTAssertFalse(app.buttons["ยืนยันขั้น ตั้งค่าระบบ"].exists)

        // sending and closing confirms the rest
        sendAndClose(app)
        gone(app.buttons["ยืนยันขั้น ก่อนออน | ฉนวน (IR)"], "closing confirms every step")

        // still closed after a relaunch, and the string table is read only
        app.terminate()
        app = launch()
        XCTAssertTrue(app.staticTexts["ปิดการทดสอบแล้ว | แก้ไขไม่ได้"].waitForExistence(timeout: slow), "the result is kept")
        sleep(1); shot("test-closed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ตั้งค่า")).firstMatch.exists, "no set-up on a closed test")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ก่อนการเชื่อมต่อระบบ")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ปิดการทดสอบแล้ว | ดูได้อย่างเดียว")).firstMatch
            .waitForExistence(timeout: 10), "the table says it's read only")
        shot("table-read-only")
        app.buttons["กลับ"].firstMatch.tap()

        // แก้ไข reopens it
        let edit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "แก้ไข")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        app.sheets.buttons["แก้ไข"].firstMatch.exists ? app.sheets.buttons["แก้ไข"].firstMatch.tap()
            : app.buttons.matching(NSPredicate(format: "label == %@", "แก้ไข")).element(boundBy: 1).tap()
        gone(app.staticTexts["ปิดการทดสอบแล้ว | แก้ไขไม่ได้"], "reopened")
        XCTAssertTrue(submitButton(app).waitForExistence(timeout: 10), "back to the contractor")
    }

    /// A reading typed on the pad is kept when the app goes to the background and is closed there (no ถัดไป). The pad
    /// is the before table's (step 3's IR is still typed there; steps 2 and 4 have their own pages on iPad).
    func testThePadKeepsAReadingWhenTheAppIsClosed() {
        var app = launch(["-iecDemo", "reset"])
        openFirstString(app)
        // Voc → current → IR +E, then 3 2 1 typed and left there
        let next = app.buttons.matching(NSPredicate(format: "label == %@", "ถัดไป ›")).firstMatch
        next.tap(); next.tap()
        for c in "321" { app.buttons[String(c)].tap() }
        XCTAssertTrue(app.buttons["บันทึกร่างตอนนี้"].isEnabled, "a draft waits")
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app = launch()
        openFirstString(app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "321")).firstMatch.waitForExistence(timeout: 10),
                      "IR +E 321 was saved on the way to the background")
        XCTAssertTrue(app.buttons["บันทึกแล้ว"].exists, "nothing left unsaved")
    }

    /// Through the screens, as a tester: step 2's page, its ถัดไป to the before table, the first string, `เปิดสตริงนี้`.
    func openFirstString(_ app: XCUIApplication) {
        let band = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ก่อนการเชื่อมต่อระบบ")).firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: slow), "the overview")
        band.tap()
        let toTable = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ถัดไป 3/7")).firstMatch
        XCTAssertTrue(toTable.waitForExistence(timeout: 15), "step 2's page")
        toTable.tap()
        let slot = app.buttons["ป้ายรูป (Word) ช่อง 1"]
        XCTAssertTrue(slot.waitForExistence(timeout: 10), "the before table")
        slot.tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "เปิดสตริงนี้ ›")).firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "ถัดไป ›")).firstMatch.waitForExistence(timeout: 10), "the pad")
    }

    /// Sending and closing a real test (the full sample made the job's own by `-iecStationLine`) books the MP plan's
    /// `3.1 Pre-Commissioning Test` as done, and the install page's IEC line shows the result.
    func testClosingARealTestBooksTheMPTask() {
        let app = launch(["-iecDemo", "full", "-iecStationLine", "โรงงานสยามแพ็คกิ้ง ขนาดกำลังผลิต 199.8 kWp"])
        sendAndClose(app)
        app.buttons["กลับ"].firstMatch.tap()

        let task = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "3.1 ")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10), "the plan's test task on the install page")
        // the Gantt row reads "| 100%", the plan tab's row ", 100%"
        XCTAssertTrue(task.label.hasSuffix("100%") || task.label.contains("| 100%"), task.label)

        // reopened, so the station's test is left editable for the other tests
        app.terminate()
        let again = launch()
        let edit = again.buttons.matching(NSPredicate(format: "label CONTAINS %@", "แก้ไข")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: slow))
        edit.tap()
        again.buttons.matching(NSPredicate(format: "label == %@", "แก้ไข")).element(boundBy: 1).tap()
        gone(again.staticTexts["ปิดการทดสอบแล้ว | แก้ไขไม่ได้"], "reopened")
    }

    /// `ส่งออก Word ภาพถ่าย` on the full sample: the appendix is made from every photo and offered to share (the file
    /// is `ตัวอย่าง แพรกหนามแดง …docx` in the app's `tmp/`).
    func testWordAppendixExports() {
        let app = launch(["-iecDemo", "full"])
        let word = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ส่งออก Word ภาพถ่าย")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: slow))
        word.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 60), "the Word file opens the share sheet")
    }
}

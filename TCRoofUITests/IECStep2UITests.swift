import XCTest

/// Step 2/7 `ก่อนออน · แรงดัน / กระแส` on iPad (docs/ui/iec62446-step2-before-vi-ipad): continuous mode walks the 3
/// unfinished strings through the dialog (V → A → the next string), the values are kept, a failing Voc shows its
/// alert, and an empty slot can take a string. iPad simulator: `-only-testing:TCRoofUITests/IECStep2UITests`. It
/// replaces the first installing station's test with the sample (`-iecStep2 YES`).
final class IECStep2UITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ state: String?, step2: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecCameraStub", "YES"]
            + (step2 ? ["-iecStep2", "YES"] : []) + (state.map { ["-iecStep2State", $0] } ?? [])
        app.launch()
        return app
    }

    func button(_ app: XCUIApplication, _ label: String, contains: Bool = false) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: contains ? "label CONTAINS %@" : "label == %@", label)).firstMatch
    }

    /// Clears the field and types `value`, then `บันทึก`.
    func enter(_ app: XCUIApplication, _ value: String) {
        let clear = app.buttons["ล้างค่า"]
        XCTAssertTrue(clear.waitForExistence(timeout: 15), "the dialog")
        clear.tap()
        for c in value { app.buttons[c == "." ? "จุด" : String(c)].tap() }
        button(app, "บันทึก", contains: true).tap()
    }

    func testContinuousModeMeasuresTheRestAndKeepsThem() {
        var app = launch("todo")
        let start = button(app, "วัดต่อเนื่อง · เหลือ 3", contains: true)
        XCTAssertTrue(start.waitForExistence(timeout: slow), "3 strings left on INV1")
        start.tap()
        // INV1ST14, 15, 16: V then A each; the photos are there, so the dialog goes straight on
        for v in ["753", "751", "752"] {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "โหมดต่อเนื่อง")).firstMatch.waitForExistence(timeout: 10))
            enter(app, v)
            enter(app, "0")
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["ล้างค่า"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "the dialog closes after the last string")
        XCTAssertTrue(app.staticTexts["✓ ครบ 16/16"].waitForExistence(timeout: 10))

        // kept: the page opened from the overview, without the seed, still has them
        app.terminate()
        app = launch(nil, step2: false)
        let band = button(app, "ก่อนการเชื่อมต่อระบบ", contains: true)
        XCTAssertTrue(band.waitForExistence(timeout: slow))
        band.tap()
        XCTAssertTrue(app.staticTexts["✓ ครบ 16/16"].waitForExistence(timeout: 15), "the step 2 page, all measured")
        XCTAssertTrue(app.staticTexts["751"].exists, "INV1ST15's Voc")
    }

    func testAFailingVocShowsItsAlert() {
        let app = launch("fail")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Voc 712.0 V ต่างจากมัธยฐาน −5.4%")).firstMatch
            .waitForExistence(timeout: slow))
        XCTAssertTrue(button(app, "วัดซ้ำ").exists)
        XCTAssertTrue(app.staticTexts["มีค่าไม่ผ่าน 1 สตริง"].exists)
    }

    func testAnEmptySlotTakesAString() {
        let app = launch("empty")
        let add = button(app, "มีสตริงต่อในช่องนี้", contains: true)
        XCTAssertTrue(add.waitForExistence(timeout: slow), "slot 8 is empty")
        add.tap()
        // the new string is INV1ST8, so the old ST8 onwards move up one
        XCTAssertTrue(app.staticTexts["INV1ST17"].waitForExistence(timeout: 10), "17 strings now")
        XCTAssertTrue(button(app, "ตั้งช่อง 8 เป็นว่าง").exists)
    }

    /// A value typed in the dialog and left there is kept when the app goes to the background and is closed.
    func testTheDialogKeepsAValueWhenTheAppIsClosed() {
        var app = launch("todo")
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "มิเตอร์ V")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: slow), "INV1ST14's photo card")
        card.tap()
        let clear = app.buttons["ล้างค่า"]
        XCTAssertTrue(clear.waitForExistence(timeout: 15))
        clear.tap()
        for c in "748" { app.buttons[String(c)].tap() }
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app = launch(nil, step2: false)
        let band = button(app, "ก่อนการเชื่อมต่อระบบ", contains: true)
        XCTAssertTrue(band.waitForExistence(timeout: slow))
        band.tap()
        XCTAssertTrue(app.staticTexts["748"].waitForExistence(timeout: 15), "INV1ST14's Voc was saved on the way to the background")
    }
}

import XCTest

/// Step 4/7 `หลังออน | แรงดัน / กระแส` on iPad (docs/ui/iec62446-step4-after-vi-ipad), step 2's page for the after phase:
/// continuous mode measures the strings `todo` leaves (photo first from the stub camera, then Vmp and Imp), a Vmp off
/// its group's median shows its alert, and the dialog has no polarity. iPad simulator:
/// `-only-testing:TCRoofUITests/IECStep4UITests`. It replaces the first installing station's test with the sample.
final class IECStep4UITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecCameraStub", "YES", "-iecStep4", "YES", "-iecStep4State", state]
        app.launch()
        return app
    }

    func enter(_ app: XCUIApplication, _ value: String) {
        let clear = app.buttons["ล้างค่า"]
        XCTAssertTrue(clear.waitForExistence(timeout: 15), "the dialog")
        clear.tap()
        for c in value { app.buttons[c == "." ? "จุด" : String(c)].tap() }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "บันทึก")).firstMatch.tap()
    }

    func testContinuousModeMeasuresTheRest() {
        let app = launch("todo")
        let start = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "วัดต่อเนื่อง | เหลือ 7")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: slow), "9 of 16 measured")
        start.tap()
        for v in ["613.1", "612.2", "611.8", "614.0", "612.7", "613.5", "612.9"] {
            enter(app, v)
            enter(app, "12.4")
        }
        XCTAssertTrue(app.staticTexts["✓ ครบ 16/16"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["612.9"].exists || app.staticTexts["613.1"].exists, "the values are in the table")
    }

    func testAVmpOffItsMedianShowsItsAlert() {
        let app = launch("fail")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Vmp 561.0 V ต่างจากมัธยฐาน")).firstMatch
            .waitForExistence(timeout: slow))
        XCTAssertTrue(app.staticTexts["มีค่าไม่ผ่าน 1 สตริง"].exists)
        XCTAssertTrue(app.staticTexts["String 5"].exists, "the table's String labels")
    }

    func testTheDialogHasNoPolarity() {
        let app = launch("vmp")
        XCTAssertTrue(app.staticTexts["มิเตอร์ V | หลังออน"].waitForExistence(timeout: slow))
        XCTAssertFalse(app.buttons["✓ ถูกต้อง"].exists, "no polarity after the connection")
        XCTAssertTrue(app.staticTexts["แรงดัน Vmp"].exists || app.otherElements["แรงดัน Vmp"].exists)
    }
}

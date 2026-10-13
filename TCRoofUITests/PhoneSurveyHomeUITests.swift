import XCTest

/// docs/ui/tcroof-survey-home-iphone, on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/PhoneSurveyHomeUITests -derivedDataPath <scratch>`.
/// The dock opens the next survey and the add-customer sheet; the next appointment, a list row and the history row
/// open their screens; a day and a status chip become selected.
final class PhoneSurveyHomeUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() {
        continueAfterFailure = false
        // the home tab's demo puts two appointments on today
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeDemo", "YES", "-noNotificationPrompt", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["งานบ้าน"].firstMatch.waitForExistence(timeout: slow) || app.buttons.firstMatch.waitForExistence(timeout: slow))
        app.terminate()
    }

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "homework", "-surveyListDraft", "YES", "-noNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    func button(_ app: XCUIApplication, beginning prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The dock's main button opens the survey form; its small button opens the add-customer sheet.
    func testDock() {
        let app = launch()
        let add = app.buttons["เพิ่มลูกค้าใหม่"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: slow))
        add.tap()
        XCTAssertTrue(app.buttons["ยกเลิก"].firstMatch.waitForExistence(timeout: 8), "the add button should open the add-customer sheet")
        app.buttons["ยกเลิก"].firstMatch.tap()

        let survey = button(app, beginning: "ทำแบบสำรวจต่อ")
        XCTAssertTrue(survey.waitForExistence(timeout: 8), "today's draft should give the dock `ทำแบบสำรวจต่อ`")
        survey.tap()
        XCTAssertTrue(app.navigationBars["แบบสำรวจ (ร่าง)"].waitForExistence(timeout: 8), "the dock should open the survey form")
    }

    /// The next appointment opens its job, and the home comes back.
    func testNext() {
        let app = launch()
        let next = button(app, beginning: "รายละเอียดงาน")
        XCTAssertTrue(next.waitForExistence(timeout: slow))
        XCTAssertTrue(app.buttons["โทรหาลูกค้า"].exists)
        XCTAssertTrue(app.buttons["นำทางไปหน้างาน"].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["ข้อมูลลูกค้า"].waitForExistence(timeout: 8), "the next appointment should open the job")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 8), "back should return to the survey home")
    }

    /// `ประวัติการสำรวจ` under the list opens the history.
    func testHistory() {
        let app = launch()
        XCTAssertTrue(app.buttons["เพิ่มลูกค้าใหม่"].firstMatch.waitForExistence(timeout: slow))
        let history = app.buttons["ประวัติการสำรวจ"].firstMatch
        for _ in 0..<8 where !(history.exists && history.isHittable) { app.swipeUp() }
        history.tap()
        XCTAssertTrue(app.navigationBars["ประวัติการสำรวจ"].waitForExistence(timeout: 8), "the history row should open the history")
    }

    /// A status chip and a day of the strip become selected; a list row opens its job.
    func testChipDayAndRow() {
        let app = launch()
        let chip = button(app, beginning: "ยืนยันแล้ว")
        XCTAssertTrue(chip.waitForExistence(timeout: slow))
        XCTAssertFalse(chip.isSelected)
        chip.tap()
        XCTAssertTrue(chip.isSelected, "the tapped status chip should be selected")
        XCTAssertFalse(button(app, beginning: "ทั้งหมด").isSelected)

        let today = button(app, beginning: "วันนี้ ")
        XCTAssertTrue(today.isSelected, "today is selected at first")
        let days = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@ OR label CONTAINS %@", " ไม่มีนัด", " นัด "))
        XCTAssertEqual(days.count, 7)
        let tomorrow = days.element(boundBy: 1)
        tomorrow.tap()
        XCTAssertTrue(tomorrow.isSelected)
        XCTAssertFalse(today.isSelected)

        button(app, beginning: "ทั้งหมด").tap()
        let row = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "ลูกค้าสนใจติดตั้ง")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.staticTexts["ข้อมูลลูกค้า"].waitForExistence(timeout: 8), "a row should open the job")
    }
}

import XCTest

/// docs/ui/pwa-plan-iphone, on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/PhonePWAPlanUITests -derivedDataPath <scratch>`.
/// The pills change the view; an agenda row, a Gantt row and a deadline open their screens and the page comes back;
/// the two filters narrow their lists.
final class PhonePWAPlanUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() {
        continueAfterFailure = false
        // `mpall` gives the first four jobs an MP plan around today, which makes them PWA stations
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mpall", "-noNotificationPrompt", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["แผน MP ทุกสถานี"].waitForExistence(timeout: slow) || app.buttons.firstMatch.waitForExistence(timeout: slow))
        app.terminate()
    }

    func launch(_ pane: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyHomeTab", "plan", "-pwaPlanView", pane, "-noNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    func button(_ app: XCUIApplication, _ format: String, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label \(format) %@", text)).firstMatch
    }

    func back(_ app: XCUIApplication, to element: XCUIElement) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element.waitForExistence(timeout: 8), "back should return to the plan page")
    }

    /// Each pill becomes selected and shows its view.
    func testPills() {
        let app = launch("schedule")
        let schedule = button(app, "BEGINSWITH", "ตารางงาน "), mp = button(app, "BEGINSWITH", "แผน MP "), due = button(app, "BEGINSWITH", "กำหนดส่ง ")
        XCTAssertTrue(schedule.waitForExistence(timeout: slow))
        XCTAssertTrue(schedule.isSelected)
        XCTAssertTrue(app.buttons["สัปดาห์ถัดไป"].exists)

        mp.tap()
        XCTAssertTrue(mp.isSelected)
        XCTAssertFalse(schedule.isSelected)
        XCTAssertTrue(app.staticTexts["ความก้าวหน้าทั้งโครงการ"].waitForExistence(timeout: 8))

        due.tap()
        XCTAssertTrue(due.isSelected)
        XCTAssertTrue(button(app, "BEGINSWITH", "กรองกำหนดส่ง").waitForExistence(timeout: 8), "the filter button stands in the pill row of `กำหนดส่ง`")
    }

    /// Today's install row opens its station; the week arrows move the strip.
    func testAgendaRow() {
        let app = launch("schedule")
        let row = button(app, "CONTAINS", " · ติดตั้ง · ")
        XCTAssertTrue(row.waitForExistence(timeout: slow), "a seeded station is in its install window today")
        row.tap()
        XCTAssertTrue(app.staticTexts["ข้อมูลลูกค้า"].waitForExistence(timeout: 8), "an install row should open the station")
        back(app, to: row)

        let today = button(app, "CONTAINS", " · วันนี้ · ")
        XCTAssertTrue(today.isSelected, "today is selected at first")
        app.buttons["สัปดาห์ถัดไป"].tap()
        XCTAssertFalse(today.exists, "the next week has no today")
        app.buttons["สัปดาห์ก่อน"].tap()
        XCTAssertTrue(today.waitForExistence(timeout: 8))
    }

    /// The agenda filter: a type with no row leaves the empty card, and `ล้างตัวกรอง` brings the rows back.
    func testAgendaFilter() {
        let app = launch("schedule")
        let row = button(app, "CONTAINS", " · ติดตั้ง · ")
        XCTAssertTrue(row.waitForExistence(timeout: slow))
        button(app, "BEGINSWITH", "กรองตารางงาน").tap()
        let inspection = button(app, "BEGINSWITH", "ตรวจรับ ")
        XCTAssertTrue(inspection.waitForExistence(timeout: 8), "the filter button should open `กรองตารางงาน`")
        inspection.tap()
        button(app, "BEGINSWITH", "แสดง ").tap()
        let clear = app.buttons["ล้างตัวกรอง"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 8), "no inspection is kept, so the day is empty under that filter")
        XCTAssertFalse(row.exists)
        clear.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8))
    }

    /// A Gantt row opens the station's MP plan.
    func testGanttRow() {
        let app = launch("mp")
        let row = button(app, "CONTAINS", " · ส่งมอบ ")
        XCTAssertTrue(row.waitForExistence(timeout: slow))
        row.tap()
        let plan = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "แผนงาน MP")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 8), "a Gantt row should open แผนงาน MP")
        back(app, to: row)
    }

    /// The overdue handover opens its station, and the menu's `ยื่นเอกสาร` takes it off the list.
    func testDeadline() {
        let app = launch("due")
        let row = button(app, "CONTAINS", " · ส่งมอบงาน")
        XCTAssertTrue(row.waitForExistence(timeout: slow), "a seeded station is past its handover")
        row.tap()
        XCTAssertTrue(app.staticTexts["ข้อมูลลูกค้า"].waitForExistence(timeout: 8), "a handover should open the station")
        back(app, to: row)

        button(app, "BEGINSWITH", "กรองกำหนดส่ง").tap()
        let documents = button(app, "BEGINSWITH", "ยื่นเอกสาร")
        XCTAssertTrue(documents.waitForExistence(timeout: 8), "the filter button should open its menu")
        documents.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed, "`ยื่นเอกสาร` should hide the handovers")
    }
}

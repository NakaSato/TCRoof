import XCTest

/// Time, CPU and memory of the install tracking page and the IEC 62446 test on an iPad simulator (Debug build, so the
/// numbers are pessimistic): `-only-testing:TCRoofUITests/InstallPerformanceUITests`. Each block runs 5 times.
final class InstallPerformanceUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-installSeed", "YES",
                               "-noNotificationPrompt", "YES"] + extra
        app.launch()
        // the install page, or the IEC test pushed over it
        let ready = app.buttons.matching(NSPredicate(format: "label IN %@", ["กลับหน้ารายการงาน", "กลับ"])).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: slow))
        return app
    }

    func metrics(_ app: XCUIApplication) -> [XCTMetric] {
        [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]
    }

    func gone(_ e: XCUIElement) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)], timeout: 10) == .completed
    }

    /// `ภาพรวม` ⇄ `รายงานประจำวัน`: the overview's Gantt and site panel against the daily table of a station with reports.
    func testSwitchInstallTabs() {
        let app = launch([])
        let daily = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "รายงานประจำวัน")).firstMatch
        let overview = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ภาพรวม")).firstMatch
        measure(metrics: metrics(app)) {
            daily.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ทั้งหมด")).firstMatch.waitForExistence(timeout: 10))
            overview.tap()
            XCTAssertTrue(app.staticTexts["ความคืบหน้าเทียบแผน"].waitForExistence(timeout: 10))
        }
    }

    /// The IEC test's overview to Inverter 1's before page (step 2: the DC map and the 20-row table) and back.
    func testOpenIECStringTable() {
        let app = launch(["-iecDemo", "YES", "-iecOpen", "YES"])
        let band = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ก่อนการเชื่อมต่อระบบ")).firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: 15))
        measure(metrics: metrics(app)) {
            band.tap()
            let cell = app.staticTexts["ตารางค่าวัด · INV1 ก่อนออนระบบ"]
            XCTAssertTrue(cell.waitForExistence(timeout: 10))
            app.buttons["กลับ"].firstMatch.tap()
            XCTAssertTrue(gone(cell))
        }
    }

    /// 12 keys on `กรอกทีละสตริง`'s pad; each one saves the report.
    func testTypeOnThePad() {
        let app = launch(["-iecDemo", "YES", "-iecOpen", "YES", "-iecInverter", "1", "-iecPhase", "before", "-iecSlot", "3", "-iecEntry", "YES"])
        let pad = app.buttons["7"]
        XCTAssertTrue(pad.waitForExistence(timeout: 20))
        measure(metrics: metrics(app)) {
            for k in ["7", "5", "3", "จุด", "5", "ลบ", "ลบ", "ลบ", "ลบ", "ลบ", "ลบ", "7"] { app.buttons[k].tap() }
        }
    }
}

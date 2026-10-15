import XCTest

/// Step 1/7 `ตั้งค่าระบบ` on iPad (docs/ui/iec62446-step1-setup-ipad): an inverter added from the catalogue with its
/// photos and a scanned S/N, then deleted; a string set SPARE updates the totals; `ถัดไป` waits for the date and the
/// tester, then opens step 2. iPad simulator: `-only-testing:TCRoofUITests/IECStep1UITests`. It replaces the first
/// installing station's test with the sample (`-iecDemo praek`).
final class IECStep1UITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecDemo", "praek", "-iecStep", "1", "-iecCameraStub", "YES"] + extra
        app.launch()
        return app
    }

    func button(_ app: XCUIApplication, _ label: String, contains: Bool = false) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: contains ? "label CONTAINS %@" : "label == %@", label)).firstMatch
    }

    func gone(_ e: XCUIElement, _ what: String) {
        let x = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        XCTAssertEqual(XCTWaiter.wait(for: [x], timeout: 10), .completed, what)
    }

    func testAnInverterIsAddedWithItsPhotosAndDeleted() {
        let app = launch()
        let add = button(app, "+ เพิ่มอินเวอร์เตอร์")
        XCTAssertTrue(add.waitForExistence(timeout: slow), "step 1's page")
        add.tap()
        XCTAssertTrue(button(app, "ถ่ายรูปด้านหน้าและป้าย S/N ก่อน").waitForExistence(timeout: 10), "two photos are required first")
        button(app, "สแกนป้าย S/N ใหม่").tap()
        XCTAssertTrue(app.textFields["S/N ใหม่"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["S/N ใหม่"].value as? String, "TCR2026SN01", "the stub nameplate's serial")
        app.buttons["ด้านหน้า"].firstMatch.tap()
        app.buttons["ด้านข้าง · ป้าย S/N"].firstMatch.tap()
        let commit = button(app, "เพิ่ม INV3")
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.tap()
        // the 60 kW model of the sample's INV 2: 6 MPPT, every slot a string of 16
        XCTAssertTrue(app.staticTexts["12/12 สตริง"].waitForExistence(timeout: 10), "INV3's tab, selected")
        XCTAssertTrue(app.staticTexts["TCR2026SN01"].exists || (app.textFields["S/N อินเวอร์เตอร์"].value as? String) == "TCR2026SN01")

        button(app, "ลบ INV3").tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "ลบ INV3")).element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        gone(app.staticTexts["12/12 สตริง"], "INV3 is gone")
    }

    func testASpareStringUpdatesTheTotals() {
        let app = launch()
        let toggle = app.switches["String 3"]
        XCTAssertTrue(toggle.waitForExistence(timeout: slow))
        XCTAssertTrue(app.staticTexts["16 / 20 ช่อง"].exists)
        toggle.tap()
        XCTAssertTrue(app.staticTexts["15 / 20 ช่อง"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["240 แผง"].exists)
        XCTAssertTrue(app.staticTexts["136,800 Wp"].exists)
        toggle.tap()
        XCTAssertTrue(app.staticTexts["16 / 20 ช่อง"].waitForExistence(timeout: 5))
    }

    func testNextWaitsForTheRecordThenOpensStepTwo() {
        let app = launch()
        let next = button(app, "ถัดไป 2/7", contains: true)
        XCTAssertTrue(next.waitForExistence(timeout: slow))
        XCTAssertFalse(next.isEnabled, "no date or tester yet")
        app.buttons["วันที่ทดสอบ"].tap()
        // the picker sets today; tap away to close it
        app.staticTexts["รายการสตริง (String list)"].tap()
        let tester = app.textFields["ผู้ทดสอบ"]
        tester.tap()
        tester.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "ทีมทดสอบ\n")
        XCTAssertTrue(next.isEnabled, "SLD, date, tester and strings are there")
        next.tap()
        XCTAssertTrue(app.staticTexts["ตารางค่าวัด · INV1 ก่อนออนระบบ"].waitForExistence(timeout: 15), "step 2's page")
    }
}

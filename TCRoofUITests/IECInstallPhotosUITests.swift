import XCTest

/// IEC 62446 | 9 ภาพถ่ายติดตั้งระบบ. On iPad (`testPadFillsASlotAndMakesThePDF`) the page opens in the string table
/// (`-iecPage install`) on the sample (`-iecDemo reset`, replaced each run): the stub camera fills ตู้ AC's inside slot
/// and the count goes up by one, the photo is still there after a relaunch, a roof added gets its two pages and is
/// removed again, and `PDF รายงาน 9` opens the share sheet. On iPhone (`testPhoneOpensFromTheJob`) the PWA job
/// screen's `ภาพถ่ายติดตั้งระบบ` row opens the one-column page and the stub fills the same slot; that leaves a photo
/// (and a test, when it had none) on the first job, which `-jobKind pwa` makes a PWA job for good.
/// `-only-testing:TCRoofUITests/IECInstallPhotosUITests`; each test skips on the other size.
final class IECInstallPhotosUITests: XCTestCase {
    let slow: TimeInterval = 90
    /// ตู้ AC's first slot: the tile's label is the report's heading without `ภาพถ่าย`.
    let acInside = "ตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ (ด้านใน)"

    override func setUp() { continueAfterFailure = false }

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    func launchPad(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecInverter", "1", "-iecPage", "install", "-iecCameraStub", "YES"] + extra
        app.launch()
        return app
    }

    func gone(_ e: XCUIElement, _ what: String) {
        let x = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        XCTAssertEqual(XCTWaiter.wait(for: [x], timeout: 10), .completed, what)
    }

    func has(_ e: XCUIElement, value: String, _ what: String) {
        let x = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: e)
        XCTAssertEqual(XCTWaiter.wait(for: [x], timeout: 10), .completed, what)
    }

    /// The summary's `ถ่ายแล้ว 3/19 รูป | เหลือ 16` (or `ครบ 19 รูปแล้ว`), as the photos taken.
    func taken(_ app: XCUIApplication) -> Int? {
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "ถ่ายแล้ว ", "ครบ ")).firstMatch
        guard line.waitForExistence(timeout: slow) else { return nil }
        let label = line.label
        if label.hasPrefix("ครบ ") { return Int(label.dropFirst(4).prefix { $0.isNumber }) }
        return Int(label.dropFirst("ถ่ายแล้ว ".count).prefix { $0.isNumber })
    }

    /// Scrolls the page until `e` can be tapped.
    func reach(_ e: XCUIElement, in app: XCUIApplication) {
        var n = 0
        while !e.isHittable, n < 12 { app.swipeUp(); n += 1 }
        XCTAssertTrue(e.isHittable, "reached \(e)")
    }

    func testPadFillsASlotAndMakesThePDF() throws {
        try XCTSkipIf(isPhone, "the iPad string table")
        var app = launchPad(["-iecDemo", "reset"])
        let before = try XCTUnwrap(taken(app), "the summary's count")

        // the stub camera fills ตู้ AC's inside slot
        let tile = app.buttons[acInside]
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        reach(tile, in: app)
        XCTAssertEqual(tile.value as? String, "ยังไม่มีรูป", "the sample starts without install photos")
        tile.tap()
        has(tile, value: "มีรูปแล้ว", "the stub photo is in the slot")
        XCTAssertEqual(taken(app), before + 1, "the count goes up by one")

        // kept after a relaunch (no reset this time)
        app.terminate()
        app = launchPad()
        let again = app.buttons[acInside]
        XCTAssertTrue(again.waitForExistence(timeout: slow))
        XCTAssertEqual(again.value as? String, "มีรูปแล้ว", "kept after a relaunch")
        XCTAssertEqual(taken(app), before + 1)

        // a roof adds its two pages, and goes again
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "ชื่อหลังคาที่เพิ่ม")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("หลังคาทดสอบ")
        app.buttons["เพิ่มหลังคา"].tap()
        let page = app.staticTexts["หลังคาทดสอบ (1/2)"]
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the new roof's first page")
        XCTAssertTrue(app.staticTexts["หลังคาทดสอบ (2/2)"].exists)
        let remove = app.buttons["ลบ หลังคาทดสอบ"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        reach(remove, in: app)
        remove.tap()
        gone(page, "the roof's pages go with it")

        // PDF รายงาน 9: every page, then the share sheet
        let pdf = app.buttons["iecInstallPDF"]
        if !pdf.isHittable { app.swipeDown(); app.swipeDown(); app.swipeDown() }
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        pdf.tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the PDF opens the share sheet")
    }

    func testPhoneOpensFromTheJob() throws {
        try XCTSkipUnless(isPhone, "the iPhone job screen")
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "job", "-jobKind", "pwa", "-noNotificationPrompt", "YES", "-iecCameraStub", "YES"]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ภาพถ่ายติดตั้งระบบ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: slow), "the job screen's row")
        reach(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["9 ภาพถ่ายติดตั้งระบบ"].waitForExistence(timeout: 10), "the page on its own")
        let before = try XCTUnwrap(taken(app))

        let tile = app.buttons[acInside]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        reach(tile, in: app)
        if tile.value as? String == "ยังไม่มีรูป" {
            tile.tap()
            has(tile, value: "มีรูปแล้ว", "the stub photo is in the slot")
            XCTAssertEqual(taken(app), before + 1)
        }
        // one column: the PDF button spans the page under the count
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let pdf = app.buttons["iecInstallPDF"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(pdf.frame.width, app.windows.firstMatch.frame.width * 0.7, "full width on iPhone")
    }
}

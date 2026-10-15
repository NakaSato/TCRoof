import XCTest

/// The iPad install tracking page's overview end (docs/ui/install-tracking-ipad §C), on an iPad simulator with the board's
/// example: `-only-testing:TCRoofUITests/InstallTrackingUITests`. The KPI cell `ต้องดำเนินการ` opens the open items and a
/// row pushes its screen; a document tile opens its list and a line pushes its screen; back returns to the page.
final class InstallTrackingUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = ["-installScrollEnd", "YES"], demo: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-installDemo", demo ? "YES" : "NO",
                               "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    func pageBack(_ app: XCUIApplication) -> XCUIElement { app.buttons["กลับหน้ารายการงาน"] }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func waitValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10) -> Bool {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    /// Back from a pushed screen (its iPad header's `กลับหน้าหลัก`) to the page.
    func back(_ app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label == %@", "กลับหน้าหลัก")).firstMatch.tap()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: 8), "back should return to the page")
    }

    func testActionsSheetOpensAnItem() {
        let app = launch()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ต้องดำเนินการ")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8))
        cell.tap()
        // the KPI cell's note names the items too: match the sheet's row by its priority chip
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "กลาง", "Weekly Report W40")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the KPI cell should open the open items")
        row.tap()
        XCTAssertTrue(waitGone(pageBack(app)), "an item should push its screen")
        back(app)
        XCTAssertFalse(row.exists, "the sheet should be closed after opening an item")
    }

    func testDocumentTileListsItsItems() {
        let app = launch()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Daily Report")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8))
        tile.tap()
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DR-007")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 8), "the tile should list its reports")
        app.buttons["ปิด"].firstMatch.tap()
        XCTAssertTrue(waitGone(line), "ปิด should close the list")
        tile.tap()
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        line.tap()
        XCTAssertTrue(waitGone(pageBack(app)), "a report should open its daily report")
        back(app)
    }

    func testSitePanelTabs() {
        let app = launch()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let risk = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ความเสี่ยง")).firstMatch
        XCTAssertTrue(risk.waitForExistence(timeout: 8))
        risk.tap()
        XCTAssertTrue(app.staticTexts["จากคำขอรายสัปดาห์นี้"].waitForExistence(timeout: 8), "ความเสี่ยง should list the week's risks")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "แรงงาน")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "สะสม 44 man-day")).firstMatch.waitForExistence(timeout: 8),
                      "แรงงาน should show the crew chart")
    }

    /// `รายงานประจำวัน`: the tab opens in place, `ต้องทำ` keeps today and the draft, and a row's button opens its report.
    func testDailyTabFiltersAndOpensAReport() {
        let app = launch([])
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "รายงานประจำวัน")).firstMatch.tap()
        let open = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "เปิดรายงาน"))
        XCTAssertTrue(open.firstMatch.waitForExistence(timeout: 8), "the tab should list the reports")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ต้องทำ")).firstMatch.tap()
        XCTAssertTrue(waitGone(open.firstMatch), "ต้องทำ should leave out the signed reports")
        let draft = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ทำต่อ · ส่ง")).firstMatch
        XCTAssertTrue(draft.exists && app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ทำรายงานวันนี้")).firstMatch.exists)
        draft.tap()
        XCTAssertTrue(waitGone(pageBack(app)), "the button should open the daily report")
        back(app)
    }

    /// `PDF รวม` on a station with reports (`-installSeed YES` gives it the routine demo's): the share sheet opens.
    func testCombinedPDFShares() {
        let app = launch(["-installSeed", "YES", "-installTab", "daily"], demo: false)
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let pdf = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PDF รวม")).firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        pdf.tap()
        let sheet = app.otherElements.matching(identifier: "ActivityListView").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "PDF รวม should open the share sheet")
    }

    /// A late task's sheet keeps the picked cause in the job (MP 192's 2.2 is past its end with nothing done): it is
    /// still picked after a relaunch, and tapping it again clears it.
    func testLateCauseIsKept() {
        func open() -> XCUIApplication {
            let app = launch(["-installStage", "2"], demo: false)
            XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
            return app
        }
        var app = open()
        let material = app.buttons["สาเหตุ วัสดุ"]
        XCTAssertTrue(material.waitForExistence(timeout: 10), "a late task's sheet should offer the causes")
        if material.isSelected { material.tap() }
        material.tap()
        XCTAssertTrue(material.isSelected)
        app.terminate()
        app = open()
        let again = app.buttons["สาเหตุ วัสดุ"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertTrue(again.isSelected, "the cause should be kept")
        again.tap()
        XCTAssertFalse(again.isSelected, "tapping the picked cause should clear it")
    }

    /// The header's `รายละเอียดงาน` opens the job's own screen (scans, ICL, documents …) and back returns to the page.
    func testJobDetailOpensFromHeader() {
        let app = launch([], demo: false)
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let detail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "รายละเอียดงาน")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        detail.tap()
        XCTAssertTrue(app.staticTexts["ข้อมูลลูกค้า"].waitForExistence(timeout: 10), "the job's screen should open")
        // the actions are below the MP plan and routine report cards
        let scan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "สแกนอุปกรณ์")).firstMatch
        // drag inside the page: -homeBoard draws it in the top of a portrait simulator, where swipeUp misses it
        let page = app.staticTexts["ข้อมูลลูกค้า"]
        for _ in 0..<6 where !scan.isHittable {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 300))
                .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(scan.isHittable, "the job's screen should offer สแกนอุปกรณ์")
        XCTAssertTrue(waitGone(pageBack(app)))
        back(app)
    }

    /// `ทดสอบ IEC 62446` opens the IEC test (seeded with the แพรกหนามแดง sample); a band opens its string table, and a
    /// Vmp typed into slot 1 after the connection is kept after going back and in again.
    func testIECTabTypesAReading() {
        let app = launch(["-iecDemo", "YES"], demo: false)
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ทดสอบ IEC 62446")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ทดสอบระบบ IEC 62446"].waitForExistence(timeout: 10), "the tab should open the IEC test")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "หลังการเชื่อมต่อระบบ")).firstMatch.tap()
        let cell = app.buttons["Vmp (V) ช่อง 1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "the band should open the after table")
        cell.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let old = field.value as? String, !old.isEmpty, old != "0" { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText("612.5")
        app.buttons["เสร็จ"].tap()
        XCTAssertTrue(NSPredicate(format: "value == %@", "612.5").evaluate(with: cell) || waitValue(cell, "612.5"), "the reading should show in its cell")
        app.buttons["กลับ"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "หลังการเชื่อมต่อระบบ")).firstMatch.tap()
        XCTAssertTrue(waitValue(app.buttons["Vmp (V) ช่อง 1"], "612.5"), "the reading should be kept")
    }

    /// `กรอกทีละสตริง`: from the before table, a selected string opens; the pad types IR +E after `ถัดไป` moves past the
    /// voltage and current, and the stub camera fills the voltage photo.
    func testIECStringEntryTypesAndTakesAPhoto() {
        let app = launch(["-iecDemo", "YES", "-iecCameraStub", "YES"], demo: false)
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ทดสอบ IEC 62446")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ก่อนการเชื่อมต่อระบบ")).firstMatch.tap()
        let cell = app.buttons["ป้ายรูป (Word) ช่อง 2"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        app.buttons["เปิดสตริงนี้ ›"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "INV1ST2")).firstMatch.waitForExistence(timeout: 10),
                      "the string should open in กรอกทีละสตริง")
        app.buttons["ถัดไป ›"].tap()
        app.buttons["ถัดไป ›"].tap()
        for k in ["3", "0", "0"] { app.buttons[k].tap() }
        XCTAssertTrue(waitValue(app.buttons["Positive – Earth"], "300 MΩ"), "the pad should type into IR +E")
        // typed readings are kept when the screen closes, and are there when the string opens again
        app.buttons["กลับ"].firstMatch.tap()
        XCTAssertTrue(app.buttons["เปิดสตริงนี้ ›"].waitForExistence(timeout: 10))
        app.buttons["เปิดสตริงนี้ ›"].tap()
        XCTAssertTrue(waitValue(app.buttons["Positive – Earth"], "300 MΩ"), "the reading should be kept after leaving")
        let photo = app.buttons["แรงดัน"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(waitValue(photo, "มีรูปแล้ว"), "the stub camera should fill the photo")
    }

    /// `ส่งออก Excel IEC 62446` fills the PWA's workbook and opens the share sheet with it.
    func testIECExportOpensTheShareSheet() {
        let app = launch(["-iecDemo", "YES", "-iecOpen", "YES"], demo: false)
        let export = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ส่งออก Excel IEC 62446")).firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: slow))
        export.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30),
                      "the export should open the share sheet")
    }

    /// A station line that names another station is flagged; `ใช้ชื่อของงาน` fixes it, and exporting with it asks first.
    func testIECStationLineMismatch() {
        var app = launch(["-iecOpen", "YES", "-iecDemo", "YES", "-iecStationLine", "สถานีอื่น ขนาดกำลังผลิต 1 kWp"], demo: false)
        let notice = app.staticTexts["บรรทัดสถานีในแผ่นงานไม่ตรงกับชื่องาน"]
        XCTAssertTrue(notice.waitForExistence(timeout: slow), "the overview should flag the station line")
        app.buttons["ใช้ชื่อของงาน"].tap()
        XCTAssertTrue(waitGone(notice), "ใช้ชื่อของงาน should fix it")
        app.terminate()
        app = launch(["-iecOpen", "YES", "-iecDemo", "YES", "-iecStationLine", "สถานีอื่น ขนาดกำลังผลิต 1 kWp"], demo: false)
        let export = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ส่งออก Excel IEC 62446")).firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: slow))
        export.tap()
        let useJob = app.buttons["ใช้ชื่อของงานแล้วส่งออก"]
        XCTAssertTrue(useJob.waitForExistence(timeout: 10), "exporting with another station's line should ask first")
        useJob.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30))
    }

    /// Example data says so, and exports without the station question.
    func testIECSampleIsLabelled() {
        let app = launch(["-iecOpen", "YES", "-iecDemo", "reset"], demo: false)
        XCTAssertTrue(app.staticTexts["ข้อมูลตัวอย่างจากสถานีแพรกหนามแดง ไม่ใช่ผลทดสอบของงานนี้"].waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ส่งออก Excel IEC 62446")).firstMatch.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30),
                      "a sample exports at once, named as the sample")
    }
}

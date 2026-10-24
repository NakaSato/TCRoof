import XCTest

/// The iPad install tracking page's overview end (docs/ui/install-tracking-ipad §C), on an iPad simulator with the board's
/// example: `-only-testing:TCRoofUITests/InstallTrackingUITests`. The KPI cell `ต้องดำเนินการ` opens the open items and a
/// row pushes its screen; a document tile opens its list and a line pushes its screen; back returns to the page.
final class InstallTrackingUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    /// The first launch after an install can take longer than `slow`; one launch before the tests takes it, so a
    /// test's own wait measures the page, not the cold start.
    override class func setUp() {
        super.setUp()
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-installDemo", "YES",
                               "-noNotificationPrompt", "YES"]
        app.launch()
        _ = app.buttons["กลับหน้ารายการงาน"].waitForExistence(timeout: 300)
        app.terminate()
    }

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

    /// Back from a pushed screen (its iPad header's `กลับหน้าหลัก`, or the one-page daily report's `ย้อนกลับ`) to the page.
    func back(_ app: XCUIApplication) {
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", ["กลับหน้าหลัก", "ย้อนกลับ"])).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), "the pushed screen should have a back button")
        button.tap()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: 8), "back should return to the page")
    }

    /// `แผนก่อสร้าง` (docs/ui/install-tracking-ipad-v2 §6) is a tab of the page: a stage's chevron hides its sub-tasks,
    /// `ตาราง` shows the table and `แก้ไขแผน` pushes the MP plan screen.
    func testPlanTab() {
        let app = launch([])
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label == %@", "แผนก่อสร้าง")).firstMatch.tap()
        let stage = app.descendants(matching: .any)["plan-stage-4"]
        XCTAssertTrue(stage.waitForExistence(timeout: 8), "แผนก่อสร้าง should open the tab in the page")
        XCTAssertTrue(pageBack(app).exists, "the tab stays on the page")
        let sub = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "4.1 ")).firstMatch
        XCTAssertTrue(sub.waitForExistence(timeout: 8), "the running stage starts open")
        stage.tap()
        XCTAssertTrue(waitGone(sub), "the chevron should hide the stage's sub-tasks")
        stage.tap()
        XCTAssertTrue(sub.waitForExistence(timeout: 8), "a second tap shows them again")

        app.buttons.matching(NSPredicate(format: "label == %@", "ตาราง")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan-table"].waitForExistence(timeout: 8), "ตาราง should show the table")
        XCTAssertFalse(stage.exists)

        app.buttons.matching(NSPredicate(format: "label == %@", "แก้ไขแผน")).firstMatch.tap()
        XCTAssertTrue(waitGone(pageBack(app)), "แก้ไขแผน should push the MP plan screen")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "แผนงาน MP")).firstMatch.waitForExistence(timeout: 8))
        back(app)
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

    /// The board of 21 ต.ค. 2569 (docs/ui/install-tracking-ipad-overview): `4.2 ขนานไฟ (กฟภ.)` lists the station's 11
    /// papers, and a row of `อุปกรณ์ที่ติดตั้ง` pushes the device list with `เปิดบันทึก ›`.
    func testGridAndDevicesTiles() {
        let app = launch()
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        let grid = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "4.2 ขนานไฟ (กฟภ.)")).firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        grid.tap()
        let papers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "4.2-"))
        XCTAssertTrue(papers.firstMatch.waitForExistence(timeout: 8), "the tile should list its papers")
        XCTAssertEqual(papers.count, 11)
        app.buttons["ปิด"].firstMatch.tap()
        XCTAssertTrue(waitGone(papers.firstMatch))

        let devices = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "อุปกรณ์ที่ติดตั้ง")).firstMatch
        XCTAssertTrue(devices.waitForExistence(timeout: 8))
        devices.tap()
        let open = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "เปิดบันทึก")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 8), "each device kind should offer เปิดบันทึก")
        open.tap()
        XCTAssertTrue(waitGone(pageBack(app)), "เปิดบันทึก should push the device list")
        XCTAssertTrue(app.staticTexts["อุปกรณ์ที่ติดตั้ง"].waitForExistence(timeout: 8), "the device list should open")
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
        let draft = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ทำต่อ | ส่ง")).firstMatch
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

    /// A late task's sheet keeps the picked cause in the job (`-installLate YES` moves the station's plan back so 2.2 is
    /// past its end with nothing done): it is still picked after a relaunch, and tapping it again clears it.
    func testLateCauseIsKept() {
        func open() -> XCUIApplication {
            let app = launch(["-installStage", "2", "-installLate", "YES"], demo: false)
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

    /// `ทดสอบ IEC 62446` opens the IEC test (seeded with the แพรกหนามแดง sample); the after band opens step 4's page, and
    /// a Vmp typed for String 1 (photo first, from the stub camera) is kept after going back and in again. It starts
    /// from a fresh sample (`reset`): readings the other IEC tests left on the station would change the step's flow.
    func testIECTabTypesAReading() {
        let app = launch(["-iecDemo", "reset", "-iecCameraStub", "YES"], demo: false)
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ทดสอบ IEC 62446")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ทดสอบระบบ IEC 62446"].waitForExistence(timeout: 10), "the tab should open the IEC test")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "หลังการเชื่อมต่อระบบ")).firstMatch.tap()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "มิเตอร์ V")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the band should open step 4's page")
        card.tap()
        let clear = app.buttons["ล้างค่า"]
        XCTAssertTrue(clear.waitForExistence(timeout: 15), "the photo, then the dialog")
        // a key tapped while the dialog still moves can land on its neighbour: check the field, and type again once
        let typed = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "612.5 V")).firstMatch
        for _ in 0..<2 where !typed.exists {
            clear.tap()
            for c in "612.5" { app.buttons[c == "." ? "จุด" : String(c)].tap() }
            _ = typed.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(typed.exists, "the pad should type 612.5")
        // the dialog's `บันทึก ไป …`, not the page's `บันทึกร่างตอนนี้` under it
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "บันทึก ")).firstMatch.tap()
        // on to the clamp's dialog; closed there
        XCTAssertTrue(app.buttons["ปิด"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["ปิด"].firstMatch.tap()
        // the card reads `มิเตอร์ V 612.5 V` (its parts are one accessibility element)
        let kept = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "มิเตอร์ V", "612.5")).firstMatch
        XCTAssertTrue(kept.waitForExistence(timeout: 10), "the reading should show on String 1's card")
        app.buttons["กลับ"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "หลังการเชื่อมต่อระบบ")).firstMatch.tap()
        XCTAssertTrue(kept.waitForExistence(timeout: 15), "the reading should be kept")
    }

    /// `กรอกทีละสตริง`: from the before table, a selected string opens; the pad types IR +E after `ถัดไป` moves past the
    /// voltage and current, and the stub camera fills the voltage photo.
    func testIECStringEntryTypesAndTakesAPhoto() {
        let app = launch(["-iecDemo", "YES", "-iecCameraStub", "YES"], demo: false)
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ทดสอบ IEC 62446")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ก่อนการเชื่อมต่อระบบ")).firstMatch.tap()
        // on iPad the band opens step 2's page; its ถัดไป opens the before table
        let toTable = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ถัดไป 3/7")).firstMatch
        XCTAssertTrue(toTable.waitForExistence(timeout: 10))
        toTable.tap()
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

    /// `เอกสาร` (docs/ui/install-tracking-ipad-docs) is a tab of the page: step 2 lists its papers, a row selects and the
    /// panel's title follows, `เปิดเอกสาร` opens the paper's sheet, and on the example station (under 200 kVA) step 3 reads
    /// `ไม่ต้องยื่น`.
    func testDocsTab() {
        let app = launch([])
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label == %@", "เอกสาร")).firstMatch.tap()
        let grid = app.buttons["docsStep.grid_connection"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8), "เอกสาร should open the tab in the page")
        XCTAssertTrue(pageBack(app).exists, "the tab stays on the page")
        XCTAssertTrue(app.buttons["docsStep.pk2"].label.contains("ไม่ต้องยื่น"), app.buttons["docsStep.pk2"].label)
        grid.tap()
        let row = app.buttons["docsPaper.site_map"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "step 2 should list its papers")
        row.tap()
        let title = app.staticTexts["docsDetailTitle"]
        let follows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Google Map'"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [follows], timeout: 5), .completed, title.label)
        app.buttons["docsOpen"].tap()
        XCTAssertTrue(app.navigationBars["เอกสาร"].waitForExistence(timeout: 8), "เปิดเอกสาร should open the paper's sheet")
    }

    /// `คำขอรายสัปดาห์` (docs/ui/install-tracking-ipad-weekly-request) is a tab of the page on the board's example: a crew
    /// day cell switches a role off and the day's total drops, a work day cell adds a day, `ส่งขออนุมัติ (PDF)` waits for
    /// the signature sheet's `ยืนยันลายเซ็น`, and `ดู PDF` opens its sheet. Nothing is kept.
    func testRequestTab() {
        let app = launch([])
        XCTAssertTrue(pageBack(app).waitForExistence(timeout: slow))
        app.buttons.matching(NSPredicate(format: "label == %@", "คำขอรายสัปดาห์")).firstMatch.tap()
        let cell = app.buttons["crewCell0-0"]
        XCTAssertTrue(cell.waitForExistence(timeout: 8), "คำขอรายสัปดาห์ should open the tab in the page")
        XCTAssertTrue(pageBack(app).exists, "the tab stays on the page")
        let day = app.staticTexts["crewDay0"]
        let before = Int(day.label) ?? 0
        cell.tap()
        let fewer = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(before - 1)"), object: day)
        XCTAssertEqual(XCTWaiter().wait(for: [fewer], timeout: 5), .completed, "a role off should take its people off the day: \(day.label)")
        let workDay = app.staticTexts["workDay3"]
        scrollTo(app.buttons["workCell3.1-3"], in: app)
        XCTAssertEqual(workDay.label, "–")
        app.buttons["workCell3.1-3"].tap()
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1 งาน"), object: workDay)
        XCTAssertEqual(XCTWaiter().wait(for: [one], timeout: 5), .completed, workDay.label)
        let send = app.buttons["requestSend"]
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled, "ส่งขออนุมัติ waits for the signature")
        app.buttons["requestSign"].tap()
        let pad = app.descendants(matching: .any).matching(identifier: "signaturePad").firstMatch
        XCTAssertTrue(pad.waitForExistence(timeout: 8))
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        app.buttons["requestSignConfirm"].tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: send)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 8), .completed, "ยืนยันลายเซ็น should enable the send")
        app.buttons["requestPDF"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["requestPDFPage"].waitForExistence(timeout: 10), "ดู PDF should open its sheet")
    }

    /// A contractor on a sent week sees no steppers.
    func testRequestTabSentIsReadOnlyForAContractor() {
        let app = launch(["-installTab", "request", "-installRequestState", "sent", "-role", "external"])
        XCTAssertTrue(app.buttons["crewCell0-0"].waitForExistence(timeout: slow))
        XCTAssertFalse(app.buttons["crew0Plus"].exists, "a sent request is read only for a contractor")
        XCTAssertFalse(app.buttons["requestSend"].exists)
    }

    /// Scrolls the request's form up until the element can be tapped.
    func scrollTo(_ e: XCUIElement, in app: XCUIApplication) {
        let form = app.scrollViews["requestForm"]
        for _ in 0..<8 where !(e.exists && e.isHittable) { form.swipeUp(velocity: .slow) }
    }
}

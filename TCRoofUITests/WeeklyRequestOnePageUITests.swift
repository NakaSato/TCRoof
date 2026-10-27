import XCTest

/// The iPad one-page คำขอรายสัปดาห์ (docs/ui/weekly-request-ipad-map) on the board's example (`-requestDemo YES`, in
/// memory, nothing saved): a day chip, a pin, a `+` ghost, the risk sheet, the send button, the PDF sheet and the week
/// row. iPad simulator: `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>'
/// -only-testing:TCRoofUITests/WeeklyRequestOnePageUITests -derivedDataPath <scratch>`.
/// `TEST_RUNNER_REQUEST_SHOTS=<folder>` makes `testStateShots` save the board's states 01–13 there in landscape.
final class WeeklyRequestOnePageUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "request", "-routineRequest", "onepage", "-requestDemo", "YES", "-role", "internal",
                               "-noNotificationPrompt", "YES"] + extra
        app.launch()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the one-page layout is iPad only")
        XCTAssertTrue(app.descendants(matching: .any)["requestTitle"].waitForExistence(timeout: slow), "the one page should open")
        return app
    }

    func waitFor(_ predicate: NSPredicate, _ object: Any, _ message: String) {
        let done = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: object)], timeout: 10)
        XCTAssertEqual(done, .completed, message)
    }

    func testLinesPinsAndRisk() throws {
        let app = try launch()

        // a day chip toggles and the line's tag becomes แก้วัน
        let line1 = app.descendants(matching: .any)["requestLine1"]
        XCTAssertTrue(line1.waitForExistence(timeout: 10))
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'requestDay1-'")).element(boundBy: 0)
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let before = chip.value as? String ?? ""
        chip.tap()
        waitFor(NSPredicate(format: "value != %@", before), chip, "the day chip should toggle")
        let edited = line1.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "แก้วัน")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 5), "a day off the plan's should tag the line แก้วัน")

        // a pin selects its line
        let pin2 = app.buttons["requestPin2"]
        XCTAssertTrue(pin2.exists)
        pin2.tap()
        waitFor(NSPredicate(format: "isSelected == true"), pin2, "the pin should select line 2")

        // a + ghost adds a line
        let lines = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'requestLine' AND NOT identifier == 'requestLines'"))
        let count = lines.count
        let ghost = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "เพิ่มงานตามแผน MP")).firstMatch
        XCTAssertTrue(ghost.exists, "the example has MP tasks not asked for yet")
        ghost.tap()
        waitFor(NSPredicate(format: "count == %d", count + 1), lines, "the + should add a line")

        // a hazard chip opens the sheet; a cell changes the level and บันทึกระดับ keeps it
        pin2.tap()
        let hazard = app.buttons["requestHazard"].firstMatch
        XCTAssertTrue(hazard.waitForExistence(timeout: 5), "the selected line shows its hazards")
        let label = hazard.label
        hazard.tap()
        XCTAssertTrue(app.descendants(matching: .any)["requestRiskSheet"].waitForExistence(timeout: 5))
        app.buttons["riskCell5-5"].tap()
        let band = app.staticTexts["riskBand"]
        waitFor(NSPredicate(format: "label == %@", "สูงมาก"), band, "5 × 5 is สูงมาก")
        app.buttons["riskSave"].tap()
        let kept = app.buttons.matching(NSPredicate(format: "identifier == 'requestHazard' AND label == %@", label)).firstMatch
        waitFor(NSPredicate(format: "value == %@", "สูงมาก"), kept, "the chip should keep the saved level")
    }

    func testSendPreviewAndWeek() throws {
        let app = try launch()

        // unsigned: ส่งขออนุมัติ is off
        let send = app.buttons["requestSendNow"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertFalse(send.isEnabled, "nothing signed yet")

        // ดูตัวอย่างคำขอ opens the PDF sheet
        app.buttons["requestPreview"].tap()
        let close = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "ปิด", "เสร็จ")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the R1 PDF sheet should open")
        close.tap()

        // ‹ moves a week back
        let title = app.descendants(matching: .any)["requestTitle"]
        let before = title.label
        XCTAssertTrue(app.buttons["requestWeekBack"].waitForExistence(timeout: 10))
        app.buttons["requestWeekBack"].tap()
        waitFor(NSPredicate(format: "label != %@", before), title, "‹ should open the week before")

        // signed: ส่งขออนุมัติ is on
        app.terminate()
        let signed = try launch(["-requestState", "signed"])
        let on = signed.buttons["requestSendNow"]
        XCTAssertTrue(on.waitForExistence(timeout: 10))
        waitFor(NSPredicate(format: "isEnabled == true"), on, "signed with every part filled, it can be sent")
    }

    /// The board's states 01–13 in landscape, saved as `states/`'s names when `TEST_RUNNER_REQUEST_SHOTS` is set (state
    /// 05 taps the tools tab's count menu, which no flag can open).
    func testStateShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["REQUEST_SHOTS"] else { throw XCTSkip("no REQUEST_SHOTS folder") }
        let states: [(String, [String])] = [
            ("01-draft", []), ("02-line2-selected", ["-requestState", "line2"]), ("03-week-picker", ["-requestState", "weeks"]),
            ("04-work-time", ["-requestState", "worktime"]), ("05-tools-dropdown", ["-requestState", "tools"]),
            ("06-risk-sheet", ["-requestState", "risk"]), ("07-line-no-days", ["-requestState", "nodays"]),
            ("08-signed-ready", ["-requestState", "signed"]), ("09-sent", ["-requestState", "sent"]),
            ("10-approved", ["-requestWeek", "-1"]), ("11-empty-week", ["-requestState", "empty"]),
            ("12-map-full", ["-requestState", "map"]), ("13-pdf-preview", ["-requestState", "pdf"]),
        ]
        for (name, args) in states {
            XCUIDevice.shared.orientation = .landscapeLeft
            let app = try launch(args)
            if name == "05-tools-dropdown" {
                let menu = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "ชิ้น")).firstMatch
                XCTAssertTrue(menu.waitForExistence(timeout: 10), "the tools rows have count menus")
                menu.tap()
                XCTAssertTrue(app.buttons["ลบออก"].waitForExistence(timeout: 5))
            }
            sleep(2)
            // the screen, not `app.screenshot()`: the app element's shot comes back sideways and cropped in landscape
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            app.terminate()
        }
    }
}

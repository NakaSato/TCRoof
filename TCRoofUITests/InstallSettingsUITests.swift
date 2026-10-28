import XCTest

/// The iPad install tracking page's `ตั้งค่าโครงการ` tab (docs/ui/install-tracking-ipad-settings) on the board's example
/// station (`-installDemo YES`, in memory, nothing saved): `-only-testing:TCRoofUITests/InstallSettingsUITests` on an
/// iPad simulator. The tab opens in the page, a category switches, a picker change shows the unsaved bar and
/// `ยกเลิกการแก้` clears it, and the upload stays off until a file and a reason are given.
final class InstallSettingsUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-installDemo", "YES",
                               "-noNotificationPrompt", "YES", "-pwaDocsCameraStub", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["กลับหน้ารายการงาน"].waitForExistence(timeout: slow), "the install page should open")
        guard app.windows.firstMatch.frame.width > 900 else { throw XCTSkip("the iPad page's tab, on an iPad simulator") }
        return app
    }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func waitEnabled(_ element: XCUIElement, _ enabled: Bool, timeout: TimeInterval = 8) -> Bool {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled)), object: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    func openTab(_ app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label == %@", "ตั้งค่าโครงการ")).firstMatch.tap()
        XCTAssertTrue(app.buttons["padSettings.team"].waitForExistence(timeout: 8), "ตั้งค่าโครงการ should open in the page")
    }

    func testCategoryPickerAndUnsavedBar() throws {
        let app = try launch()
        openTab(app)
        XCTAssertTrue(app.buttons["กลับหน้ารายการงาน"].exists, "the tab stays on the page")
        XCTAssertTrue(app.staticTexts["วิศวกรผู้ควบคุมงาน"].exists, "ทีมและสิทธิ์ is the first category")

        app.buttons["padSettings.routine"].tap()
        let allDays = app.buttons["ทุกวัน"]
        XCTAssertTrue(allDays.waitForExistence(timeout: 8), "รอบรายงาน should show the working days picker")
        let bar = app.descendants(matching: .any)["padSettings.unsavedBar"]
        XCTAssertFalse(bar.exists, "no bar before an edit")

        allDays.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "a picker change should show the unsaved bar")
        XCTAssertTrue(app.staticTexts["แก้ไข 1 รายการ | ยังไม่บันทึก"].exists)
        XCTAssertTrue(allDays.isSelected, "the picked segment is selected")

        app.buttons["ยกเลิกการแก้"].tap()
        XCTAssertTrue(waitGone(bar), "ยกเลิกการแก้ should drop the draft")
        XCTAssertFalse(allDays.isSelected, "the kept working days come back")
    }

    func testLeavingWithEditsAsks() throws {
        let app = try launch(["-installSettings", "connection"])
        openTab(app)
        let parallel = app.buttons["ขนานไฟ (ขายคืน)"]
        XCTAssertTrue(parallel.waitForExistence(timeout: 8))
        parallel.tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "ภาพรวม")).firstMatch.tap()
        let stay = app.alerts.buttons["อยู่ต่อ"]
        XCTAssertTrue(stay.waitForExistence(timeout: 8), "leaving the tab with an edit should ask first")
        stay.tap()
        XCTAssertTrue(parallel.isSelected, "อยู่ต่อ keeps the edit")
    }

    func testUploadNeedsFileAndReason() throws {
        let app = try launch(["-installSettings", "drawings"])
        openTab(app)
        let upload = app.buttons["padSettings.upload"]
        XCTAssertTrue(upload.waitForExistence(timeout: 8), "แบบก่อสร้าง should offer the upload to the team")
        upload.tap()

        let confirm = app.buttons["padSheet.uploadConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "the upload sheet should open")
        XCTAssertTrue(waitEnabled(confirm, false), "off with no file")
        XCTAssertTrue(confirm.label.hasPrefix("อัปโหลด REV 0"), "the button names the REV")
        XCTAssertNotEqual(confirm.label, "อัปโหลด REV 00", "an existing drawing takes its next REV")

        app.buttons["padSheet.scan"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["padSheet.fileName"].waitForExistence(timeout: 8), "the stub camera gives a file")
        XCTAssertTrue(waitEnabled(confirm, false), "still off without a reason from REV 01")

        let reason = app.textFields["padSheet.reason"].exists ? app.textFields["padSheet.reason"] : app.textFields.element(boundBy: 0)
        reason.tap()
        reason.typeText("ย้ายแนวราง")
        XCTAssertTrue(waitEnabled(confirm, true), "on once a file and a reason are given")

        confirm.tap()
        XCTAssertTrue(waitGone(confirm), "the sheet closes after the upload")
    }

    /// With `TEST_RUNNER_SETTINGS_SHOTS=<folder>`, saves the board's states there named like `states/` (05 and 08, the
    /// categories left out, have none).
    func testStateShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SETTINGS_SHOTS"] else { throw XCTSkip("TEST_RUNNER_SETTINGS_SHOTS not set") }
        let states: [(String, [String], String?)] = [
            ("01-team", [], nil),
            ("02-document-header", ["-installSettings", "header"], nil),
            ("03-drawings", ["-installSettings", "drawings"], nil),
            ("04-report-cycle", ["-installSettings", "routine"], nil),
            ("06-connection-iec", ["-installSettings", "connection"], nil),
            ("07-reference", ["-installSettings", "reference"], nil),
            ("09-text-editor", ["-installSettingsState", "edit"], "padSheet.text"),
            ("10-unsaved-bar", ["-installSettingsState", "dirty"], "padSettings.unsavedBar"),
            ("11-revision-history", ["-installSettingsState", "history"], "padSheet.uploadNext"),
            ("12-upload-revision", ["-installSettingsState", "upload"], "padSheet.uploadConfirm"),
            ("13-person-sheet", ["-installSettingsState", "person"], "padSheet.remove"),
        ]
        for (name, extra, wait) in states {
            let app = try launch(["-installTab", "settings"] + extra)
            XCTAssertTrue(app.buttons["padSettings.team"].waitForExistence(timeout: 15), name)
            if let wait { XCTAssertTrue(app.descendants(matching: .any)[wait].firstMatch.waitForExistence(timeout: 15), name) }
            _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 1.5)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            app.terminate()
        }
    }
}

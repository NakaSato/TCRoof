import XCTest

/// `บันทึกเครื่องมือและรถ` on iPad (docs/ui/tools-log-ipad, issues #260–#266) with the board's example log
/// (`-toolLogDemo YES`, `-toolsDemo YES`; nothing is saved), in landscape:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/ToolLogPadUITests -derivedDataPath <scratch>`.
/// The `รถ` tab narrows both tables, `วันนี้` + `เติมน้ำมัน` shows the empty note, `โหลดเพิ่ม` adds rows, `บันทึกคืน` opens
/// the give-back form, a vehicle row picks the primary button, `ส่งออก CSV` opens the share sheet, and the tab's row
/// pushes the screen. `TEST_RUNNER_TOOLLOG_SHOTS=<folder>` makes `testStateShots` save the board's states there.
final class ToolLogPadUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the ledger is the iPad's") }
    }

    func launch(_ extra: [String] = [], screen: [String] = ["-screen", "toollog"]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = screen + ["-toolLogDemo", "YES", "-toolsDemo", "YES", "-noNotificationPrompt", "YES"] + extra
        app.launchInThai()
        XCTAssertTrue(app.buttons["toollog.kind.all"].waitForExistence(timeout: slow), "the ledger opens")
        return app
    }

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The log's rows (`toollog.log.<event id>`; a demo event's id starts with its item).
    func logRows(_ app: XCUIApplication, item: String = "") -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "toollog.log." + item))
    }

    func footer(_ app: XCUIApplication) -> String { element(app, "toollog.footer").label }

    func waitGone(_ e: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func waitLabel(_ e: XCUIElement, _ label: String, _ message: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: e)
        XCTAssertEqual(XCTWaiter().wait(for: [match], timeout: 8), .completed, message + " (reads \(e.label))")
    }

    func testCarTabNarrowsBothTables() {
        let app = launch()
        XCTAssertTrue(element(app, "toollog.out.t376").exists, "a borrowed tool is out")
        XCTAssertTrue(element(app, "toollog.out.v1").exists, "the D-Max is out")
        XCTAssertGreaterThan(logRows(app, item: "f1587").count, 0, "a tool's return in the log")

        app.buttons["toollog.kind.car"].tap()
        XCTAssertTrue(waitGone(element(app, "toollog.out.t376")), "the tools leave the out-now table")
        XCTAssertTrue(element(app, "toollog.out.v1").exists)
        XCTAssertEqual(logRows(app, item: "f1587").count, 0, "and the log")
        XCTAssertGreaterThan(logRows(app, item: "v2").count, 0)
        XCTAssertEqual(footer(app), "แสดง 6 จาก 6 รายการ", "the vehicles' six entries")
    }

    func testTodaysFuelIsEmpty() {
        let app = launch()
        app.buttons["toollog.range.0"].tap()      // วันนี้
        app.buttons["toollog.action.5"].tap()     // เติมน้ำมัน
        waitLabel(element(app, "toollog.footer"), "แสดง 0 จาก 0 รายการ · ไม่มีรายการตามตัวกรองนี้", "the empty note")
        XCTAssertEqual(logRows(app).count, 0)
        XCTAssertFalse(element(app, "toollog.more").exists)
    }

    func testLoadMore() {
        let app = launch()
        XCTAssertEqual(footer(app), "แสดง 10 จาก 12 รายการ", "7 วัน by default")
        XCTAssertEqual(logRows(app).count, 10)
        app.buttons["toollog.more"].tap()
        waitLabel(element(app, "toollog.footer"), "แสดง 12 จาก 12 รายการ", "โหลดเพิ่ม adds the rest")
        XCTAssertEqual(logRows(app).count, 12)
        XCTAssertTrue(waitGone(app.buttons["toollog.more"]), "nothing more to load")
        // a filter starts again at 10
        app.buttons["toollog.range.3"].tap()      // ทั้งหมด
        waitLabel(element(app, "toollog.footer"), "แสดง 10 จาก 13 รายการ", "a filter change shows 10 again")
    }

    func testGiveBackFormOpensAndCancels() {
        let app = launch()
        let back = app.buttons["toollog.out.drone"]
        XCTAssertTrue(back.exists)
        XCTAssertEqual(back.label, "บันทึกคืน")
        back.tap()
        let title = app.navigationBars["รับคืนเครื่องมือ"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the give-back form")
        app.buttons["ยกเลิก"].firstMatch.tap()
        XCTAssertTrue(waitGone(title))
        XCTAssertEqual(app.buttons["toollog.out.v1"].label, "บันทึกคืนรถ", "a car's row returns the car")
    }

    func testVehicleSelection() {
        let app = launch()
        let primary = app.buttons["toollog.vehicle.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertEqual(primary.label, "คืนรถ · บันทึกไมล์", "the first vehicle out is selected")
        element(app, "toollog.vehicle.v2").tap()     // Toyota Commuter, parked
        waitLabel(primary, "ออกรถคันนี้", "a free vehicle goes out")
        XCTAssertTrue(element(app, "toollog.vehicle.v2").isSelected)
        // `ประวัติ` turns the left card to this vehicle
        app.buttons["toollog.history"].tap()
        XCTAssertTrue(app.buttons["toollog.kind.car"].isSelected)
        waitLabel(element(app, "toollog.footer"), "แสดง 3 จาก 3 รายการ", "its three entries")
    }

    func testCSVOpensTheShareSheet() {
        let app = launch()
        app.buttons["toollog.csv"].tap()
        let share = app.otherElements.matching(identifier: "ActivityListView").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the share sheet with the file")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else if app.buttons["ปิด"].exists { app.buttons["ปิด"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap() }
        XCTAssertTrue(waitGone(share, timeout: 10))
        XCTAssertTrue(app.staticTexts["ส่งออก CSV 12 รายการตามตัวกรองที่เลือก"].waitForExistence(timeout: 5), "the toast")
    }

    /// The `เครื่องมือ` tab's row pushes the ledger, and back returns.
    func testTabRowPushesTheLedger() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "tools", "-toolLogDemo", "YES", "-toolsDemo", "YES", "-noNotificationPrompt", "YES"]
        app.launchInThai()
        let row = app.buttons["toollog.row"]
        XCTAssertTrue(row.waitForExistence(timeout: slow), "the tab's row")
        row.tap()
        XCTAssertTrue(app.buttons["toollog.kind.all"].waitForExistence(timeout: 10))
        app.buttons["toollog.back"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
    }

    /// The board's states (docs/ui/tools-log-ipad/states), saved under their names when `TEST_RUNNER_TOOLLOG_SHOTS` is set.
    /// State 08 (`จองแล้ว`) has no stored source and is left out.
    func testStateShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["TOOLLOG_SHOTS"] else { throw XCTSkip("no TOOLLOG_SHOTS folder") }
        let states: [(String, [String])] = [
            ("01-all", []), ("02-tools", ["-toolLogFilter", "tool"]), ("03-cars", ["-toolLogFilter", "car"]),
            ("04-today", ["-toolLogRange", "today"]), ("05-30days-returns", ["-toolLogRange", "30", "-toolLogAction", "giveBack"]),
            ("06-no-match", ["-toolLogRange", "today", "-toolLogAction", "fuel"]), ("07-car-free", ["-toolLogVehicle", "v2"]),
            ("09-load-more", ["-toolLogMore", "YES"]), ("10-toast", []),
        ]
        func shoot(_ name: String) throws {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
        for (name, args) in states {
            let app = launch(args)
            if name == "10-toast" {
                app.buttons["toollog.csv"].tap()
                let share = app.otherElements.matching(identifier: "ActivityListView").firstMatch
                XCTAssertTrue(share.waitForExistence(timeout: 30))
                if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap() }
                XCTAssertTrue(app.staticTexts["ส่งออก CSV 12 รายการตามตัวกรองที่เลือก"].waitForExistence(timeout: 5))
            } else {
                sleep(2)
            }
            try shoot(name)
            app.terminate()
        }
    }
}

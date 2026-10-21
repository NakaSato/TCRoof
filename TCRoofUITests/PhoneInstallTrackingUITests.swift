import XCTest

/// The iPhone install tracking page (docs/ui/install-tracking-iphone) on an iPhone simulator with the board's example:
/// `-only-testing:TCRoofUITests/PhoneInstallTrackingUITests`. Every pill opens its content in the page, a Gantt stage
/// opens and closes its sub-tasks, `Gantt | S-Curve` switches, a document tile opens its target, the plan's edit mode
/// needs a reason before `บันทึก` and `ยกเลิก` restores it, and the gear opens `ตั้งค่าเฉพาะโครงการ` and a category.
/// Nothing is saved (`-installDemo YES`). Skipped on iPad.
final class PhoneInstallTrackingUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUpWithError() throws {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad { throw XCTSkip("the iPhone page") }
    }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-installOpen", "YES", "-installDemo", "YES", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func text(_ app: XCUIApplication, beginsWith s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", s)).firstMatch
    }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func waitEnabled(_ element: XCUIElement, _ enabled: Bool, timeout: TimeInterval = 8) -> Bool {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled)), object: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    func testEveryPillOpensItsContent() {
        let app = launch()
        XCTAssertTrue(any(app, "installTab.overview").waitForExistence(timeout: slow), "an installing station opens the page on iPhone")
        XCTAssertTrue(any(app, "install.actions").exists, "ภาพรวม starts with the KPI card")
        let marks: [(String, XCUIElement)] = [
            ("daily", text(app, beginsWith: "ทั้งหมด")),
            ("request", text(app, beginsWith: "คำขอปฏิบัติงานรายสัปดาห์")),
            ("weekly", text(app, beginsWith: "ความพร้อมก่อนส่ง")),
            ("iec", text(app, beginsWith: "ทดสอบ IEC 62446-1")),
            ("docs", text(app, beginsWith: "เส้นทางขออนุญาต")),
            ("plan", any(app, "plan.view")),
            ("overview", any(app, "install.actions")),
        ]
        for (tab, mark) in marks {
            let pill = any(app, "installTab.\(tab)")
            // the strip scrolls to the selected pill; the first one is back at its start
            if tab == "overview" { any(app, "installTabs").swipeRight(); any(app, "installTabs").swipeRight() }
            pill.tap()
            XCTAssertTrue(mark.waitForExistence(timeout: 8), "\(tab) should show its content in the page")
            XCTAssertTrue(pill.isSelected, "\(tab)'s pill should be selected")
        }
    }

    func testOverviewGanttAndTiles() {
        let app = launch()
        let stage = any(app, "installStage.4")
        XCTAssertTrue(stage.waitForExistence(timeout: slow))
        let sub = text(app, beginsWith: "สายสตริง 1–6")
        XCTAssertTrue(sub.waitForExistence(timeout: 8), "the running stage starts open")
        stage.tap()
        XCTAssertTrue(waitGone(sub), "a tap on the stage hides its sub-tasks")
        stage.tap()
        XCTAssertTrue(sub.waitForExistence(timeout: 8), "a second tap shows them again")

        app.buttons["S-Curve"].firstMatch.tap()
        XCTAssertTrue(any(app, "install.curve").waitForExistence(timeout: 8), "S-Curve shows the curve")
        XCTAssertFalse(stage.exists)
        app.buttons["Gantt"].firstMatch.tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 8), "Gantt comes back")

        let tile = any(app, "installDoc.daily")
        for _ in 0..<4 where !tile.isHittable { app.swipeUp() }
        tile.tap()
        XCTAssertTrue(any(app, "installTab.daily").isSelected, "the Daily Report tile opens รายงานประจำวัน")
    }

    func testPlanEditNeedsAReason() {
        let app = launch(["-installTab", "plan"])
        let edit = any(app, "plan.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: slow))
        edit.tap()
        let reason = any(app, "plan.reason"), save = any(app, "plan.save")
        XCTAssertTrue(reason.waitForExistence(timeout: 8), "edit mode shows the reason strip")
        XCTAssertTrue(any(app, "plan-table").exists, "edit mode works in the table")
        XCTAssertFalse(save.isEnabled, "nothing changed yet")
        app.buttons["เลื่อนวันเริ่มหลัง 5"].firstMatch.tap()
        XCTAssertFalse(save.isEnabled, "a change without a reason can't be saved")
        reason.tap()
        reason.typeText("ฝนตก เลื่อนงาน AC")
        XCTAssertTrue(waitEnabled(save, true), "a change with a reason can be saved")
        XCTAssertTrue(save.label.contains("1 งาน"))
        any(app, "plan.cancel").tap()
        XCTAssertTrue(waitGone(reason), "ยกเลิก leaves edit mode")
        edit.tap()
        XCTAssertTrue(waitEnabled(any(app, "plan.save"), false), "ยกเลิก restored the plan")
        any(app, "plan.cancel").tap()
    }

    func testSettingsOpensACategory() {
        let app = launch()
        XCTAssertTrue(any(app, "installTab.overview").waitForExistence(timeout: slow))
        app.buttons["ตั้งค่าเฉพาะโครงการ"].tap()
        XCTAssertTrue(text(app, beginsWith: "ตั้งค่าเฉพาะโครงการนี้").waitForExistence(timeout: 8), "the gear opens ตั้งค่าเฉพาะโครงการ")
        let routine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "รอบรายงาน")).firstMatch
        XCTAssertTrue(routine.waitForExistence(timeout: 8))
        XCTAssertFalse(any(app, "installTab.overview").exists, "the tab strip hides while it is open")
        routine.tap()
        XCTAssertTrue(text(app, beginsWith: "วันทำงาน").waitForExistence(timeout: 8), "รอบรายงาน lists its values")
        any(app, "settings.back").tap()
        XCTAssertTrue(routine.waitForExistence(timeout: 8), "หมวดทั้งหมด goes back to the list")
        app.buttons["ตั้งค่าเฉพาะโครงการ"].tap()
        XCTAssertTrue(any(app, "installTab.overview").waitForExistence(timeout: 8), "the gear again closes it")
    }

    // MARK: board states

    var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TCRoofKit/Tests/ExcelExportTests/Fixtures/mp-weekly-bangsai.xlsx").standardized
    }

    func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["INSTALL_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// With `TEST_RUNNER_INSTALL_SHOTS=<folder>`, saves the board's states that need a tap (docs/ui/install-tracking-iphone
    /// `states/` names): the late station, its S-curve and plan, the Excel menu and the import sheet. The sheet is closed
    /// without importing.
    func testBoardStates() throws {
        guard ProcessInfo.processInfo.environment["INSTALL_SHOTS"] != nil else { throw XCTSkip("set TEST_RUNNER_INSTALL_SHOTS") }
        var app = launch(["-installDemo", "late"])
        XCTAssertTrue(any(app, "installStage.4").waitForExistence(timeout: slow))
        sleep(1); shot("02-overview-late")
        app.buttons["S-Curve"].firstMatch.tap()
        XCTAssertTrue(any(app, "install.curve").waitForExistence(timeout: 8))
        sleep(1); shot("04-overview-scurve-late")
        app.terminate()

        app = launch(["-installDemo", "late", "-installTab", "plan"])
        XCTAssertTrue(any(app, "plan.edit").waitForExistence(timeout: slow))
        sleep(1); shot("15-plan-gantt-late")
        app.terminate()

        app = launch(["-installTab", "plan", "-mpImportFile", fixture.path])
        XCTAssertTrue(any(app, "plan.edit").waitForExistence(timeout: slow))
        app.buttons["ไฟล์แผน Excel"].firstMatch.tap()
        let importItem = app.buttons["นำเข้าไฟล์แผน (.xlsx)"].firstMatch
        XCTAssertTrue(importItem.waitForExistence(timeout: 8), "Excel ▾ lists the import")
        sleep(1); shot("18-plan-excel-menu")
        importItem.tap()
        XCTAssertTrue(any(app, "mpImport.run").waitForExistence(timeout: 15), "the import opens its sheet")
        sleep(1); shot("19-plan-import")
        app.buttons["ปิด"].firstMatch.tap()
    }
}

import XCTest

/// จัดการผู้ใช้และสิทธิ์ (docs/ui/user-admin-ipad) on the board's demo (`-userAdminDemo YES`, nothing written; its key is
/// the board's). iPad:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>' -only-testing:TCRoofUITests/UserAdminUITests -derivedDataPath <dir>`.
/// With `TEST_RUNNER_USERADMIN_SHOTS=<folder>` the settings entry is saved there as `00-settings-entry.png`.
final class UserAdminUITests: XCTestCase {
    let slow: TimeInterval = 90
    let aree = "aree@contractor-a.example"

    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "useradmin", "-userAdminDemo", "YES", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    private func type(_ app: XCUIApplication, _ digits: String) {
        for d in digits { app.buttons["devKey.\(d)"].firstMatch.tap() }
    }

    private func text(_ app: XCUIApplication, _ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    private func waitGone(_ e: XCUIElement, _ timeout: TimeInterval = 10) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed)
    }

    func testAWrongKeyShowsTheCountAndTheRightKeyOpens() {
        let app = launch(["-userAdminWrongKey", "0"])
        XCTAssertTrue(app.buttons["devKey.1"].waitForExistence(timeout: slow))
        type(app, "111111")
        XCTAssertTrue(text(app, "คีย์ไม่ถูกต้อง · เหลือ 4 ครั้ง").waitForExistence(timeout: 5))
        type(app, "246810")
        waitGone(app.buttons["devKey.1"])
        XCTAssertTrue(app.buttons["userAdmin.lock"].isHittable, "the page is open")
    }

    func testLockingReturnsToThePad() {
        let app = launch(["-userAdminUnlocked", "YES"])
        XCTAssertTrue(app.buttons["userAdmin.lock"].waitForExistence(timeout: slow))
        XCTAssertFalse(app.buttons["devKey.1"].exists)
        app.buttons["userAdmin.lock"].tap()
        XCTAssertTrue(app.buttons["devKey.1"].waitForExistence(timeout: 5))
    }

    func testARoleEditAsksTheKeyAgainAndWaitsInThePendingBar() {
        let app = launch(["-userAdminUnlocked", "YES", "-userAdminUser", aree])
        let edit = app.buttons["userAdmin.editRole"]
        XCTAssertTrue(edit.waitForExistence(timeout: slow))
        edit.tap()
        XCTAssertTrue(text(app, "ยืนยันคีย์เพื่อแก้บทบาท").waitForExistence(timeout: 5))
        type(app, "246810")
        let team = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Internal'")).firstMatch
        XCTAssertTrue(team.waitForExistence(timeout: 5))
        team.tap()
        XCTAssertTrue(app.staticTexts["userAdmin.diff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["userAdmin.diff"].label.contains("→ ทีมภายใน"))
        XCTAssertTrue(app.staticTexts["userAdmin.pending"].label.contains("แก้ไข 1 รายการ"))
        // ยกเลิกทั้งหมด clears it
        app.buttons["ยกเลิกทั้งหมด"].tap()
        waitGone(app.staticTexts["userAdmin.pending"])
        XCTAssertFalse(app.staticTexts["userAdmin.diff"].exists)
    }

    func testTheInviteStaysOffForABadEmail() {
        let app = launch(["-userAdminUnlocked", "YES"])
        let invite = app.buttons["userAdmin.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: slow))
        invite.tap()
        XCTAssertTrue(text(app, "ยืนยันคีย์เพื่อเพิ่มผู้ใช้").waitForExistence(timeout: 5))
        type(app, "246810")
        let field = app.textFields["userAdmin.inviteEmail"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("not-an-email")
        XCTAssertFalse(app.buttons["userAdmin.inviteAdd"].isEnabled)
        XCTAssertTrue(text(app, "รูปแบบอีเมลไม่ถูกต้อง").exists)
        field.typeText("@contractor-e.co.th")
        XCTAssertTrue(app.buttons["userAdmin.inviteAdd"].isEnabled)
        app.buttons["userAdmin.inviteAdd"].tap()
        XCTAssertTrue(app.staticTexts["userAdmin.pending"].waitForExistence(timeout: 5))
    }

    func testSuspendingShowsSuspended() {
        let app = launch(["-userAdminUnlocked", "YES", "-userAdminUser", aree])
        let row = app.buttons["userAdmin.row.\(aree)"]
        XCTAssertTrue(row.waitForExistence(timeout: slow))
        XCTAssertFalse(row.label.contains("ระงับ"))
        app.buttons["userAdmin.suspend"].tap()
        XCTAssertTrue(app.buttons["userAdmin.suspend"].label.contains("เปิดใช้งานอีกครั้ง"))
        XCTAssertTrue(row.label.contains("ระงับ"), row.label)
        XCTAssertTrue(app.staticTexts["userAdmin.pending"].exists)
    }

    func testAMatrixCellChangesOnlyInEditMode() {
        let app = launch(["-userAdminUnlocked", "YES", "-userAdminTab", "roles"])
        let cell = app.buttons["userAdmin.cell.internal|tools.register"]
        XCTAssertTrue(cell.waitForExistence(timeout: slow))
        if !cell.isHittable { app.swipeUp(); app.swipeUp() }
        XCTAssertTrue(cell.label.contains("ทำได้"))
        // out of edit mode a tap asks for the key and changes nothing
        cell.tap()
        XCTAssertTrue(text(app, "ยืนยันคีย์เพื่อแก้สิทธิ์และกฎ").waitForExistence(timeout: 5))
        app.buttons["ยกเลิก"].firstMatch.tap()
        XCTAssertTrue(cell.label.contains("ทำได้"))
        cell.tap()
        type(app, "246810")
        cell.tap()
        XCTAssertTrue(cell.label.contains("มีเงื่อนไข"), cell.label)
        XCTAssertTrue(app.staticTexts["userAdmin.pending"].exists)
    }

    /// The Settings row is the Maintainer's (`users.admin`): a manager doesn't get it.
    func testTheSettingsRowIsTheMaintainers() {
        func settings(_ role: String) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-screen", "home", "-homeSettings", "YES", "-role", role, "-noNotificationPrompt", "YES"]
            app.launch()
            XCTAssertTrue(text(app, "สมาชิกทีม").waitForExistence(timeout: slow))
            for _ in 0..<4 where !app.buttons["settings.userAdmin"].exists || !app.buttons["settings.userAdmin"].isHittable {
                app.scrollViews.firstMatch.swipeUp()
            }
            return app
        }
        let manager = settings("manager")
        XCTAssertFalse(manager.buttons["settings.userAdmin"].exists, "a manager has no users.admin")
        manager.terminate()

        let dev = settings("maintainer")
        let row = dev.buttons["settings.userAdmin"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("ต้องใช้คีย์"), row.label)
        if let dir = ProcessInfo.processInfo.environment["USERADMIN_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("00-settings-entry.png"))
        }
        row.tap()
        // it opens on the lock screen; off the demo the pad waits for config/devKey, which the simulator can't read
        XCTAssertTrue(text(dev, "ใส่คีย์นักพัฒนา 6 หลัก").waitForExistence(timeout: 10), "it opens on the lock screen")
    }
}

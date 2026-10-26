import XCTest

/// The iPad one-page daily report's right column (docs/ui/daily-report-ipad-v3): the working-time popover's stepper,
/// the reporter-only sign card and the date calendar. iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>' -only-testing:TCRoofUITests/DailyOnePageUITests -derivedDataPath <scratch>`.
/// It launches `-screen daily` without `-routineDaily onepage` (an iPad is wide enough), since that flag seeds the
/// board's lines into today and moving to another day would keep them as a draft. The calendar goes first, while
/// today is unedited, and the time is changed on the sent day it opens and never saved.
final class DailyOnePageUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func testRightColumn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "daily", "-role", "internal", "-jobTeam", "none", "-noNotificationPrompt", "YES"]
        app.launch()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the one-page layout is iPad only")

        // the calendar: pick the latest sent day before this one, and the date changes
        let date = app.buttons["dailyDate"]
        XCTAssertTrue(date.waitForExistence(timeout: slow))
        let title = date.label
        date.tap()
        let sent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dailyDay-' AND label ENDSWITH %@", "ส่งแล้ว"))
        XCTAssertTrue(sent.firstMatch.waitForExistence(timeout: 5), "the seeded month has sent days")
        let day = sent.element(boundBy: sent.count - 1)
        let picked = day.label.replacingOccurrences(of: " ส่งแล้ว", with: "")
        day.tap()
        let moved = NSPredicate(format: "label == %@", picked)
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: app.buttons["dailyDate"])], timeout: 10)
        XCTAssertNotEqual(app.buttons["dailyDate"].label, title)

        // working time: + on เลิกงาน moves the chip's end by an hour (or − when it is at 20:00)
        let chip = app.buttons["dailyWorkTime"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        let before = chip.value as? String ?? ""
        chip.tap()
        let plus = app.buttons["workEnd+"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        (plus.isEnabled ? plus : app.buttons["workEnd-"]).tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "ปิด")).firstMatch.tap()
        let changed = NSPredicate(format: "value != %@", before)
        wait(for: [XCTNSPredicateExpectation(predicate: changed, object: chip)], timeout: 5)

        // the sign card is the reporter's only
        XCTAssertTrue(app.buttons["dailySign"].exists || app.buttons["ล้างลายเซ็นผู้รายงาน"].exists)
        XCTAssertFalse(app.buttons["dailyAck"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ผู้ตรวจงาน")).firstMatch.exists)
    }

    /// The TC view of a sent report (docs/ui/daily-report-ipad-v4, `-routineDailyState ack|acked`, nothing saved): the
    /// team sees `ลงนามรับทราบ` in place of the reporter's card and its box opens the inspector sheet; with a drawn
    /// acknowledgement `ยืนยันรับทราบ` is on; a contractor on the same report gets the reporter's view.
    func testTeamAcknowledgesOnThePage() throws {
        func launch(_ state: String, role: String) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-screen", "daily", "-routineDaily", "onepage", "-routineKeyPlan", "YES", "-routineDailyState", state,
                                   "-role", role, "-jobTeam", "none", "-noNotificationPrompt", "YES"]
            app.launch()
            return app
        }
        let team = launch("ack", role: "internal")
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the one-page layout is iPad only")
        let box = team.buttons["dailyAck"]
        XCTAssertTrue(box.waitForExistence(timeout: slow), "the team sees the acknowledgement card")
        XCTAssertTrue(team.staticTexts["ลงนามรับทราบ"].exists)
        XCTAssertFalse(team.staticTexts["ลงนามผู้รายงาน"].exists)
        XCTAssertFalse(team.buttons["dailyAckConfirm"].isEnabled, "nothing to confirm before the acknowledgement")
        XCTAssertTrue(team.buttons["dailySendBack"].exists)
        box.tap()
        XCTAssertTrue(team.navigationBars["Inspector รับทราบ"].waitForExistence(timeout: 10))
        team.buttons["ยกเลิก"].tap()
        team.terminate()

        let acked = launch("acked", role: "internal")
        XCTAssertTrue(acked.otherElements["dailyAckSigned"].waitForExistence(timeout: slow)
                      || acked.buttons["ล้างลายเซ็นรับทราบ"].waitForExistence(timeout: 5))
        XCTAssertTrue(acked.buttons["dailyAckConfirm"].isEnabled)
        acked.terminate()

        let contractor = launch("ack", role: "external")
        XCTAssertTrue(contractor.buttons["ล้างลายเซ็นผู้รายงาน"].waitForExistence(timeout: slow), "the reporter's signed card")
        XCTAssertFalse(contractor.buttons["dailyAck"].exists)
        XCTAssertFalse(contractor.buttons["dailySendBack"].exists)
    }

    /// The daily list's `รับทราบ` on a signed report not yet acknowledged: the team opens the inspector sheet (cancelled,
    /// nothing saved); a contractor has no button. Any simulator.
    func testDailyListAcknowledge() {
        let team = XCUIApplication()
        team.launchArguments = ["-screen", "dailies", "-role", "internal", "-jobTeam", "none", "-noNotificationPrompt", "YES"]
        team.launch()
        let ack = team.buttons["dailyListAck"].firstMatch
        XCTAssertTrue(ack.waitForExistence(timeout: slow), "the seeded latest signed days have no acknowledgement yet")
        ack.tap()
        XCTAssertTrue(team.navigationBars["Inspector รับทราบ"].waitForExistence(timeout: 10))
        team.buttons["ยกเลิก"].tap()
        team.terminate()

        let contractor = XCUIApplication()
        contractor.launchArguments = ["-screen", "dailies", "-role", "external", "-noNotificationPrompt", "YES"]
        contractor.launch()
        XCTAssertTrue(contractor.buttons["dailyListMenu"].firstMatch.waitForExistence(timeout: slow))
        XCTAssertFalse(contractor.buttons["dailyListAck"].waitForExistence(timeout: 5))
    }
}

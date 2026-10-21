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
}

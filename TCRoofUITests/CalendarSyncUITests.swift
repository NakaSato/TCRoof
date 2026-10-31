import XCTest

/// Survey appointments and the iPad Calendar (docs/specs/calendar-travel-expenses-swift.md §A): the plan row's buttons,
/// and Settings › ปฏิทิน. Any simulator. With sync on the plan row reads `ในปฏิทิน` once Calendar access is granted
/// (`xcrun simctl privacy <udid> grant calendar com.tcroof.internal`). `TEST_RUNNER_CALENDAR_SHOTS=<folder>` saves
/// the settings section as `calendar-settings.png`.
final class CalendarSyncUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    private func text(_ app: XCUIApplication, _ s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    /// An appointment in the plan offers นำทาง, โทร and ปฏิทิน; with sync off, ปฏิทิน is the manual editor.
    func testThePlanRowHasTheAppointmentButtons() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "plan", "-planDemo", "YES", "-planToday", "2026-10-25", "-planDay", "2026-10-25",
                               "-calendarSync.on", "NO", "-noNotificationPrompt", "YES"]
        app.launch()
        XCTAssertTrue(text(app, "นำทาง").waitForExistence(timeout: slow))
        XCTAssertTrue(text(app, "โทร").exists)
        let add = app.buttons["addToCalendar"].firstMatch
        XCTAssertTrue(add.exists, "sync off: the manual เพิ่มลงปฏิทิน")
        add.tap()
        // the system event editor, filled in (its title field holds the appointment)
        XCTAssertTrue(text(app, "สำรวจ |").waitForExistence(timeout: 15))
    }

    /// Settings › ปฏิทิน: the sync switch; its options show once it is on.
    func testSettingsHasTheCalendarSection() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeSettings", "YES", "-calendarSync.on", "YES", "-noNotificationPrompt", "YES"]
        app.launch()
        let toggle = app.switches["settings.calendarSync"].firstMatch
        XCTAssertTrue(text(app, "การแจ้งเตือน").waitForExistence(timeout: slow))
        for _ in 0..<4 where !toggle.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(toggle.exists)
        XCTAssertTrue(text(app, "ระยะเวลานัด").exists || text(app, "ไม่ได้รับสิทธิ์ปฏิทิน").exists
                      || app.buttons["settings.calendarAccess"].exists,
                      "on: the options, or an action to grant Calendar access")
        if let dir = ProcessInfo.processInfo.environment["CALENDAR_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("calendar-settings.png"))
        }
    }
}

import XCTest

/// docs/ui/iphone-monitor-entry (CHA-34), on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/PhoneMonitorUITests -derivedDataPath <scratch>`.
/// The iPhone dock has `Monitor` between `เอกสาร` and `ตั้งค่า`, with the example fleet's badge; it opens
/// `Monitoring ทุกสถานี` in one column, and a station row opens its maintenance page. A contractor has no `Monitor`.
final class PhoneMonitorUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeDemo", "YES", "-noNotificationPrompt", "YES"] + extra
        app.launchInThai()
        return app
    }

    /// The dock's hittable button of that name (each opened tab keeps its own dock), or with a badge's `| n`.
    func dockButton(_ app: XCUIApplication, _ label: String) -> XCUIElement? {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + " |"))
            .allElementsBoundByIndex.first { $0.isHittable }
    }

    func testMonitorSitsBetweenDocsAndSettings() throws {
        let app = launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "หน้าหลัก")).firstMatch.waitForExistence(timeout: slow))
        let docs = try XCTUnwrap(dockButton(app, "เอกสาร"))
        let monitor = try XCTUnwrap(dockButton(app, "Monitor"), "the iPhone dock should have Monitor")
        let settings = try XCTUnwrap(dockButton(app, "ตั้งค่า"))
        XCTAssertEqual(monitor.frame.midY, docs.frame.midY, accuracy: 1, "Monitor should be on the dock's line")
        XCTAssertLessThanOrEqual(docs.frame.maxX, monitor.frame.minX, "Monitor should come after เอกสาร")
        XCTAssertLessThanOrEqual(monitor.frame.maxX, settings.frame.minX, "Monitor should come before ตั้งค่า")
        XCTAssertGreaterThanOrEqual(monitor.frame.width, 44, "a dock tab should be at least 44 pt wide")
    }

    func testMonitorOpensTheFleetPage() throws {
        let app = launch(["-monitoringDemo", "YES"])
        let badge = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Monitor | ต้องดูแล ")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: slow), "the badge should count the stations needing someone")
        try XCTUnwrap(dockButton(app, "Monitor")).tap()
        XCTAssertTrue(app.staticTexts["Monitoring ทุกสถานี"].waitForExistence(timeout: 15), "Monitor should open the fleet page")
        XCTAssertTrue(app.descendants(matching: .any)["monitoring.actions"].exists, "the page should list ต้องดำเนินการ")
        XCTAssertEqual(app.buttons["monitoring.settings"].exists, false, "no ตั้งค่า Monitoring on iPhone")

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "monitoring.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the stations card should list the fleet")
        row.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Monitoring ทุกสถานี"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "a station row should push its page over the fleet page")
    }

    func testNoMonitorForContractors() {
        let app = launch(["-role", "external"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "หน้าหลัก")).firstMatch.waitForExistence(timeout: slow))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Monitor")).count, 0, "a contractor has no Monitor")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "เอกสาร")).count, 0, "nor เอกสาร")
    }
}

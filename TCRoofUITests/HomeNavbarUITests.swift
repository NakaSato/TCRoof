import XCTest

/// docs/ui/home-navbar-ipad, docs/ui/tcroof-home-ipad-v2 and the dock of docs/ui/pwa-solar-survey-ipad-v3, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/HomeNavbarUITests -derivedDataPath <scratch>`.
/// The bell and the dock's `ตั้งค่า` each open their panel and close the other; the search field opens the job search.
/// The bar has no account button: settings are in the dock.
final class HomeNavbarUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // `-surveyHomeType all`: the PWA home keeps its type between runs, and only the project list has the sorts
        app.launchArguments = ["-screen", "home", "-homeDemo", "YES", "-noNotificationPrompt", "YES", "-surveyHomeType", "all"] + extra
        app.launchInThai()
        return app
    }

    /// The dock's button of that name on screen: each opened tab keeps its own dock, and the install page has a `เอกสาร`
    /// tab of its own, so take the hittable one whose label is exactly the name (or begins with it, for a badge's `| n`).
    func dockButton(_ app: XCUIApplication, _ label: String, prefix: Bool = false) -> XCUIElement? {
        let p = prefix ? NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + " |")
                       : NSPredicate(format: "label == %@", label)
        return app.buttons.matching(p).allElementsBoundByIndex.first { $0.isHittable }
    }

    func bell(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "การแจ้งเตือน")).firstMatch
    }

    /// The panel's close button stands for the open notifications panel (`อ่านทั้งหมด` hides once all are read).
    func notificationsPanel(_ app: XCUIApplication) -> XCUIElement { app.buttons["ปิด"] }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Bell opens the popover; the dock's `ตั้งค่า` closes it and opens settings.
    func testBellThenSettings() {
        let app = launch()
        let bell = bell(app)
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        XCTAssertTrue(notificationsPanel(app).waitForExistence(timeout: 8), "the bell should open the notifications")

        let settings = app.buttons.matching(NSPredicate(format: "label == %@", "ตั้งค่าและบัญชี"))
        XCTAssertEqual(settings.count, 1, "settings should be in the dock only, not in the bar")
        settings.firstMatch.tap()
        XCTAssertTrue(waitGone(notificationsPanel(app)), "the dock's settings button should close the notifications")
        XCTAssertTrue(app.buttons["เสร็จ"].waitForExistence(timeout: 8), "the dock's settings button should open settings")
    }

    /// A dock button opens its tab under the same dock; a screen pushed there covers the dock; `หน้าแรก` returns.
    /// Every opened tab keeps its own dock (the others are not on screen), so the dock's buttons are matched by
    /// name with `firstMatch` and "the dock is gone" means none of them can be tapped. The plan calendar left the
    /// dock (docs/ui/pwa-solar-survey-ipad-v3): it is a row of the `เครื่องมือ` tab.
    func testDockSwitchesTabs() {
        let app = launch()
        let tools = app.buttons.matching(NSPredicate(format: "label == %@", "เครื่องมือวัด"))
        XCTAssertTrue(tools.firstMatch.waitForExistence(timeout: slow))
        XCTAssertTrue(app.staticTexts["ฟีดโครงการ"].exists, "the right column should be the project feed")
        for gone in ["แผนงาน", "ติดตั้ง", "สำรวจ", "กปภ."] {
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", gone)).count, 0, "\(gone) should not be in the dock")
        }
        tools.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ทะเบียนเครื่องมือวัด"].waitForExistence(timeout: 10), "the tools register should open")
        let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == true", "เครื่องมือวัด"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 8), "the dock should stay, with the tools tab selected")
        func dockShown() -> Bool { selected.allElementsBoundByIndex.contains { $0.isHittable } }
        XCTAssertTrue(dockShown())

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "แผนก่อสร้าง")).firstMatch.tap()
        XCTAssertTrue(app.buttons["ดูรายการแผนก่อสร้าง"].waitForExistence(timeout: 10), "the plan calendar should open from its row")
        sleep(1)
        XCTAssertFalse(dockShown(), "the dock should be hidden on a pushed screen")
        app.buttons.matching(NSPredicate(format: "label == %@", "กลับหน้าหลัก")).firstMatch.tap()
        sleep(1)
        XCTAssertTrue(dockShown(), "the dock should return on the tab's root")

        app.buttons.matching(NSPredicate(format: "label == %@", "หน้าแรก")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ฟีดโครงการ"].waitForExistence(timeout: 8), "the home tab should return")
    }

    /// The `โครงการ` tab is the PWA project home: its nav and filter, and its bell opens the home's panel.
    func testProjectsTab() {
        let app = launch()
        let projects = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "โครงการ", "PWA"))
        XCTAssertTrue(projects.firstMatch.waitForExistence(timeout: slow))
        projects.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["โครงการ PWA"].waitForExistence(timeout: 10), "the PWA project home should open")
        XCTAssertTrue(app.buttons["บำรุงรักษา"].firstMatch.exists, "the nav should have บำรุงรักษา")
        XCTAssertTrue(app.buttons["แผนงาน"].firstMatch.exists, "the nav should have แผนงาน")

        let filter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "กรอง")).firstMatch
        filter.tap()
        XCTAssertTrue(app.buttons["แก้ไขล่าสุด"].waitForExistence(timeout: 8), "the filter should list the sorts")
        // the home tab's stack is still in the tree, so take the row that is on screen
        func row(_ title: String) -> XCUIElement? {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", title + " ", "สถานี")).allElementsBoundByIndex.first { $0.isHittable }
        }
        row("ติดตั้ง")?.tap()
        XCTAssertTrue(waitGone(app.buttons["แก้ไขล่าสุด"]), "a type row should close the filter")
        XCTAssertTrue(app.buttons["เพิ่มโครงการติดตั้ง"].waitForExistence(timeout: 8), "ติดตั้ง should show the install overview")
        filter.tap()
        XCTAssertFalse(app.buttons["แก้ไขล่าสุด"].waitForExistence(timeout: 3), "the install overview has only ประเภทงาน")
        XCTAssertNotNil(row("บำรุงรักษา"), "the type rows should still be listed")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "ทั้งหมด ", " งาน")).allElementsBoundByIndex.first { $0.isHittable }?.tap()
        XCTAssertTrue(waitGone(app.buttons["เพิ่มโครงการติดตั้ง"]), "ทั้งหมด should return to the project list")

        let bell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "การแจ้งเตือน")).allElementsBoundByIndex.first { $0.isHittable }
        bell?.tap()
        XCTAssertTrue(notificationsPanel(app).waitForExistence(timeout: 8), "the bell should open the notifications panel")
    }

    /// docs/ui/ipad-dock-monitor (issues #268, #271): `Monitor` stands between `เอกสาร` and `เครื่องมือ`, on the dock's line,
    /// and the 8 tabs with the divider fit the iPad mini's 744 pt portrait width with a 16 pt gutter each side (the dock
    /// is as wide as its tabs at any screen width, so measuring it on this simulator is enough).
    func testMonitorSitsBetweenDocsAndTools() throws {
        let app = launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "หน้าแรก")).firstMatch.waitForExistence(timeout: slow))
        let home = try XCTUnwrap(dockButton(app, "หน้าแรก"))
        let docs = try XCTUnwrap(dockButton(app, "เอกสาร"))
        let monitor = try XCTUnwrap(dockButton(app, "Monitor", prefix: true), "the dock should have Monitor")
        let tools = try XCTUnwrap(dockButton(app, "เครื่องมือวัด"))
        let settings = try XCTUnwrap(dockButton(app, "ตั้งค่าและบัญชี"))
        XCTAssertEqual(monitor.frame.midY, docs.frame.midY, accuracy: 1, "Monitor should be on the dock's line")
        XCTAssertLessThanOrEqual(docs.frame.maxX, monitor.frame.minX, "Monitor should come after เอกสาร")
        XCTAssertLessThanOrEqual(monitor.frame.maxX, tools.frame.minX, "Monitor should come before เครื่องมือ")
        XCTAssertEqual(monitor.frame.width, docs.frame.width, accuracy: 0.5, "Monitor should be as wide as the other tabs")
        // the dock: its first to its last button, with its 6 pt padding each side
        let width = settings.frame.maxX - home.frame.minX + 12
        XCTAssertLessThanOrEqual(width, 744 - 32, "the dock should fit the iPad mini in portrait (\(width) pt)")
    }

    /// `Monitor` opens `Monitoring ทุกสถานี` (issue #259 replaced the pinned บำรุงรักษา overview the hand-off drew), its
    /// badge counts the example fleet's stations in alarm or offline (MP 25, MP 44), and the `โครงการ` tab keeps its nav.
    func testMonitorOpensTheFleetPage() throws {
        let app = launch(["-monitoringDemo", "YES"])
        let monitor = app.buttons["Monitor | ต้องดูแล 2"].firstMatch
        XCTAssertTrue(monitor.waitForExistence(timeout: slow), "the badge should count the stations in alarm or offline")
        try XCTUnwrap(dockButton(app, "Monitor", prefix: true)).tap()
        XCTAssertTrue(app.buttons["monitoring.settings"].waitForExistence(timeout: 15), "Monitor should open the fleet page")
        let selected = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND selected == true", "Monitor"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 8), "the dock should stay, with Monitor selected")

        let projects = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "โครงการ", "PWA"))
            .allElementsBoundByIndex.first { $0.isHittable }
        try XCTUnwrap(projects).tap()
        XCTAssertTrue(app.staticTexts["โครงการ PWA"].waitForExistence(timeout: 10), "the PWA project home should open")
        XCTAssertTrue(app.buttons["บำรุงรักษา"].firstMatch.exists, "the โครงการ nav should keep บำรุงรักษา")
        XCTAssertTrue(app.buttons["แผนงาน"].firstMatch.exists, "the โครงการ nav should keep แผนงาน")
    }

    /// A contractor's dock has no `Monitor` (decision 2 of #267), as it has no `เอกสาร`.
    func testNoMonitorForContractors() {
        let app = launch(["-role", "external"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "หน้าแรก")).firstMatch.waitForExistence(timeout: slow))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "เครื่องมือวัด")).firstMatch.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Monitor")).count, 0, "a contractor has no Monitor")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "เอกสาร")).count, 0, "nor เอกสาร")
    }

    /// Bell toggles: a second tap closes the popover.
    func testBellToggles() {
        let app = launch()
        let bell = bell(app)
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        XCTAssertTrue(notificationsPanel(app).waitForExistence(timeout: 8))
        bell.tap()
        XCTAssertTrue(waitGone(notificationsPanel(app)), "a second tap on the bell should close the notifications")
    }

    /// `อ่านทั้งหมด` clears the count: VoiceOver drops `| ใหม่ n` (states/04 hides the badge).
    /// The read state stays on the simulator, so a second run finds everything read already.
    func testAllReadDropsCount() {
        let app = launch()
        let bell = bell(app)
        XCTAssertTrue(bell.waitForExistence(timeout: slow))
        bell.tap()
        let panel = notificationsPanel(app)
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let readAll = app.buttons["อ่านทั้งหมด"]
        if readAll.exists { readAll.tap() }
        panel.tap()
        XCTAssertTrue(waitGone(panel))
        XCTAssertEqual(self.bell(app).label, "การแจ้งเตือน")
    }

    /// The search field opens the survey list with its search field focused.
    func testSearchOpensJobSearch() {
        let app = launch()
        let search = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ค้นหาเลขที่")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: slow))
        search.tap()
        let field = app.textFields["ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the survey list's search should open")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "its search field should be focused")
    }
}

import XCTest

/// `ตั้งค่าโครงการจากไฟล์…` (the Excel menu of แผนงาน MP, `ProjectSetupSheet`), on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/ProjectSetupUITests -derivedDataPath <scratch>`.
/// The first job starts from station P3-001's plan file (`-mpClear YES -mpTemplate P3-001`, moved to today, which takes no
/// project facts); the sheet lists the file's facts the job doesn't hold, and taking only its PPIM request number takes
/// that row off the list. The first job keeps the plan and the PPIM number.
final class ProjectSetupUITests: XCTestCase {
    let slow: TimeInterval = 90
    static let fields = ["stationName", "kWp", "code", "branch", "area", "peaZone", "inverter", "zeroExport", "ppimRequest",
                         "engineer", "admin", "contractor", "owner", "locations"]

    override func setUp() { continueAfterFailure = false }

    func testTakingOneFactFromThePlanFile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-mpTemplate", "P3-001", "-noNotificationPrompt", "YES"]
        app.launch()

        let menu = app.buttons["ไฟล์ Excel"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: slow), "the template's plan should show")
        menu.tap()
        let item = app.buttons["ตั้งค่าโครงการจากไฟล์…"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the menu offers the plan file's project facts")
        item.tap()

        func row(_ id: String) -> XCUIElement { app.buttons.matching(identifier: "projectSetup." + id).firstMatch }
        let ppim = row("ppimRequest")
        XCTAssertTrue(ppim.waitForExistence(timeout: 10), "a job without a PPIM number is offered the file's")
        XCTAssertTrue(ppim.label.contains("PPIM1A5072BC"), ppim.label)
        // only the PPIM number: untick the rest
        for id in Self.fields where id != "ppimRequest" && row(id).exists && row(id).isSelected { row(id).tap() }
        if !ppim.isSelected { ppim.tap() }
        XCTAssertTrue(ppim.isSelected)
        app.buttons["projectSetup.apply"].tap()
        XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ppim)],
                                       timeout: 10) == .completed, "the sheet should close")

        // taken: the file and the job now agree on it
        menu.tap()
        item.tap()
        XCTAssertTrue(app.navigationBars["ตั้งค่าโครงการจากไฟล์"].waitForExistence(timeout: 10))
        XCTAssertFalse(row("ppimRequest").waitForExistence(timeout: 3), "the PPIM number is the job's now")
        app.buttons["ปิด"].firstMatch.tap()
    }
}

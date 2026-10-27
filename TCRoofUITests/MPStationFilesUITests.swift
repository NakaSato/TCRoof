import XCTest

/// เพิ่มสถานีจากไฟล์แผน in แผน MP ทุกสถานี (`MPStationFilesSheet`), on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MPStationFilesUITests -derivedDataPath <scratch>`.
/// The sheet lists the 102 stations' plan files the app doesn't have; the test picks one and adds it, which reports it.
/// That station stays on the simulator (with its own plan), so the next run adds the next one.
final class MPStationFilesUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func testAddOneStationFromItsPlanFile() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mpall", "-homeBoard", "YES", "-mpStationFiles", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        let summary = app.staticTexts.matching(identifier: "stationFiles.summary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: slow), "the sheet should list the stations the app doesn't have")
        XCTAssertTrue(summary.label.hasPrefix("ยังไม่มีในแอป"), summary.label)

        let installing = app.segmentedControls["stationFiles.status"].buttons["กำลังติดตั้ง"]
        XCTAssertTrue(installing.exists && installing.isSelected, "stations are added as installing by default")

        app.buttons["stationFiles.none"].tap()
        let add = app.buttons["stationFiles.add"]
        XCTAssertFalse(add.isEnabled, "nothing picked")

        app.buttons.matching(identifier: "stationFiles.row").firstMatch.tap()
        XCTAssertTrue(app.buttons["เพิ่ม 1 สถานี"].waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.alerts["เพิ่มแล้ว 1 สถานี"].waitForExistence(timeout: 30), "the station should be added and reported")
    }
}

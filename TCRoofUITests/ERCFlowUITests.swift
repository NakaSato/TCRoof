import XCTest

/// ลำดับ กกพ. in เอกสารสถานี กปภ., on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/ERCFlowUITests -derivedDataPath <scratch>`.
/// `-stationDocsERC failed` rewrites the first installing job's record on every launch, so the test starts the same.
final class ERCFlowUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    /// After a "not passed" design answer the request is ours again; recording it hands the turn to the utility.
    func testRequestingAgainWaitsOnTheUtility() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "stationdocs", "-stationDocsERC", "failed", "-noNotificationPrompt", "YES"]
        app.launch()

        let request = app.buttons["erc.designRequest"]
        XCTAssertTrue(request.waitForExistence(timeout: slow), "the flag should open ลำดับ กกพ.")
        XCTAssertTrue(app.staticTexts["ทีมเรา"].exists, "the request should be ours after a failed round")
        XCTAssertFalse(app.staticTexts["รอการไฟฟ้า"].exists)

        request.tap()
        XCTAssertTrue(app.staticTexts["บันทึกขั้นตอน"].waitForExistence(timeout: 8), "the row should open the step sheet")
        app.buttons["บันทึก"].tap()

        XCTAssertTrue(app.staticTexts["รอการไฟฟ้า"].waitForExistence(timeout: 8), "the utility should have the turn now")
        XCTAssertTrue(app.buttons["ลบรายการล่าสุด"].exists, "the history should list what was recorded")
    }
}

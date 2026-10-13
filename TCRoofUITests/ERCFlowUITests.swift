import XCTest

/// ลำดับ กกพ. in เอกสารสถานี กปภ., on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/ERCFlowUITests -derivedDataPath <scratch>`.
/// `-stationDocsERC <state>` rewrites the first installing job's record on every launch, so each test starts the same.
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

    /// Once installed, the พค.2 request is ours: its row leads to the พค.2 papers, and the job's card says whose turn it is.
    func testOpenRequestLeadsToItsPapersAndShowsOnTheJobCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "stationdocs", "-stationDocsERC", "ready", "-noNotificationPrompt", "YES"]
        app.launch()

        let papers = app.buttons["erc.papers.pk2"]
        XCTAssertTrue(papers.waitForExistence(timeout: slow), "an open พค.2 request should offer its papers")
        papers.tap()
        XCTAssertTrue(app.staticTexts["กำหนดยื่น"].waitForExistence(timeout: 8), "the link should open the พค.2 package")
        XCTAssertFalse(app.buttons["erc.designRequest"].exists)
        app.terminate()

        app.launchArguments = ["-screen", "job", "-jobKind", "pwa", "-noNotificationPrompt", "YES"]
        app.launch()
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ลำดับ กกพ. · ถึงคิวทีมเรา")).firstMatch
        XCTAssertTrue(app.staticTexts["เอกสารสถานี กปภ."].waitForExistence(timeout: slow) || line.waitForExistence(timeout: 8))
        for _ in 0..<8 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.exists, "the job's card should say whose turn it is in the ERC flow")
    }
}

import XCTest

/// The iPad one-page daily report's left card (docs/ui/daily-report-ipad-v2): the station's uploaded key plan wins
/// over the survey's A2 picture and `ใช้ภาพ A2 จากรายงานสำรวจ` goes back to it, and a line's title takes a photo.
/// iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>' -only-testing:TCRoofUITests/DailyLeftCardUITests -derivedDataPath <scratch>`.
final class DailyLeftCardUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "daily", "-role", "internal", "-jobTeam", "none", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    /// `-routineKeyPlanUpload YES` gives the station an uploaded plan (the demo job has no A2 picture), so the plan
    /// shows; going back to A2 clears it and the page lists the locations instead. The uploaded plan is removed again.
    func testUploadedKeyPlanWinsOverA2() throws {
        let app = launch(["-routineKeyPlanUpload", "YES"])
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the one-page layout is iPad only")
        let badge = app.staticTexts["KEY PLAN"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: slow), "the uploaded plan is shown")
        app.buttons["keyPlanUpload"].firstMatch.tap()
        let a2 = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ใช้ภาพ A2")).firstMatch
        XCTAssertTrue(a2.waitForExistence(timeout: 5))
        a2.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: badge)
        wait(for: [gone], timeout: 10)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ยังไม่มีผังของสถานีนี้")).firstMatch.exists)
    }

    /// With `-routineDaily onepage`'s lines and `-routineCameraStub YES`, a line's title adds a photo to it. Not saved.
    func testTitleTakesAPhoto() throws {
        let app = launch(["-routineDaily", "onepage", "-routineCameraStub", "YES"])
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the one-page layout is iPad only")
        let title = app.buttons["dailyLineTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: slow))
        // the first row's camera button names its count
        let camera = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ถ่ายรูปงานนี้ ")).firstMatch
        let before = camera.label
        title.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: camera)
        wait(for: [changed], timeout: 10)
    }
}

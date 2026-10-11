import XCTest

/// docs/specs/review-lock-revisions-swift.md §6 UI tests, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/ReviewLockUITests -derivedDataPath <scratch>`.
/// Each test starts on a new job (`-surveyFreshJob YES`); signatures come from `-surveyReview sign`, as the pad can't be drawn on here.
final class ReviewLockUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-noNotificationPrompt", "YES"] + args
        app.launch()
        return app
    }

    func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func button(_ app: XCUIApplication, beginsWith text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// "รูปบังคับ 3/24" → 3
    func filledCount(_ app: XCUIApplication) -> Int? {
        let label = app.staticTexts["photoReview.progress"].label
        return label.split(separator: " ").last?.split(separator: "/").first.flatMap { Int($0) }
    }

    /// 1. A missing photo → tap → camera (stubbed) → the slot fills and the count goes up.
    func testMissingPhotoFillsFromCamera() {
        let app = launch(["-surveyFreshJob", "YES", "-surveyPage", "photos", "-surveyCameraStub", "YES"])
        let progress = app.staticTexts["photoReview.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: slow))
        let before = filledCount(app)
        XCTAssertEqual(before, 0, "a new job has no photos: \(progress.label)")
        let missing = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", " ยังขาด")).firstMatch
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        let label = missing.label.replacingOccurrences(of: " ยังขาด", with: "")
        missing.tap()
        XCTAssertTrue(app.buttons[label + " มีรูปแล้ว"].waitForExistence(timeout: 8), "the slot should show its photo")
        XCTAssertEqual(filledCount(app), 1)
    }

    /// 2–4. Sign both → lock → locked; open REV 01 → an edit gets its marker; sign again → REV 01 lists the change.
    func testLockNextRevisionAndChangeList() {
        // 2. both signatures → the lock sheet → locked banner, fields disabled
        var app = launch(["-surveyFreshJob", "YES", "-surveyPage", "final", "-surveyReview", "sign"])
        let lock00 = button(app, beginsWith: "ล็อกและออก REV 00")
        XCTAssertTrue(lock00.waitForExistence(timeout: slow), "the second signature should open the lock sheet")
        lock00.tap()
        XCTAssertTrue(element(app, containing: "REV 00 ลงนามแล้ว · ล็อก").waitForExistence(timeout: 15))
        let verdict = app.buttons["ติดตั้งได้"]
        XCTAssertTrue(verdict.exists)
        XCTAssertFalse(verdict.isEnabled, "a locked form can't be edited")

        // 3. open REV 01 → the edit marks its page
        button(app, beginsWith: "แก้ไข (เปิด REV 01)").tap()
        let reason = app.textFields["nextRevision.reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        reason.typeText("สถานีแจ้งขนาดหม้อแปลงใหม่")
        app.buttons["เปิด REV 01"].tap()
        XCTAssertTrue(verdict.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: verdict)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 5), .completed, "REV 01 is editable")
        verdict.tap()
        XCTAssertTrue(element(app, containing: "แก้จาก REV ก่อน 1 รายการ").waitForExistence(timeout: 5), "the sidebar should mark E1 as changed")

        // 4. sign REV 01 → issued; รายการแก้ไข lists the verdict
        app.terminate()
        app = launch(["-surveyTestJob", "YES", "-surveyPage", "final", "-surveyReview", "sign"])
        let lock01 = button(app, beginsWith: "ล็อกและออก REV 01")
        XCTAssertTrue(lock01.waitForExistence(timeout: slow))
        lock01.tap()
        XCTAssertTrue(element(app, containing: "REV 01 ลงนามแล้ว · ล็อก").waitForExistence(timeout: 15))
        button(app, beginsWith: "REV และรายการแก้ไข").tap()
        XCTAssertTrue(element(app, containing: "สถานีแจ้งขนาดหม้อแปลงใหม่").waitForExistence(timeout: 5), "the history shows the reason")
        XCTAssertTrue(element(app, containing: "ผลการประเมินความเหมาะสมในการติดตั้ง").waitForExistence(timeout: 5), "the verdict change is listed")
    }
}

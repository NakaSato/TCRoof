import XCTest

/// ตรวจรูปทั้งหมด and signing (docs/specs/review-lock-revisions-swift.md §6, without the lock), on an iPad simulator:
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

    /// 2. Both signatures leave the form editable: no lock sheet, no lock banner.
    func testSignedFormStaysEditable() {
        let app = launch(["-surveyFreshJob", "YES", "-surveyPage", "final", "-surveyReview", "sign"])
        let verdict = app.buttons["ติดตั้งได้"]
        XCTAssertTrue(verdict.waitForExistence(timeout: slow))
        // the second signature lands 1.2 s in
        sleep(3)
        XCTAssertFalse(button(app, beginsWith: "ล็อกและออก REV").exists, "signing shouldn't offer a lock")
        XCTAssertFalse(element(app, containing: "ลงนามแล้ว · ล็อก").exists)
        XCTAssertTrue(verdict.isEnabled, "a signed form stays editable")
    }
}

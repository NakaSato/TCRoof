import XCTest

/// D1 sub-step 4 on iPad (docs/ui/survey-d1-photo-ipad), on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/TankPhotosUITests -derivedDataPath <scratch>`.
/// From `-surveyD1 photo` (two of three required photos): tap the missing obstacle tile, take it with the camera stub,
/// and the ring counts one more.
final class TankPhotosUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func testAMissingTileIsFilledFromTheCamera() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-surveyWideA1", "YES",
                               "-surveyPage", "tank", "-surveyD1", "photo", "-surveyCameraStub", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "ภาพบังคับ ")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: slow))
        let before = ring.label

        let tile = app.buttons["สิ่งกีดขวาง | บังคับ"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        app.buttons["กล้อง"].firstMatch.tap()

        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: ring)], timeout: 15)
        XCTAssertTrue(app.buttons["สิ่งกีดขวาง 1 | ถ่ายแล้ว"].firstMatch.waitForExistence(timeout: 10))
    }
}

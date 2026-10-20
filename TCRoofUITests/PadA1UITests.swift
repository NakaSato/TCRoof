import XCTest

/// docs/ui/survey-a1-ipad, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/PadA1UITests -derivedDataPath <scratch>`.
/// `-surveyWideA1 YES` gives the landscape layout, where the map fills its card and cuts off the picture's sides.
final class PadA1UITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    /// The report frame (states/02): resizing it by a corner changes `ภาพในรายงาน | w × h ม.`; `รีเซ็ตกรอบ` brings the
    /// standard frame back.
    func testReportFrameResizeAndReset() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyFreshJob", "YES", "-surveyDemoSection", "YES",
                               "-surveyWideA1", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        // the frame shows once the job has coordinates
        let gps = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "17.0062, 99.8235")).firstMatch
        XCTAssertTrue(gps.waitForExistence(timeout: slow))
        gps.tap()
        gps.typeText("17.0062, 99.8235\n")

        let frame = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "ภาพในรายงาน |")).firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 15))
        let standard = frame.label

        // the element is the whole map; the picture fills it centred, and the standard frame's SE corner is at 76 % × 80 %
        let size = frame.frame.size
        let k = max(size.width / 640, size.height / 400)
        let picture = CGRect(x: (size.width - 640 * k) / 2, y: (size.height - 400 * k) / 2, width: 640 * k, height: 400 * k)
        let origin = frame.coordinate(withNormalizedOffset: .zero)
        let corner = origin.withOffset(CGVector(dx: picture.minX + picture.width * 0.76, dy: picture.minY + picture.height * 0.80))
        corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: -120, dy: -80)))

        let resized = NSPredicate(format: "label != %@", standard)
        wait(for: [XCTNSPredicateExpectation(predicate: resized, object: frame)], timeout: 10)
        XCTAssertTrue(frame.label.hasPrefix("ภาพในรายงาน | "), frame.label)

        app.buttons["รีเซ็ตกรอบ"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", standard), object: frame)], timeout: 10)
    }
}

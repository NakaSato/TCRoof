import XCTest

/// ร่างหนังสือแจ้งดับไฟ in เอกสารสถานี กปภ., on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/StationDocsDraftUITests -derivedDataPath <scratch>`.
/// The answers and the kept letter stay on the first installing job, so a second run adds to the number and signer.
final class StationDocsDraftUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Fill the letter, keep it: the paper gets a file and reads ร่างแล้ว in the list.
    func testOutageLetterBecomesThePapersFile() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "stationdocs", "-stationDocsDraft", "outage", "-noNotificationPrompt", "YES"]
        app.launch()

        let number = app.textFields["outage.number"]
        XCTAssertTrue(number.waitForExistence(timeout: slow), "the flag should open ร่างหนังสือแจ้งดับไฟ")
        number.tap()
        number.typeText("001")

        let to = app.descendants(matching: .any)["outage.to"].firstMatch
        to.tap()
        to.typeText("PEA")

        let setDay = app.buttons["กำหนดวันที่ดับไฟ"]
        if setDay.exists { setDay.tap() }
        XCTAssertTrue(waitGone(setDay), "setting the day should show the date picker instead")

        let signer = app.textFields["outage.signer"]
        signer.tap()
        signer.typeText("Somchai")

        let keep = app.buttons["บันทึกเป็นไฟล์ของเอกสาร"]
        keep.tap()
        XCTAssertTrue(waitGone(keep), "keeping the letter should close the draft sheet")

        XCTAssertTrue(app.buttons["เปลี่ยนไฟล์"].waitForExistence(timeout: 8), "the paper should now have a file")
        app.buttons["บันทึก"].tap()
        XCTAssertTrue(app.staticTexts["ร่างแล้ว"].waitForExistence(timeout: 8), "the paper should read ร่างแล้ว in the list")
    }
}

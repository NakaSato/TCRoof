import XCTest

/// docs/ui/survey-a3-ipad-v3, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/PadA3PickersUITests -derivedDataPath <scratch>`.
/// Each test starts from a new job (`-surveyFreshJob YES`) on A3 and adds TX 1.
final class PadA3PickersUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func openA3() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyFreshJob", "YES", "-surveyDemoSection", "YES",
                               "-surveyWideA1", "YES", "-surveyPage", "electrical", "-noNotificationPrompt", "YES"]
        app.launch()
        let add = app.buttons["เพิ่มหม้อแปลง"]
        XCTAssertTrue(add.waitForExistence(timeout: slow))
        add.tap()
        XCTAssertTrue(app.staticTexts["หม้อแปลง TX 1"].waitForExistence(timeout: 10))
        return app
    }

    func gone(_ e: XCUIElement, _ timeout: TimeInterval = 10) {
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)], timeout: timeout)
    }

    /// Picking 400 kVA fills the empty voltage and %Z with the standard values; a vector group typed first stays.
    func testSizePickFillsOnlyEmptyFields() {
        let app = openA3()
        let vector = app.textFields["Vector group"].firstMatch
        XCTAssertTrue(vector.waitForExistence(timeout: 10))
        vector.tap()
        vector.typeText("Dd0\n")

        app.buttons["เลือกขนาดหม้อแปลง TX 1"].firstMatch.tap()
        let size = app.buttons["400 kVA"].firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 10))
        size.tap()
        gone(size)

        XCTAssertEqual(app.textFields["แรงดัน"].firstMatch.value as? String, "22k/230-400")
        XCTAssertEqual(app.textFields["%Z"].firstMatch.value as? String, "4")
        XCTAssertEqual(vector.value as? String, "Dd0")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "In แรงต่ำ ≈ 577 A")).firstMatch.exists)
    }

    /// A new CB ลูกย่อย reads `?kA` until its Icu is picked in the row's popover.
    func testBreakerPopoverSetsIcu() {
        let app = openA3()
        app.buttons["+ เพิ่ม CB ลูกย่อย"].firstMatch.tap()
        let done = app.buttons["เสร็จ"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        gone(done)

        let row = app.buttons["CB ลูกย่อย 1"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue((row.value as? String ?? "").contains("?kA"), row.value as? String ?? "")
        row.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        // the popover's Icu, not the main breaker's
        app.popovers.firstMatch.buttons["เลือกIcu"].tap()
        let icu = app.buttons["25 kA"].firstMatch
        XCTAssertTrue(icu.waitForExistence(timeout: 10))
        icu.tap()
        gone(icu)
        done.tap()
        gone(done)

        let value = NSPredicate(format: "NOT (value CONTAINS %@) AND value CONTAINS %@", "?kA", "25kA")
        wait(for: [XCTNSPredicateExpectation(predicate: value, object: row)], timeout: 10)
    }

    /// A meter at 0.4 kV hides the transformer: the boards hang off the meter with `+ เพิ่ม MDB`.
    func testLowVoltageMeterHidesTransformer() {
        let app = openA3()
        app.buttons["0.4"].firstMatch.tap()
        gone(app.staticTexts["หม้อแปลง TX 1"])
        XCTAssertTrue(app.buttons["เพิ่ม MDB"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A3 มิเตอร์แรงต่ำ | MDB"].exists)
        app.buttons["22"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["หม้อแปลง TX 1"].waitForExistence(timeout: 10))
    }
}

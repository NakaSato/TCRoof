import XCTest

/// เดินทางและเบิกค่าใช้จ่าย (`ClaimScreen`, docs/specs/calendar-travel-expenses-swift.md part B) on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/TravelClaimUITests -derivedDataPath <scratch>`.
/// Grant location first (`xcrun simctl privacy <udid> grant location com.tcroof.internal`) so no prompt covers the screen.
/// ถึง then ออก within two minutes takes the arrival back; a drawn receipt is read into a new expense; a month is
/// signed and submitted (locked), then withdrawn. The expense and the log stay on the simulator.
final class TravelClaimUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "travel", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    func waitGone(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func testArriveThenQuickLeaveUndoes() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["สรุปยอด"].waitForExistence(timeout: slow))
        let arrive = app.buttons["ถึงสถานีแล้ว"]
        guard arrive.waitForExistence(timeout: 5) else { throw XCTSkip("no survey or install day today in the sample jobs") }
        let before = app.buttons.matching(identifier: "ถึงสถานีแล้ว").count
        arrive.firstMatch.tap()
        let leave = app.buttons["ออกจากสถานี"]
        XCTAssertTrue(leave.waitForExistence(timeout: 20), "an arrival turns the button into ออกจากสถานี")
        leave.firstMatch.tap()
        XCTAssertTrue(waitGone(leave), "ออก right after ถึง takes the arrival back")
        XCTAssertEqual(app.buttons.matching(identifier: "ถึงสถานีแล้ว").count, before)
    }

    func testReceiptIsReadIntoANewExpense() {
        let app = launch(["-travelReceiptStub", "YES"])
        let add = app.buttons["claim.add"]
        XCTAssertTrue(add.waitForExistence(timeout: slow))
        add.tap()
        let amount = app.textFields["expense.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        let read = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1038.05"), object: amount)
        XCTAssertEqual(XCTWaiter().wait(for: [read], timeout: 30), .completed, "the drawn PTT receipt's total is read into the amount")
        app.buttons["บันทึก"].tap()
        XCTAssertTrue(waitGone(amount))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "PTT")).firstMatch.waitForExistence(timeout: 10))
    }

    func testSubmitLocksAndWithdrawUnlocks() {
        let app = launch(["-travelDemo", "YES", "-travelSubmit", "YES"])
        let pad = app.otherElements["claim.signature"]
        XCTAssertTrue(pad.waitForExistence(timeout: slow))
        let start = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        let submit = app.buttons["claim.submit"]
        XCTAssertTrue(submit.isEnabled, "a signature enables ยื่นเบิก")
        submit.tap()
        let locked = app.staticTexts["ยื่นเบิกแล้ว · แก้ไม่ได้จนกว่าจะถอนการยื่น"]
        XCTAssertTrue(locked.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["claim.add"].exists, "a submitted month takes no new expense")

        let withdraw = app.buttons["ถอนการยื่น"].firstMatch
        for _ in 0..<6 where !withdraw.isHittable { app.swipeUp() }
        withdraw.tap()
        let alert = app.alerts["ถอนการยื่นเบิก"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("แก้ยอดน้ำมัน")
        alert.buttons["ถอนการยื่น"].tap()
        XCTAssertTrue(waitGone(locked), "withdrawing unlocks the month")
        for _ in 0..<6 where !app.buttons["claim.add"].exists { app.swipeDown() }
        XCTAssertTrue(app.buttons["claim.add"].waitForExistence(timeout: 5))
    }
}

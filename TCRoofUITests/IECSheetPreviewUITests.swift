import XCTest

/// The IEC sheet preview on iPad (docs/ui/iec62446-sheet-before): `ดูชีต Excel` opens INV 01-ก่อน drawn from the
/// export, the source toggle switches, the picker opens INV 02 and INV 01-หลัง, `PDF ชีตนี้` opens the share sheet, and a tap on a Voc cell opens step 2 at that string.
/// iPad simulator: `-only-testing:TCRoofUITests/IECSheetPreviewUITests`. Uses the sample (`-iecDemo reset`).
final class IECSheetPreviewUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func testThePreviewOpensSwitchesAndLeadsToTheStep() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecDemo", "reset"]
        app.launch()
        let open = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ดูชีต Excel")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: slow))
        open.tap()
        XCTAssertTrue(app.staticTexts["ชีต INV 01-ก่อน · ตามฟอร์ม 1FORMI1"].waitForExistence(timeout: 20), "the preview")
        XCTAssertTrue(app.staticTexts["ไม่พิมพ์ลงไฟล์ Excel"].waitForExistence(timeout: 20), "drawn, with the legend")
        let toggle = app.descendants(matching: .any).matching(identifier: "iec.sheet.sources").firstMatch
        toggle.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["ไม่พิมพ์ลงไฟล์ Excel"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "sources off: the form as exported")
        toggle.tap()

        app.buttons["เลือกชีต"].tap()
        app.buttons["INV 02-ก่อน"].tap()
        XCTAssertTrue(app.staticTexts["ชีต INV 02-ก่อน · ตามฟอร์ม 1FORMI1"].waitForExistence(timeout: 10))
        app.buttons["เลือกชีต"].tap()
        app.buttons["INV 01-หลัง"].tap()
        XCTAssertTrue(app.staticTexts["ชีต INV 01-หลัง · ตามฟอร์ม 1FORMI1"].waitForExistence(timeout: 10), "the after sheet")
        app.buttons["เลือกชีต"].tap()
        app.buttons["INV 01-ก่อน"].tap()
        XCTAssertTrue(app.staticTexts["ไม่พิมพ์ลงไฟล์ Excel"].waitForExistence(timeout: 10))

        // `PDF ชีตนี้`: the share sheet with the PDF, then back
        app.buttons.matching(identifier: "iec.sheet.pdf").firstMatch.tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15), "the share sheet")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap() }
        let shareGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: share)
        XCTAssertEqual(XCTWaiter.wait(for: [shareGone], timeout: 10), .completed)

        // the Voc of String 5 (column I, row 16): through the sheet's own geometry
        let sheet = app.otherElements["ชีต Excel"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        if let dir = ProcessInfo.processInfo.environment["IEC_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/before-tap.png"))
            try? "\(sheet.frame)".write(toFile: dir + "/frame.txt", atomically: true, encoding: .utf8)
        }
        sheet.coordinate(withNormalizedOffset: CGVector(dx: Self.vocI16.x, dy: Self.vocI16.y)).tap()
        sleep(3)
        if let dir = ProcessInfo.processInfo.environment["IEC_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/after-tap.png"))
        }
        XCTAssertTrue(app.staticTexts["IEC 62446 · ก่อนออนระบบ · แรงดัน / กระแส"].waitForExistence(timeout: 15), "step 2's page")
        XCTAssertTrue(app.staticTexts["INV1ST5"].waitForExistence(timeout: 5), "at String 5")
    }

    /// On a closed test (sent, then closed by the team) a tap asks `แก้ไข` first: `ยกเลิก` stays on the sheet, `แก้ไข` reopens the test and opens the step.
    func testATapOnAClosedTestAsksToEditFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecDemo", "full"]
        app.launch()
        let submit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ส่งผลให้ทีม")).firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: slow))
        submit.tap()
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "ปิดการทดสอบ")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.staticTexts["ปิดการทดสอบแล้ว · แก้ไขไม่ได้"].waitForExistence(timeout: 10), "closed")

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ดูชีต Excel")).firstMatch.tap()
        let sheet = app.otherElements["ชีต Excel"]
        XCTAssertTrue(app.staticTexts["ไม่พิมพ์ลงไฟล์ Excel"].waitForExistence(timeout: 20))
        let voc = sheet.coordinate(withNormalizedOffset: CGVector(dx: Self.vocI16.x, dy: Self.vocI16.y))
        voc.tap()
        let ask = app.staticTexts["เปิดผลทดสอบให้แก้ไข"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10), "asks first")
        // iPad shows the question as a popover: no ยกเลิก, a tap outside closes it
        let cancel = app.buttons["ยกเลิก"].firstMatch
        if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap() }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ask)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["ชีต INV 01-ก่อน · ตามฟอร์ม 1FORMI1"].exists, "still on the sheet")

        voc.tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label == %@", "แก้ไข")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["IEC 62446 · ก่อนออนระบบ · แรงดัน / กระแส"].waitForExistence(timeout: 15), "step 2's page")
        XCTAssertTrue(app.staticTexts["INV1ST5"].waitForExistence(timeout: 5), "at String 5")
    }

    /// I16 in the sheet, as a fraction of its width and height (from the template: columns A–AB, rows 1–35, hidden
    /// row 10 left out).
    static let vocI16 = (x: 0.3228, y: 0.4010)
}

import XCTest

/// The iPad `เอกสาร` tab (docs/ui/pwa-docs-ipad) on its example data, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/PadPWADocsUITests -derivedDataPath <scratch>`.
/// `-pwaDocsDemo YES` keeps every change in memory, so nothing is left behind.
final class PadPWADocsUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "docs", "-homeBoard", "YES", "-pwaDocsDemo", "YES",
                               "-pwaDocsCameraStub", "YES", "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The tab opens on the stations; a contractor with nothing to do shows the empty state, whose `ดูทุกสถานี`
    /// brings the stations back; a package card drills in and `ทุกชุดเอกสาร` comes back.
    func testContractorFilterAndPackageDrillDown() {
        let app = launch()
        XCTAssertTrue(element(app, "pwaDocs.station.189").waitForExistence(timeout: slow), "the tab should list the stations")

        app.buttons["ผู้รับเหมา D"].tap()
        let showAll = element(app, "pwaDocs.showAll")
        XCTAssertTrue(showAll.waitForExistence(timeout: 8), "contractor D has nothing to do: the empty state")
        XCTAssertFalse(element(app, "pwaDocs.station.189").exists, "another contractor's station should be hidden")
        showAll.tap()
        XCTAssertTrue(element(app, "pwaDocs.station.189").waitForExistence(timeout: 8), "ดูทุกสถานี should list every station")
        XCTAssertTrue(element(app, "pwaDocs.station.61").exists, "D's own station is back too")

        element(app, "pwaDocs.station.189").tap()
        let card = element(app, "pwaDocs.package.building")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let back = element(app, "pwaDocs.allPackages")
        XCTAssertTrue(back.waitForExistence(timeout: 8), "the card should drill into its papers")
        XCTAssertTrue(element(app, "pwaDocs.paper.building_exempt_notice").exists, "the package lists its papers")
        back.tap()
        XCTAssertTrue(element(app, "pwaDocs.package.building").waitForExistence(timeout: 8), "back shows every package again")
    }

    /// A waiting paper opens its sheet from `ต้องทำ`; `ทวง` counts one more reminder.
    func testRemindRaisesTheCount() {
        let app = launch(["-pwaDocsView", "todo"])
        let card = element(app, "pwaDocs.todo.120.owner_signoff")
        XCTAssertTrue(card.waitForExistence(timeout: slow), "the sign-off column lists the paper waiting for PWA")
        card.tap()

        let remind = element(app, "pwaDocs.sheet.remind")
        XCTAssertTrue(remind.waitForExistence(timeout: 8), "a paper waiting for its signature offers ทวง")
        let before = remind.label
        remind.tap()
        // the share sheet with the message; the app sends nothing itself
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) { close.tap() } else { app.swipeDown() }
        let after = NSPredicate(format: "label != %@", before)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: after, object: remind)], timeout: 8), .completed,
                       "the button should count the reminder: \(before)")
        XCTAssertTrue(remind.label.hasPrefix("ทวง (ครั้งที่"), remind.label)
    }

    /// An ID card's upload stays off until the file is chosen and the three masking checks are ticked.
    func testIDCardUploadNeedsTheThreeChecks() {
        let app = launch(["-pwaDocsStation", "120", "-pwaDocsUpload", "YES", "-pwaDocsPaper", "grantor_docs"])
        let go = element(app, "pwaDocs.upload.go")
        XCTAssertTrue(go.waitForExistence(timeout: slow), "the flag opens the upload sheet")
        XCTAssertFalse(go.isEnabled)
        element(app, "pwaDocs.source.camera").tap()
        XCTAssertTrue(element(app, "pwaDocs.mask.ปิดศาสนา").waitForExistence(timeout: 8), "an ID card asks for the masking checks")
        XCTAssertFalse(go.isEnabled, "a file alone isn't enough for an ID card")
        element(app, "pwaDocs.mask.ปิดศาสนา").tap()
        element(app, "pwaDocs.mask.ปิดกรุ๊ปเลือด").tap()
        XCTAssertFalse(go.isEnabled, "two of three checks keep it off")
        element(app, "pwaDocs.mask.ปิดวันเกิด").tap()
        XCTAssertTrue(go.isEnabled, "all three checks turn it on")
        go.tap()
        XCTAssertTrue(waitGone(go), "uploading closes the sheet")
    }

    /// The header's search finds a paper by name and opens its sheet.
    func testSearchOpensAPaper() {
        let app = launch()
        XCTAssertTrue(element(app, "pwaDocs.station.189").waitForExistence(timeout: slow))
        app.buttons["ค้นหาสถานี ชื่อเอกสาร เลขที่หนังสือ"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.typeText("มอบอำนาจ")
        let hit = element(app, "pwaDocs.hit.poa_letter")
        XCTAssertTrue(hit.waitForExistence(timeout: 8), "the search lists the station papers by name")
        hit.tap()
        XCTAssertTrue(element(app, "pwaDocs.sheet.close").waitForExistence(timeout: 8), "a paper result opens its sheet")
    }
}

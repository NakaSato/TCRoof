import XCTest

/// The daily report's module checklist (docs/specs/module-install-rules.md §7.3, iPad): with a bolt at 22 N·m the
/// engineer can't sign, and the card and sheet say why (`-dailyModuleDemo YES`, nothing saved).
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/DailyModuleUITests -derivedDataPath <path>`.
final class DailyModuleUITests: XCTestCase {
    func testABlockStopsSignOff() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "daily", "-noNotificationPrompt", "YES", "-role", "manager", "-dailyModuleDemo", "YES"]
        app.launch()
        let card = app.buttons["dailyModuleCheck"]
        XCTAssertTrue(card.waitForExistence(timeout: 90))
        XCTAssertTrue(card.label.contains("ห้าม"), card.label)
        let sign = app.buttons["dailySign"].firstMatch
        XCTAssertTrue(sign.waitForExistence(timeout: 10))
        sign.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "S551-torque")).firstMatch.waitForExistence(timeout: 5),
                      "the toast names the rule")
        XCTAssertFalse(app.navigationBars["ตรวจ & ลงนาม"].waitForExistence(timeout: 2), "no sign sheet")
        card.tap()
        XCTAssertTrue(app.staticTexts["S551-torque"].waitForExistence(timeout: 10), "the sheet lists the block")
    }

    /// The checklist's evidence: a torque photo from the camera (`-dailyModuleCameraStub YES`) and three serials from the
    /// barcode scanner (`-dailyModuleScanStub YES`) added to the installed list. Nothing is saved.
    func testEvidencePhotoAndScannedSerials() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "daily", "-noNotificationPrompt", "YES", "-role", "manager", "-dailyModuleDemo", "open",
                               "-dailyModuleCameraStub", "YES", "-dailyModuleScanStub", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["ตรวจติดตั้งแผงตามคู่มือ"].waitForExistence(timeout: 90), "the sheet opens")
        // the checklist is a Form: its rows exist once scrolled to
        let camera = app.buttons["moduleEvidence.torque.camera"]
        for _ in 0..<8 where !(camera.exists && camera.isHittable) { app.swipeUp() }
        XCTAssertTrue(camera.exists, "the torque photo slot")
        camera.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "ลบรูป")).firstMatch.waitForExistence(timeout: 5),
                      "the slot shows its photo")

        let scan = app.buttons["moduleSerials.scanInstalled"]
        for _ in 0..<8 where !(scan.exists && scan.isHittable) { app.swipeUp() }
        scan.tap()
        let add = app.buttons["moduleScan.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the scanner sheet opens")
        XCTAssertTrue(app.staticTexts["ZX7523351920A003"].waitForExistence(timeout: 5), "it lists what it found")
        add.tap()
        let serials = app.textViews["moduleSerials.installed"].exists ? app.textViews["moduleSerials.installed"] : app.textFields["moduleSerials.installed"]
        XCTAssertTrue(serials.waitForExistence(timeout: 5))
        let text = serials.value as? String ?? ""
        XCTAssertTrue(text.contains("ZX7523351920A001") && text.contains("ZX7523351920001"), "the scanned serials join the typed ones: \(text)")
        let footer = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "ติดตั้ง 5 แผง")).firstMatch
        for _ in 0..<4 where !footer.exists { app.swipeUp() }
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "five installed: two typed, three scanned")
    }
}

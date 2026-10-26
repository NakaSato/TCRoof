import XCTest

/// ลายเซ็นของฉัน (`MySignature`, iPhone): drawn and saved in Settings, offered on the daily report's sign sheet
/// (`ใช้ลายเซ็นของฉัน`) to the same account, and not to another one. It ends by deleting the signature.
/// `TEST_RUNNER_SIGNATURE_SHOTS=<folder>` saves each step there as a PNG.
final class MySignatureUITests: XCTestCase {
    let slow: TimeInterval = 90
    let owner = "sig.owner@tcroof.test"
    let other = "sig.other@tcroof.test"

    override func setUp() { continueAfterFailure = false }

    func launch(_ args: [String], email: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-roleEmail", email, "-noNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    func shot(_ app: XCUIApplication, _ name: String) {
        let png = app.screenshot().pngRepresentation
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = name; a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SIGNATURE_SHOTS"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Scrolls the frontmost scroll view up until `e` is on screen.
    func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        for _ in 0..<6 where !(e.exists && e.isHittable) { app.swipeUp() }
    }

    func openMySignature(_ email: String) -> XCUIApplication {
        let app = launch(["-screen", "home", "-homeSettings", "YES"], email: email)
        let row = app.buttons["settings.mySignature"]
        XCTAssertTrue(row.waitForExistence(timeout: slow))
        row.tap()
        XCTAssertTrue(app.navigationBars["ลายเซ็นของฉัน"].waitForExistence(timeout: 10))
        return app
    }

    func draw(on pad: XCUIElement) {
        let start = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        let mid = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        mid.press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6)))
    }

    func testSaveUseAndOtherAccount() {
        // 1. Settings: draw and save
        var app = openMySignature(owner)
        let delete = app.buttons["ลบลายเซ็น"]
        if delete.waitForExistence(timeout: 3) { delete.tap() } // left by an earlier run
        let pad = element(app, "mySignature.pad")
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mySignature.save"].isEnabled, "nothing drawn yet")
        draw(on: pad)
        XCTAssertTrue(app.buttons["mySignature.save"].isEnabled)
        app.buttons["mySignature.save"].tap()
        XCTAssertTrue(app.buttons["เซ็นใหม่"].waitForExistence(timeout: 5), "saved: the page shows it with เซ็นใหม่")
        shot(app, "01-settings-saved")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'บันทึกแล้ว'")).firstMatch.waitForExistence(timeout: 5))
        shot(app, "02-settings-row")
        app.terminate()

        // 2. the daily report's sign sheet, same account: one tap puts it in
        app = launch(["-screen", "daily", "-routineDemo", "sign", "-jobTeam", "none"], email: owner)
        XCTAssertTrue(app.staticTexts["ตรวจก่อนลงนาม"].waitForExistence(timeout: slow))
        let use = app.buttons["signature.useMine"]
        reveal(app, use)
        XCTAssertTrue(use.exists)
        shot(app, "03-daily-offer")
        use.tap()
        XCTAssertTrue(element(app, "ลายเซ็นของฉัน").exists || app.otherElements["ลายเซ็นของฉัน"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["signature.useMine"].exists, "already used")
        shot(app, "04-daily-used")
        app.terminate()

        // 3. another account on the same device: nothing offered
        app = launch(["-screen", "daily", "-routineDemo", "sign", "-jobTeam", "none"], email: other)
        XCTAssertTrue(app.staticTexts["ตรวจก่อนลงนาม"].waitForExistence(timeout: slow))
        reveal(app, app.buttons["ล้างลายเซ็น"])
        XCTAssertTrue(app.buttons["ล้างลายเซ็น"].exists)
        XCTAssertFalse(app.buttons["signature.useMine"].exists, "another account's signature is not offered")
        shot(app, "05-daily-other-account")
        app.terminate()

        // 4. delete it again
        app = openMySignature(owner)
        XCTAssertTrue(app.buttons["ลบลายเซ็น"].waitForExistence(timeout: 5))
        app.buttons["ลบลายเซ็น"].tap()
        XCTAssertTrue(app.buttons["mySignature.save"].waitForExistence(timeout: 5), "deleted: the pad is back")
        shot(app, "06-settings-deleted")
    }
}

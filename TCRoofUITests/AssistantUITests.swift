import XCTest

/// ผู้ช่วยโครงการ with the demo stand-in for Qwen (`-screen assistant -assistantDemo YES`, any simulator):
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>' -only-testing:TCRoofUITests/AssistantUITests -derivedDataPath <scratch>`.
/// A prompt chip answers from the seeded plans, a typed question about one station answers, and the update chip
/// proposes a booking whose `ยืนยัน` saves it (the first demo jobs keep it). With `TEST_RUNNER_ASSISTANT_SHOTS=<folder>`
/// each step is saved there as a PNG.
final class AssistantUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ASSISTANT_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func testAskProposeAndConfirm() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "assistant", "-assistantDemo", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        let behind = app.buttons["สถานีไหนช้ากว่าแผน"]
        XCTAssertTrue(behind.waitForExistence(timeout: slow), "the prompt chips should show")
        shot("01-start")

        behind.tap()
        let answer = app.staticTexts.matching(identifier: "assistantAnswer").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 15), "the stand-in should answer")
        XCTAssertTrue(answer.label.contains("สถานีที่ช้ากว่าแผน"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "วันนี้ใช้ได้อีก")).firstMatch.exists, "the day's requests left")
        shot("02-behind")

        let input = app.textViews["assistantInput"].exists ? app.textViews["assistantInput"] : app.textFields["assistantInput"]
        input.tap()
        input.typeText("MP 190 ต้องเร่งงานอะไร")
        app.buttons["ส่ง"].tap()
        let second = app.staticTexts.matching(identifier: "assistantAnswer").element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 15))
        XCTAssertTrue(second.label.contains("งานที่ต้องเร่ง") || second.label.contains("แผน"), "a station's schedule")
        shot("03-station")

        app.buttons["เริ่มใหม่"].tap()
        let update = app.buttons["อัปเดตความก้าวหน้าจากรายงานประจำวัน"]
        XCTAssertTrue(update.waitForExistence(timeout: 5), "a new chat shows the chips again")
        update.tap()
        let confirm = app.buttons["assistantConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "the stand-in should propose a booking")
        XCTAssertTrue(app.staticTexts["ยังไม่ได้บันทึก"].exists)
        let thinking = app.descendants(matching: .any)["assistantThinking"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: thinking)
        waitForExpectations(timeout: 15)
        shot("04-proposal")

        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["assistantSaved"].firstMatch.waitForExistence(timeout: 5), "ยืนยัน should save and say so")
        XCTAssertFalse(confirm.exists)
        shot("05-saved")
    }

    /// The strategy chips: priorities, a recovery what-if, the look-ahead, and a re-plan card, dismissed so the demo
    /// station keeps its plan.
    func testStrategyChips() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "assistant", "-assistantDemo", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        func ask(_ chip: String, expect: String, shot name: String) {
            let b = app.buttons[chip]
            XCTAssertTrue(b.waitForExistence(timeout: slow), "\(chip) should show")
            b.tap()
            let answer = app.staticTexts.matching(NSPredicate(format: "identifier == 'assistantAnswer' AND label CONTAINS %@", expect)).firstMatch
            XCTAssertTrue(answer.waitForExistence(timeout: 15), "\(chip) should answer with \(expect)")
            shot(name)
            app.buttons["เริ่มใหม่"].tap()
        }
        ask("จัดลำดับความสำคัญทุกสถานี", expect: "ลำดับความเสี่ยง", shot: "06-priorities")
        ask("วางแผนเร่งงานให้ทันกำหนด", expect: "อัตราเดิม", shot: "07-whatif")
        ask("แผนล่วงหน้า 3 สัปดาห์", expect: "แผนล่วงหน้า", shot: "08-lookahead")

        let replan = app.buttons["เสนอแผนใหม่ที่ทำได้จริง"]
        XCTAssertTrue(replan.waitForExistence(timeout: 5))
        replan.tap()
        let confirm = app.buttons["assistantConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "the re-plan should come as a card")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'ยืนยันแล้ววันตามแผนเดิม'")).firstMatch.exists)
        let thinking = app.descendants(matching: .any)["assistantThinking"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: thinking)
        waitForExpectations(timeout: 15)
        shot("09-replan")
        app.buttons["ยกเลิก"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["assistantDismissed"].firstMatch.waitForExistence(timeout: 5))
    }

    /// ตั้งค่า › ผู้ช่วยโครงการ (AI) as a manager: a key saved into this device's Keychain, tested against Qwen (a fake
    /// key is refused), then removed. Without a key the chat says where to put one.
    func testKeyOnTheDevice() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeSettings", "YES", "-role", "manager", "-noNotificationPrompt", "YES"]
        app.launch()

        let row = app.buttons["assistantSettingsRow"]
        XCTAssertTrue(row.waitForExistence(timeout: slow), "settings should list the assistant")
        var swipes = 0
        while !row.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        row.tap()
        let status = app.staticTexts["assistantKeyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        if app.buttons["assistantKeyRemove"].exists {                  // left from an earlier run
            app.buttons["assistantKeyRemove"].tap(); app.buttons["ลบคีย์"].tap()
        }
        expectation(for: NSPredicate(format: "label BEGINSWITH 'ยังไม่ได้ใส่คีย์'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        shot("10-key-empty")

        let field = app.secureTextFields["assistantKeyField"]
        field.tap(); field.typeText("sk-uitest-not-a-real-key")
        app.buttons["ทดสอบ"].tap()
        let result = app.descendants(matching: .any)["assistantKeyResult"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 60), "the test should answer")
        shot("11-key-tested")

        app.buttons["assistantKeySave"].tap()
        let saved = NSPredicate(format: "label BEGINSWITH 'ใช้คีย์ในเครื่องนี้'")
        expectation(for: saved, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        shot("12-key-saved")

        app.buttons["assistantKeyRemove"].tap()
        app.buttons["ลบคีย์"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'ยังไม่ได้ใส่คีย์'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
    }

    /// From a station's install tracking page (iPad): the header's ผู้ช่วย opens the chat on that station, and the
    /// what-if and priorities chips answer.
    func testFromTheInstallPage() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the install tracking page is the iPad's") }
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES",
                               "-assistantDemo", "YES", "-noNotificationPrompt", "YES"]
        app.launch()

        let open = app.buttons["ผู้ช่วย"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: slow), "the header should offer ผู้ช่วย")
        shot("13-install-page")
        open.tap()
        let intro = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'ผู้ช่วยดูแผนของ'")).firstMatch
        XCTAssertTrue(intro.waitForExistence(timeout: 10))
        XCTAssertFalse(intro.label.hasPrefix("ผู้ช่วยดูแผนของทุกสถานี"), "it should name the station it was opened from")

        func ask(_ chip: String, expect: String, shot name: String) {
            let b = app.buttons[chip]
            XCTAssertTrue(b.waitForExistence(timeout: 10), "\(chip) should show")
            b.tap()
            let answer = app.staticTexts.matching(NSPredicate(format: "identifier == 'assistantAnswer' AND label CONTAINS %@", expect)).firstMatch
            XCTAssertTrue(answer.waitForExistence(timeout: 15), "\(chip) should answer")
            shot(name)
        }
        ask("วางแผนเร่งงานให้ทันกำหนด", expect: "อัตราเดิม", shot: "14-install-whatif")
        app.buttons["เริ่มใหม่"].tap()
        ask("จัดลำดับความสำคัญทุกสถานี", expect: "ลำดับความเสี่ยง", shot: "15-install-priorities")
    }
}

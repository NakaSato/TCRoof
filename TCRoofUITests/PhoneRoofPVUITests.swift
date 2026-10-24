import XCTest

/// C1's `จัดแผง` tab on the iPhone: the switch above the plan, `แก้แผง` taking a module out and `จัดแผงใหม่` bringing it
/// back, the roof access segment, landscape pairs and the ridge walkway's width (docs/ui/survey-c1-iphone-pv-fix01), and
/// the closed `ตั้งค่าและรายละเอียดเพิ่มเติม` row. Run on an iPhone simulator.
final class PhoneRoofPVUITests: XCTestCase {
    func launch(_ extra: [String] = ["-surveyFreshJob", "YES"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES",
                               "-noNotificationPrompt", "YES", "-surveyPage", "roof"] + extra
        app.launch()
        let b = app.buttons["จัดแผง"].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 90)); b.tap()
        return app
    }

    func scrollDown(_ app: XCUIApplication, until e: XCUIElement) {
        for _ in 0..<10 where !(e.exists && e.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
        }
    }

    func testEditModulesAndReset() {
        let app = launch()
        let edit = app.buttons["editModules"].firstMatch, reset = app.buttons["resetModules"].firstMatch
        scrollDown(app, until: edit)
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        XCTAssertFalse(reset.isEnabled)
        edit.tap()
        XCTAssertTrue(app.staticTexts["editHint"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["editHint"].firstMatch.label.contains("เอาออกแล้ว 0 แผ่น"))
        edit.tap()
    }

    func testAccessAndMoreSection() {
        let app = launch()
        let left = app.buttons["ด้านซ้าย"].firstMatch
        scrollDown(app, until: left)
        XCTAssertTrue(left.waitForExistence(timeout: 20))
        app.buttons["ด้านขวา"].firstMatch.tap(); left.tap()
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: left)
        XCTAssertEqual(XCTWaiter.wait(for: [picked], timeout: 5), .completed)
        let more = app.buttons["pvMore"].firstMatch
        scrollDown(app, until: more)
        XCTAssertEqual(more.value as? String, "ปิดอยู่")
        more.tap()
        XCTAssertEqual(more.value as? String, "เปิดอยู่")
    }

    /// On the demo roof laid out by `-surveyC1 pvmost` (it writes into the demo job): a tap on a module takes it out,
    /// the tag counts one less, and `จัดแผงใหม่` puts it back.
    func testRemoveModuleAndReset() {
        let app = launch(["-surveyC1", "pvmost"])
        let tag = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' แผง · '")).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 30))
        sleep(6)
        let before = Int(tag.label.split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(before, 0)
        let plan = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'แปลนโครงหลังคา'")).firstMatch
        let edit = app.buttons["editModules"].firstMatch, reset = app.buttons["resetModules"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        // a module in the upper face, left of the skylight
        (plan.exists ? plan : app).coordinate(withNormalizedOffset: plan.exists ? CGVector(dx: 0.29, dy: 0.31) : CGVector(dx: 0.33, dy: 0.46)).tap()
        let hint = app.staticTexts["editHint"].firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'เอาออกแล้ว 1 แผ่น'").evaluate(with: hint) ||
                      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'เอาออกแล้ว 1 แผ่น'"), object: hint)], timeout: 5) == .completed)
        let less = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "\(before - 1) แผง"), object: tag)
        XCTAssertEqual(XCTWaiter.wait(for: [less], timeout: 15), .completed, tag.label)
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "\(before) แผง"), object: tag)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 15), .completed, tag.label)
        XCTAssertFalse(hint.exists)
    }

    /// `แนวนอน` → `วางคู่ 2 แผ่น` shows the pair gap at the standard's 0.40 m, and `+` makes it 0.50 m.
    func testLandscapePairsGap() {
        let app = launch()
        let landscape = app.buttons["แนวนอน"].firstMatch
        scrollDown(app, until: landscape)
        XCTAssertTrue(landscape.waitForExistence(timeout: 20))
        landscape.tap()
        let pairs = app.buttons["วางคู่ 2 แผ่น"].firstMatch
        scrollDown(app, until: pairs)
        XCTAssertTrue(pairs.waitForExistence(timeout: 10))
        pairs.tap()
        let value = app.staticTexts["pairGapValue"].firstMatch, plus = app.buttons["pairGapPlus"].firstMatch
        scrollDown(app, until: plus)
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        XCTAssertEqual(value.label, "0.40 ม.")
        plus.tap()
        let half = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '0.50 ม.'"), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [half], timeout: 5), .completed, value.label)
    }

    /// The ridge walkway's width starts at the team's 0.90 m detail, and `−` is off there.
    func testRidgeWalkwayWidthStopsAtTheDetail() {
        let app = launch()
        let minus = app.buttons["ridgeWidthMinus"].firstMatch
        scrollDown(app, until: minus)
        XCTAssertTrue(minus.waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["ridgeWidthValue"].firstMatch.label, "0.90 ม.")
        XCTAssertFalse(minus.isEnabled)
        XCTAssertTrue(app.buttons["ridgeWidthPlus"].firstMatch.isEnabled)
    }
}

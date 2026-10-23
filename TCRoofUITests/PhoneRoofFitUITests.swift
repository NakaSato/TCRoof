import XCTest

/// C1 on the iPhone stays inside the screen: nothing on either tab (the structure and the panel layout, scrolled down
/// the whole page) starts left of it or ends right of it. A row of buttons wider than the card pushed the whole page out
/// once. The other survey pages (`testOtherPagesFit`) get the same scroll-and-measure. Run on an iPhone simulator.
final class PhoneRoofFitUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func wide(_ app: XCUIApplication) -> [String] {
        let width = app.frame.width
        return app.descendants(matching: .any).allElementsBoundByIndex.compactMap { e in
            let f = e.frame
            guard !f.isEmpty, f.height < 3000, f.maxX > width + 1 || f.minX < -1 else { return nil }
            return "\(e.elementType.rawValue) '\(e.label.prefix(40))' \(f)"
        }
    }

    func check(tab: String?) {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-noNotificationPrompt", "YES", "-surveyPage", "roof"]
        app.launch()
        if let tab {
            let b = app.buttons[tab].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 90)); b.tap()
        } else {
            XCTAssertTrue(app.staticTexts["C1 หลังคา"].firstMatch.waitForExistence(timeout: 90))
        }
        sleep(3)
        for pass in 0..<8 {
            XCTAssertEqual(wide(app), [], "pass \(pass), tab \(tab ?? "โครงสร้าง")")
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            from.press(forDuration: 0.05, thenDragTo: to)
            sleep(1)
        }
    }

    func testStructureTabFits() { check(tab: nil) }
    func testPanelTabFits() { check(tab: "จัดแผง") }

    /// Every other survey page, opened with `-surveyPage`, scrolled the same way.
    func testOtherPagesFit() {
        for page in ["site", "electrical", "sld", "inverter", "panels", "flood", "water", "backfeed", "fts", "tank", "final"] {
            let app = XCUIApplication()
            app.launchArguments = ["-screen", "pwa", "-surveyDemo", "YES", "-surveyDemoSection", "YES", "-noNotificationPrompt", "YES", "-surveyPage", page]
            app.launch()
            sleep(page == "site" ? 12 : 6)
            for pass in 0..<6 {
                XCTAssertEqual(wide(app), [], "page \(page), pass \(pass)")
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
                from.press(forDuration: 0.05, thenDragTo: to)
                sleep(1)
            }
            app.terminate()
        }
    }
}

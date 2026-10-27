import XCTest

/// C1's shade card on iPad (`-surveyC1 pvshade`, docs/ui/survey-c1-ipad-shade): the card under the plan shows
/// `Sun Access`, and a tap on `ด้านเหนือ` turns `Tilt | Azimuth` to the north face.
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/RoofShadeUITests -derivedDataPath <path>`.
final class RoofShadeUITests: XCTestCase {
    func testTheCardSwitchesFaces() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "pwa", "-noNotificationPrompt", "YES", "-surveyDemo", "YES", "-surveyFreshJob", "YES", "-surveyDemoSection", "YES",
                               "-surveyWideA1", "YES", "-surveyPage", "roof", "-surveyC1", "pvshade"]
        app.launch()
        if UIDevice.current.userInterfaceIdiom != .pad { throw XCTSkip("the shade card is the iPad's") }
        let sunAccess = app.descendants(matching: .any).matching(identifier: "shade-Sun Access").firstMatch
        XCTAssertTrue(sunAccess.waitForExistence(timeout: 90), "the card's Sun Access tile")
        // the hourly run fills it in
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "%"), object: sunAccess)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 60), .completed, "Sun Access computed")
        let tilt = app.descendants(matching: .any).matching(identifier: "shade-Tilt | Azimuth").firstMatch
        XCTAssertTrue((tilt.value as? String ?? "").contains("S 180°"), tilt.value as? String ?? "")
        let north = app.buttons["ด้านเหนือ"].firstMatch
        XCTAssertTrue(north.waitForExistence(timeout: 10))
        north.tap()
        let turned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "N 0°"), object: tilt)
        XCTAssertEqual(XCTWaiter().wait(for: [turned], timeout: 10), .completed, "Tilt | Azimuth on the north face")
        // TEST_RUNNER_SHADE_SHOTS=<folder>: the north face and the whole roof as PNGs
        guard let dir = ProcessInfo.processInfo.environment["SHADE_SHOTS"] else { return }
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("02-shade-north.png"))
        app.buttons["รวมทั้งหลังคา"].firstMatch.tap()
        let both = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", ","), object: tilt)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: 10), .completed, "both faces on the whole roof")
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("03-shade-whole-roof.png"))
    }
}

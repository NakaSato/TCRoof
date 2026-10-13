import XCTest

/// The live notification cases as banners over the app, on an iPhone simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<iphone udid>' -only-testing:TCRoofUITests/LiveNotificationBannerUITests -derivedDataPath <scratch>`.
/// `-notifDemo live` posts one example of each case 8 s apart; the test allows notifications when iOS asks, then waits
/// for each banner by its title and keeps a screenshot of it in the runner's temporary folder (the path is printed).
final class LiveNotificationBannerUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() { continueAfterFailure = true }

    func testEachLiveCaseShowsItsBanner() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeFeed", "demo", "-notifDemo", "live"]
        app.launch()
        let titles = ["เริ่มติดตั้งพรุ่งนี้", "ติดตั้ง Day 1/5", "เริ่มงานพรุ่งนี้ตามแผน MP", "ส่งรายงานประจำวันแล้ว", "งานเสร็จ รอผู้ตรวจ",
                      "ปัญหาใหม่", "สรุปวันนี้"]
        func banner(_ title: String) -> XCUIElement {
            springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        }
        // the examples are posted once the permission question is answered; iOS asks only on a fresh install
        let asked = Date()
        while Date().timeIntervalSince(asked) < 90, !banner(titles[0]).exists {
            if let allow = ["Allow", "อนุญาต"].map({ springboard.buttons[$0].firstMatch }).first(where: \.exists) { allow.tap(); break }
            usleep(300_000)
        }
        for (i, title) in titles.enumerated() {
            XCTAssertTrue(banner(title).waitForExistence(timeout: 30), "no banner for \(title)")
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("live-banner-\(i).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
            print("BANNER \(title) -> \(file.path)")
        }
    }

    /// A tap on each banner opens that case's screen over the home: the job, the daily report, the punch list, the install records.
    func testATapOnEachBannerOpensItsScreen() {
        let cases: [(only: Int, title: String, screen: String)] = [
            (0, "เริ่มติดตั้งพรุ่งนี้", "ข้อมูลลูกค้า"), (1, "ติดตั้ง Day 1/5", "ข้อมูลลูกค้า"), (2, "เริ่มงานพรุ่งนี้ตามแผน MP", "ข้อมูลลูกค้า"),
            (3, "ส่งรายงานประจำวันแล้ว", "รายงานประจำวัน"), (4, "งานเสร็จ รอผู้ตรวจ", "ข้อมูลลูกค้า"), (5, "ปัญหาใหม่", "งานบ้านอยู่อาศัยเท่านั้น"),
            (6, "สรุปวันนี้", "บันทึกงานติดตั้ง"),
        ]
        for c in cases {
            let app = XCUIApplication()
            app.launchArguments = ["-screen", "home", "-homeFeed", "demo", "-notifDemo", "live", "-notifOnly", "\(c.only)"]
            app.launch()
            let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", c.title)).firstMatch
            let asked = Date()
            while Date().timeIntervalSince(asked) < 90, !banner.exists {
                if let allow = ["Allow", "อนุญาต"].map({ springboard.buttons[$0].firstMatch }).first(where: \.exists) { allow.tap() }
                usleep(300_000)
            }
            guard banner.waitForExistence(timeout: 30) else { XCTFail("no banner for \(c.title)"); continue }
            banner.tap()
            let screen = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", c.screen, c.screen)).firstMatch
            XCTAssertTrue(screen.waitForExistence(timeout: 15), "\(c.title) should open \(c.screen)")
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("live-tap-\(c.only).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
            print("TAP \(c.title) -> \(file.path)")
            app.terminate()
        }
    }
}

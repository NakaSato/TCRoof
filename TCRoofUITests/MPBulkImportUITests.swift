import XCTest

/// นำเข้าไฟล์แผนหลายสถานี in แผน MP ทุกสถานี, on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MPBulkImportUITests -derivedDataPath <scratch>`.
/// `-mpImportFiles` hands the check the package's fixture twice (the picker can't be driven); its station isn't among the
/// demo stations, so the test picks one. MP 189 (the first demo station of `-screen mpall`) keeps the imported plan.
final class MPBulkImportUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    var fixture: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TCRoofKit/Tests/ExcelExportTests/Fixtures/mp-weekly-bangsai.xlsx").standardized.path
    }

    /// Nothing matches, a picked station enables the import, the same station for both files blocks it, and the import
    /// of one reports it.
    func testPickCheckAndImport() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mpall", "-homeBoard", "YES", "-mpImportFiles", "\(fixture)|\(fixture)", "-noNotificationPrompt", "YES"]
        app.launch()

        let title = app.staticTexts["นำเข้าไฟล์แผน 2 ไฟล์"]
        XCTAssertTrue(title.waitForExistence(timeout: slow), "the files should open their check")
        XCTAssertEqual(app.staticTexts.matching(identifier: "ไม่พบสถานี").count, 2)
        let none = app.buttons["นำเข้า 0 สถานี"]
        XCTAssertFalse(none.isEnabled)

        func pick(_ row: Int, _ prefix: String) {
            app.descendants(matching: .any).matching(identifier: "mpBulk.station").element(boundBy: row).tap()
            let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5), "the menu should list \(prefix)")
            option.tap()
        }

        pick(0, "MP 189")
        let one = app.buttons["นำเข้า 1 สถานี"]
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        XCTAssertTrue(one.isEnabled)

        pick(1, "MP 189")
        XCTAssertTrue(app.staticTexts["ซ้ำกับไฟล์อื่น"].firstMatch.waitForExistence(timeout: 5), "one station for two files")
        XCTAssertFalse(app.buttons["นำเข้า 2 สถานี"].isEnabled)

        pick(1, "ไม่นำเข้า")
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        one.tap()
        XCTAssertTrue(app.alerts["นำเข้าแล้ว 1 สถานี"].waitForExistence(timeout: 10), "the import should report it")
    }
}

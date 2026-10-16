import XCTest

/// The IEC 62446 test from nothing to the Excel, through the screens a tester uses (no sample data): set-up, the before
/// table's row fill and checks, every string's readings on the pad before and after the connection, the performance
/// and the conditions, then the export. The values are test inputs, not a station's measurements. iPad simulator:
/// `-only-testing:TCRoofUITests/IECFlowUITests`. It clears the first installing station's test (`-iecClear YES`).
final class IECFlowUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    /// Voc, Vmp before and after for the four strings of 16 panels.
    static let voc = ["752", "751", "753", "750"], vmp = ["612", "611", "613", "610"]

    /// `edge`: at the right edge, so the cursor lands after any text (the number fields are right-aligned); the narrow
    /// centred slot fields are tapped in the middle.
    func type(_ field: XCUIElement, _ text: String, _ what: String, edge: Bool = true) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), what)
        if edge { field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap() } else { field.tap() }
        // the keyboard can take a moment to attach to a field the form just scrolled in
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
        if XCTWaiter.wait(for: [focused], timeout: 3) != .completed { field.tap() }
        // a pre-filled value (the inverter's kW comes from the job's MP plan) is replaced, not added to
        if let old = field.value as? String, !old.isEmpty, old != field.placeholderValue, old != "—" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(text)
    }

    func button(_ app: XCUIApplication, _ label: String, contains: Bool = false) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: contains ? "label CONTAINS %@" : "label == %@", label)).firstMatch
    }

    func pad(_ app: XCUIApplication, _ text: String) {
        for c in text { app.buttons[c == "." ? "จุด" : String(c)].tap() }
    }

    func testFromSetUpToExcel() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecClear", "YES"]
        app.launch()

        // 1 · set-up: on iPad step 1's page
        let setUp = button(app, "ตั้งค่าการทดสอบ", contains: true)
        XCTAssertTrue(setUp.waitForExistence(timeout: slow), "a station with no test offers its set-up")
        setUp.tap()
        let panel = button(app, "แผงโซลาร์ แก้ไข")
        XCTAssertTrue(panel.waitForExistence(timeout: 15), "step 1's page")
        panel.tap()
        type(app.textFields["ยี่ห้อ / รุ่นแผง"], "Znshine", "panel")
        type(app.textFields["กำลังต่อแผง"], "570", "power")
        type(app.textFields["พื้นที่ต่อแผ่น"], "2.58", "area")
        app.buttons["เสร็จ"].firstMatch.tap()
        // the inverter's kW comes from the job (80); its S/N and strings 1–4 of 16 panels
        type(app.textFields["S/N อินเวอร์เตอร์"], "TEST-INV1\n", "serial")
        for slot in 1...4 { app.switches["String \(slot)"].tap() }
        XCTAssertTrue(app.staticTexts["4 / 20 ช่อง"].waitForExistence(timeout: 5))
        app.buttons["วันที่ทดสอบ"].tap()
        app.staticTexts["รายการสตริง (String list)"].tap()
        type(app.textFields["ผู้ทดสอบ"], String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "ทีมทดสอบ\n", "tester")
        for (row, serial) in [("แคลมป์มิเตอร์", "CLAMP-01"), ("เครื่องวัดฉนวน (IR)", "IR-01"), ("เครื่องวัดแสง", "SUN-01")] {
            app.buttons[row + " S/N"].tap()
            app.buttons["พิมพ์ S/N"].tap()
            let field = app.alerts.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), row)
            field.typeText(serial)
            app.alerts.buttons["บันทึก"].tap()
        }
        app.buttons["กลับ"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 / 4"].waitForExistence(timeout: 10), "1 inverter, 4 strings")

        // 2 · before: rows for every string, and the inverter's checks
        button(app, "ก่อนการเชื่อมต่อระบบ", contains: true).tap()
        // on iPad that is step 2's page; its ถัดไป opens the string table with every before row
        let toTable = button(app, "ถัดไป 3/7", contains: true)
        XCTAssertTrue(toTable.waitForExistence(timeout: 10), "step 2's page")
        toTable.tap()
        let fill = button(app, "กรอกทั้งแถว")
        XCTAssertTrue(fill.waitForExistence(timeout: 10))
        for item in ["Polarity ✓ ทุกสตริง", "Test Voltage 1000 V ทุกสตริง", "String Current 0 A ทุกสตริง (วงจรเปิด)"] {
            fill.tap(); button(app, item).tap()
        }
        for check in ["Continuity", "Inverter testing"] { button(app, check).tap(); button(app, "Normal").tap() }

        // 3 · every string on the pad: Voc → current (0, filled) → IR +E → IR −E → the next string
        app.buttons["ป้ายรูป (Word) ช่อง 1"].tap()
        button(app, "เปิดสตริงนี้ ›").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "INV1ST1")).firstMatch.waitForExistence(timeout: 10))
        let next = button(app, "ถัดไป ›")
        for v in Self.voc {
            pad(app, v); next.tap(); next.tap()
            pad(app, "250"); next.tap()
            pad(app, "300"); next.tap()
        }
        // after the connection: Vmp → Imp → the next string
        button(app, "หลังเชื่อมต่อ").tap()
        app.buttons["INV1ST1"].tap()
        for v in Self.vmp { pad(app, v); next.tap(); pad(app, "9.5"); next.tap() }
        app.buttons["กลับ"].firstMatch.tap()

        // 4 · after: the inverter check, the performance and the conditions
        button(app, "หลังเชื่อมต่อ").tap()
        button(app, "Inverter testing").tap(); button(app, "Normal").tap()
        button(app, "ผลการผลิต", contains: true).tap()
        type(app.textFields["พลังงานที่ผลิตได้ 7 วัน"], "920", "energy")
        type(app.textFields["Solar irradiance เฉลี่ย (Yr)"], "4.5", "Yr")
        type(app.textFields["Array Temperature"], "58", "array temperature")
        app.staticTexts["คำนวณให้"].tap()
        // 4 × 16 × 570 W = 36.48 kWp; 920 kWh ÷ 7 = 131.43 a day; Yf 3.60; PR 3.60 ÷ 4.5 = 0.80
        XCTAssertTrue(app.staticTexts["0.8"].waitForExistence(timeout: 10), "PR = Yf 3.60 ÷ Yr 4.5")
        button(app, "สภาพการทดสอบ", contains: true).tap()
        let ambient = app.textFields.matching(identifier: "อุณหภูมิอากาศ"), sun = app.textFields.matching(identifier: "ความเข้มแสง")
        let time = app.textFields.matching(identifier: "เวลาทดสอบ")
        XCTAssertTrue(ambient.firstMatch.waitForExistence(timeout: 10))
        type(ambient.element(boundBy: 0), "33.5", "ambient before"); type(sun.element(boundBy: 0), "980", "sun before")
        type(time.element(boundBy: 0), "10:30", "time before")
        type(ambient.element(boundBy: 1), "34", "ambient after"); type(sun.element(boundBy: 1), "1010", "sun after")
        type(time.element(boundBy: 1), "13:15", "time after")
        app.staticTexts["ผู้ทดสอบและเครื่องมือ"].tap()

        // 5 · the Excel
        app.buttons["กลับ"].firstMatch.tap()
        let export = button(app, "ส่งออก Excel IEC 62446", contains: true)
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30), "the export opens the share sheet")
    }

    /// A third inverter added on step 1's page exports too (its sheets are cloned from INV 02's), on the sample
    /// (`-iecDemo praek`): the file is `ตัวอย่าง แพรกหนามแดง …` in the app's `tmp/`.
    func testThirdInverterExports() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecDemo", "praek", "-iecStep", "1", "-iecCameraStub", "YES"]
        app.launch()

        // step 1's add sheet: the 60 kW model (6 MPPT, 12 strings of 16), its two required photos from the stub camera
        let add = button(app, "+ เพิ่มอินเวอร์เตอร์")
        XCTAssertTrue(add.waitForExistence(timeout: slow), "step 1's page")
        add.tap()
        app.buttons["ด้านหน้า"].firstMatch.tap()
        app.buttons["ด้านข้าง · ป้าย S/N"].firstMatch.tap()
        let commit = button(app, "เพิ่ม INV3")
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.tap()
        XCTAssertTrue(app.staticTexts["12/12 สตริง"].waitForExistence(timeout: 10))
        app.buttons["กลับ"].firstMatch.tap()

        let export = button(app, "ส่งออก Excel IEC 62446", contains: true)
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30),
                      "3 inverters export instead of being refused")
    }
}

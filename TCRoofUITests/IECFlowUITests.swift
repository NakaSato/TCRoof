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

    func type(_ field: XCUIElement, _ text: String, _ what: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), what)
        // at the right edge, so the cursor lands after any text (the number fields are right-aligned)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
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

        // 1 · set-up
        let setUp = button(app, "ตั้งค่าการทดสอบ", contains: true)
        XCTAssertTrue(setUp.waitForExistence(timeout: slow), "a station with no test offers its set-up")
        setUp.tap()
        type(app.textFields["ยี่ห้อ / รุ่นแผง"], "Znshine", "panel")
        type(app.textFields["กำลังต่อแผง"], "570", "power")
        type(app.textFields["พื้นที่ต่อแผ่น (datasheet)"], "2.58", "area")
        type(app.textFields["พิกัด inverter 1"], "80", "kW")
        type(app.textFields["S/N inverter 1"], "TEST-INV1", "serial")
        for slot in 1...4 { type(app.textFields["Inverter 1 ช่อง \(slot) จำนวนแผง"], "16", "slot \(slot)") }
        // the record section is further down the form
        let toggle = app.switches.matching(NSPredicate(format: "label == %@", "ระบุวันที่ทดสอบ")).firstMatch
        for _ in 0..<5 where !toggle.isHittable { app.textFields["Inverter 1 ช่อง 4 จำนวนแผง"].swipeUp() }
        XCTAssertTrue(toggle.isHittable, "the test date switch")
        toggle.tap()
        type(app.textFields["ผู้ทดสอบ"], "ทีมทดสอบ", "tester")
        type(app.textFields["S/N แคลมป์มิเตอร์"], "CLAMP-01", "clamp")
        type(app.textFields["S/N เครื่องวัดความเป็นฉนวน (IR)"], "IR-01", "IR tester")
        type(app.textFields["S/N เครื่องวัดความเข้มแสง"], "SUN-01", "irradiance meter")
        app.buttons["บันทึก"].tap()
        XCTAssertTrue(app.staticTexts["1 / 4"].waitForExistence(timeout: 10), "1 inverter, 4 strings")

        // 2 · before: rows for every string, and the inverter's checks
        button(app, "ก่อนการเชื่อมต่อระบบ", contains: true).tap()
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

    /// A third inverter added in the set-up exports too (its sheets are cloned from INV 02's), on the sample
    /// (`-iecDemo reset`): the file is `ตัวอย่าง แพรกหนามแดง …` in the app's `tmp/`.
    func testThirdInverterExports() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "home", "-homeTab", "pwa", "-homeBoard", "YES", "-installOpen", "YES", "-noNotificationPrompt", "YES",
                               "-iecOpen", "YES", "-iecDemo", "reset", "-iecSetup", "YES"]
        app.launch()

        XCTAssertTrue(app.textFields["S/N inverter 1"].waitForExistence(timeout: slow), "the set-up sheet")
        // below the two inverters; the form only builds rows near the screen
        let add = button(app, "เพิ่ม inverter", contains: true)
        for _ in 0..<10 where !(add.exists && add.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(add.isHittable, "เพิ่ม inverter")
        add.tap()
        type(app.textFields["พิกัด inverter 3"], "50", "kW")
        type(app.textFields["S/N inverter 3"], "TEST-INV3", "serial")
        // the slot grid is the section's next row, under the keyboard
        let slot1 = app.textFields["Inverter 3 ช่อง 1 จำนวนแผง"]
        for _ in 0..<4 where !(slot1.exists && slot1.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        for slot in 1...2 { type(app.textFields["Inverter 3 ช่อง \(slot) จำนวนแผง"], "16", "slot \(slot)") }
        app.buttons["บันทึก"].tap()

        let export = button(app, "ส่งออก Excel IEC 62446", contains: true)
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30),
                      "3 inverters export instead of being refused")
    }
}

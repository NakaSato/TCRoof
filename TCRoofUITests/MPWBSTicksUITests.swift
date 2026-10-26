import XCTest
import Compression

/// WBS ticks into the plan file (docs/specs/project-plan-wbs.md, step 3), on an iPad simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<ipad udid>' -only-testing:TCRoofUITests/MPWBSTicksUITests -derivedDataPath <scratch>`.
/// The first job starts from template P9-012 (`-mpClear YES -mpTemplate P9-012`) with 2.1.1 and 2.1.3 ticked (`-mpTickWBS`);
/// the Excel menu's export, copied by `-mpExportFile`, must carry the tick: `Y` in the `แผนโครงการ` sheet and the
/// export's record of ticked rows. The first job keeps that plan and tick.
final class MPWBSTicksUITests: XCTestCase {
    let slow: TimeInterval = 90
    let exported = URL(fileURLWithPath: "/private/tmp/TCRoofUITests-mp-wbs-export.xlsx")

    override func setUp() { continueAfterFailure = false }

    func testATickGoesIntoTheExportedFile() throws {
        try? FileManager.default.removeItem(at: exported)
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "mp", "-mpClear", "YES", "-mpTemplate", "P9-012", "-mpTickWBS", "2.1.1,2.1.3",
                               "-mpExportFile", exported.path, "-noNotificationPrompt", "YES"]
        app.launch()

        // the tick booked its share of 2.1 into the plan
        let menu = app.buttons["ไฟล์ Excel"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: slow), "the template's plan should show")
        XCTAssertFalse(app.staticTexts["ทำได้ 0%"].firstMatch.exists, "the tick should count in the plan's progress")

        menu.tap()
        let export = app.buttons["ส่งออกไฟล์แผน (Excel)"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "ActivityListView").firstMatch.waitForExistence(timeout: 30),
                      "the export should open the share sheet")

        let zip = try Zip(Data(contentsOf: exported))
        let sheet = try XCTUnwrap(zip.text("xl/worksheets/sheet1.xml"), "the แผนโครงการ sheet")
        XCTAssertEqual(sheet.components(separatedBy: #"t="inlineStr"><is><t>Y</t></is>"#).count - 1, 2, "two rows marked Y")
        let record = zip.paths.filter { $0.hasPrefix("customXml/item") && !$0.hasPrefix("customXml/itemProps") }
            .compactMap(zip.text).first { $0.contains("urn:tcroof:wbs-ticks") }
        // the record is JSON escaped into XML: ["2.1.1","2.1.3"]
        XCTAssertTrue(record?.contains("&quot;2.1.1&quot;,&quot;2.1.3&quot;") == true, "the export keeps which rows it ticked: \(record ?? "none")")
    }
}

/// Just enough of a zip reader for the test: the central directory's entries, stored or deflated.
private struct Zip {
    struct Entry { let method: UInt16; let compressed: Int; let size: Int; let offset: Int }
    let data: Data
    let entries: [String: Entry]
    var paths: [String] { Array(entries.keys) }

    init(_ data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: { u32($0) == 0x06054b50 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var out: [String: Entry] = [:], at = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            let nameLength = u16(at + 28), extra = u16(at + 30), comment = u16(at + 32)
            let name = String(decoding: bytes[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            out[name] = Entry(method: UInt16(u16(at + 10)), compressed: u32(at + 20), size: u32(at + 24), offset: u32(at + 42))
            at += 46 + nameLength + extra + comment
        }
        entries = out
    }

    func text(_ path: String) -> String? {
        guard let e = entries[path] else { return nil }
        let bytes = [UInt8](data)
        let local = e.offset
        let start = local + 30 + (Int(bytes[local + 26]) | Int(bytes[local + 27]) << 8) + (Int(bytes[local + 28]) | Int(bytes[local + 29]) << 8)
        let body = Array(bytes[start..<(start + e.compressed)])
        if e.method == 0 { return String(decoding: body, as: UTF8.self) }
        var out = [UInt8](repeating: 0, count: e.size)
        let n = compression_decode_buffer(&out, e.size, body, body.count, nil, COMPRESSION_ZLIB)
        return n == e.size ? String(decoding: out, as: UTF8.self) : nil
    }
}

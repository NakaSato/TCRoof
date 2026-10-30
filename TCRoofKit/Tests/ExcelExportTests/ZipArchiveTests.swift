import XCTest
@testable import ExcelExport

final class ZipArchiveTests: XCTestCase {
    func testMixedEntriesAndSlicedInput() throws {
        let xml = String(repeating: "<t>สวัสดี &amp; hello</t>", count: 10_000)
        let photo = Data((0..<65_536).map { UInt8($0 & 0xff) })
        var zip = ZipArchive()
        zip.set("เอกสาร/sheet.xml", xml)
        zip.set("media/photo.jpg", photo)
        zip.set("empty", Data())
        let bytes = try zip.write()
        XCTAssertLessThan(bytes.count, photo.count + xml.utf8.count / 4)

        // Data slices need not start at zero; ZIP offsets are relative to the archive's start.
        var prefixed = Data([1, 2, 3])
        prefixed.append(bytes)
        let decoded = try ZipArchive(prefixed.dropFirst(3))
        XCTAssertEqual(decoded.paths, zip.paths)
        XCTAssertEqual(decoded.string("เอกสาร/sheet.xml"), xml)
        XCTAssertEqual(decoded.data("media/photo.jpg"), photo)
        XCTAssertEqual(decoded.data("empty"), Data())
    }

    func testEmptyArchiveAndShortInput() throws {
        XCTAssertTrue(try ZipArchive(ZipArchive().write()).paths.isEmpty)
        XCTAssertThrowsError(try ZipArchive(Data()))
        XCTAssertThrowsError(try ZipArchive(Data([0x50, 0x4b])))
    }
}

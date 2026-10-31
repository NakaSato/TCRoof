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

    func testReadsIndependentDeflatedEntriesWithDataDescriptors() throws {
        // Python zipfile writing to a non-seekable stream: local sizes/CRCs are zero,
        // with authoritative values in data descriptors and the central directory.
        let encoded = "UEsDBBQACAAIAAAAIQAAAAAAAAAAAAAAAAAJAAAAc2hlZXQueG1ssymxy0jNycm30S+xAwBQSwcIwk0bBg4AAAAMAAAAUEsDBBQACAAIAAAAIQAAAAAAAAAAAAAAAAAFAAAAZW1wdHkDAFBLBwgAAAAAAgAAAAAAAABQSwECFAMUAAgACAAAACEAwk0bBg4AAAAMAAAACQAAAAAAAAAAAAAAgAEAAAAAc2hlZXQueG1sUEsBAhQDFAAIAAgAAAAhAAAAAAACAAAAAAAAAAUAAAAAAAAAAAAAAIABRQAAAGVtcHR5UEsFBgAAAAACAAIAagAAAHoAAAAAAA=="
        let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
        let archive = try ZipArchive(bytes)
        XCTAssertEqual(archive.string("sheet.xml"), "<t>hello</t>")
        XCTAssertEqual(archive.data("empty"), Data())
    }

    private func fixture(name: String = "sheet.xml", size: Int = 1000) throws -> Data {
        var archive = ZipArchive()
        archive.set(name, Data(repeating: 65, count: size))
        return try archive.write()
    }

    private func centralOffset(_ data: Data) throws -> Int {
        try XCTUnwrap(data.range(of: Data([0x50, 0x4b, 0x01, 0x02]))).lowerBound
    }

    private func replacing(_ data: Data, offset: Int, value: UInt32) -> Data {
        var changed = data
        for i in 0..<4 { changed[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
        return changed
    }

    func testRejectsOversizedEntryBeforeInflating() throws {
        let original = try fixture()
        let central = try centralOffset(original)
        let forged = replacing(original, offset: central + 24, value: UInt32.max)
        XCTAssertThrowsError(try ZipArchive(forged, limits: .init(maxEntryBytes: 1024, maxExpandedBytes: 2048))) { error in
            guard case ZipArchive.Failure.unsupported = error else { return XCTFail("Size limit did not reject entry: \(error)") }
        }
    }

    func testRejectsEntryAboveConfiguredLimit() throws {
        XCTAssertThrowsError(try ZipArchive(fixture(), limits: .init(maxEntryBytes: 999)))
        let accepted = try ZipArchive(fixture(), limits: .init(maxEntryBytes: 1000, maxExpandedBytes: 1000))
        XCTAssertEqual(accepted.data("sheet.xml")?.count, 1000)
    }

    func testEnforcesCumulativeLimitIncludingDirectories() throws {
        for name in ["first.bin", "first/"] {
            var zip = ZipArchive()
            zip.set(name, Data(repeating: 65, count: 32))
            zip.set("second.bin", Data(repeating: 66, count: 32))
            let bytes = try zip.write()
            XCTAssertThrowsError(try ZipArchive(bytes, limits: .init(maxEntryBytes: 32, maxExpandedBytes: 63))) { error in
                guard case ZipArchive.Failure.unsupported = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertEqual(try ZipArchive(bytes, limits: .init(maxEntryBytes: 32, maxExpandedBytes: 64)).data("second.bin")?.count, 32)
        }
    }

    func testRejectsWrongCRC() throws {
        let original = try fixture()
        let forged = replacing(original, offset: try centralOffset(original) + 16, value: 0)
        XCTAssertThrowsError(try ZipArchive(forged)) { error in
            guard case ZipArchive.Failure.corrupt = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testRejectsWrongExpandedSize() throws {
        for name in ["sheet.xml", "image.jpg"] {
            let original = try fixture(name: name)
            let central = try centralOffset(original)
            for size in [UInt32(999), UInt32(1001)] {
                let forged = replacing(original, offset: central + 24, value: size)
                XCTAssertThrowsError(try ZipArchive(forged)) { error in
                    guard case ZipArchive.Failure.corrupt = error else { return XCTFail("Unexpected error: \(error)") }
                }
            }
        }
    }

    func testDetectsCorruptedStoredPayload() throws {
        var bytes = try fixture(name: "photo.jpg")
        // The fixture has one local header, no extra field, and this ASCII filename.
        bytes[30 + "photo.jpg".utf8.count] ^= 1
        XCTAssertThrowsError(try ZipArchive(bytes)) { error in
            guard case ZipArchive.Failure.corrupt = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testZeroLimitsAllowOnlyEmptyContentAndRejectNegativeLimits() throws {
        var empty = ZipArchive()
        empty.set("empty", Data())
        XCTAssertEqual(try ZipArchive(empty.write(), limits: .init(maxEntryBytes: 0, maxExpandedBytes: 0)).data("empty"), Data())
        XCTAssertThrowsError(try ZipArchive(empty.write(), limits: .init(maxEntryBytes: -1)))
        XCTAssertThrowsError(try ZipArchive(empty.write(), limits: .init(maxExpandedBytes: -1)))
    }
}

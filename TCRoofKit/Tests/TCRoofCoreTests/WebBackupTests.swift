import XCTest
@testable import TCRoofCore

final class WebBackupTests: XCTestCase {
    private func tmpStore() -> JobStore {
        JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("wb-" + UUID().uuidString))
    }

    // MARK: ImageSize

    /// A JPEG header: SOI, then `segments` (marker, payload), then a frame header of `width` × `height`.
    private func jpeg(_ width: Int, _ height: Int, frame: UInt8 = 0xC0, before segments: [(UInt8, [UInt8])] = [], padding: [UInt8] = []) -> Data {
        var b: [UInt8] = [0xFF, 0xD8]
        for (m, payload) in segments {
            let len = payload.count + 2
            b += [0xFF, m, UInt8(len >> 8), UInt8(len & 0xFF)] + payload
        }
        b += padding
        // SOFn: length 17, precision 8, height, width, 3 components
        b += [0xFF, frame, 0x00, 0x11, 0x08, UInt8(height >> 8), UInt8(height & 0xFF), UInt8(width >> 8), UInt8(width & 0xFF), 0x03]
        b += [UInt8](repeating: 0, count: 9) + [0xFF, 0xD9]
        return Data(b)
    }

    func testJPEGSizeFromTheFrameHeader() {
        let app0: (UInt8, [UInt8]) = (0xE0, Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0])
        let dqt: (UInt8, [UInt8]) = (0xDB, [UInt8](repeating: 1, count: 65))
        let size = ImageSize.of(jpeg(4032, 3024, before: [app0, dqt]))
        XCTAssertEqual(size?.width, 4032)
        XCTAssertEqual(size?.height, 3024)
        // progressive JPEGs (SOF2) too
        XCTAssertEqual(ImageSize.of(jpeg(800, 600, frame: 0xC2))?.width, 800)
    }

    func testJPEGSkipsTablesFillBytesAndRestartMarkers() {
        // DHT (C4) sits in the SOF range but holds no size; it must be skipped, not read
        let dht: (UInt8, [UInt8]) = (0xC4, [UInt8](repeating: 0x7F, count: 20))
        let size = ImageSize.of(jpeg(1280, 960, before: [dht], padding: [0x00, 0xFF, 0xD0, 0xFF, 0x01]))
        XCTAssertEqual(size?.width, 1280)
        XCTAssertEqual(size?.height, 960)
    }

    func testPNGSizeAndUnknownData() {
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13] + Array("IHDR".utf8)
        png += [0, 0, 0x07, 0x80, 0, 0, 0x04, 0x38] + [8, 6, 0, 0, 0]
        let size = ImageSize.of(Data(png))
        XCTAssertEqual(size?.width, 1920)
        XCTAssertEqual(size?.height, 1080)
        XCTAssertNil(ImageSize.of(Data("GIF89a......".utf8)))
        XCTAssertNil(ImageSize.of(Data([0xFF, 0xD8, 0xFF])), "too short")
        XCTAssertNil(ImageSize.of(Data([0xFF, 0xD8] + [UInt8](repeating: 0x00, count: 40))), "no frame header")
    }

    // MARK: import / export

    func testDriveLinkSurvivesTheBackup() throws {
        let s = tmpStore()
        var j = Job.new(template: JobTemplate.all[2])
        var link = DriveLink()
        link.rootID = "root-1"; link.folderID = "folder-9"; link.folderURL = "https://drive.google.com/drive/folders/folder-9"
        link.folderName = "NO.224 สถานีลาดพร้าว"
        link.lastSaved = Date(timeIntervalSince1970: 1_790_000_000.5)
        j.drive = link
        let back = try WebBackup.importJobs(WebBackup.exportBackup([j], store: s), into: tmpStore())[0]
        XCTAssertEqual(back.drive?.rootID, "root-1")
        XCTAssertEqual(back.drive?.folderID, "folder-9")
        XCTAssertEqual(back.drive?.folderURL, link.folderURL)
        XCTAssertEqual(back.drive?.folderName, "NO.224 สถานีลาดพร้าว")
        XCTAssertEqual(back.drive?.lastSaved?.timeIntervalSince1970 ?? 0, 1_790_000_000.5, accuracy: 0.001)

        let plain = try WebBackup.importJobs(WebBackup.exportBackup([Job.new(template: JobTemplate.all[2])], store: s), into: tmpStore())[0]
        XCTAssertNil(plain.drive, "no drive block, no link")
    }

    func testOtherFilesAreRefused() {
        XCTAssertThrowsError(try WebBackup.importJobs(Data(#"{"app":"other","jobs":[]}"#.utf8), into: tmpStore())) { e in
            XCTAssertEqual(e.localizedDescription, "ไฟล์นี้ไม่ใช่ข้อมูลแบบสำรวจ (solar-survey)")
        }
        XCTAssertEqual(try WebBackup.importJobs(Data(#"{"app":"solar-survey","jobs":[]}"#.utf8), into: tmpStore()).count, 0)
    }

    func testDatesInEveryWebFormat() throws {
        let utc = { (s: String) in try XCTUnwrap(WebBackup.date(s)).timeIntervalSince1970 }
        XCTAssertEqual(WebBackup.date(NSNumber(value: 1_790_000_000_250.0))?.timeIntervalSince1970 ?? 0, 1_790_000_000.25, accuracy: 0.001, "milliseconds")
        XCTAssertEqual(try utc("2026-09-30T02:30:00.500Z"), 1_790_735_400.5, accuracy: 0.001)
        XCTAssertEqual(try utc("2026-09-30T02:30:00Z"), 1_790_735_400, accuracy: 0.001)
        XCTAssertEqual(WebBackup.date("2026-09-30"), ISODate.date("2026-09-30"), "a plain day")
        XCTAssertNil(WebBackup.date("เมื่อวาน"))
        XCTAssertNil(WebBackup.date(nil))
        // and they write back with milliseconds
        XCTAssertEqual(WebBackup.iso(Date(timeIntervalSince1970: 1_790_735_400.5)), "2026-09-30T02:30:00.500Z")
    }

    func testStableIDsForWebIDs() {
        XCTAssertEqual(WebBackup.stableUUID("muk7y0k8bja16"), WebBackup.stableUUID("muk7y0k8bja16"))
        XCTAssertNotEqual(WebBackup.stableUUID("muk7y0k8bja16"), WebBackup.stableUUID("muk7y0k8bja17"))
        // a version-5-style, RFC 4122 variant id
        let u = WebBackup.stableUUID("abc").uuidString
        XCTAssertEqual(Array(u)[14], "5")
        XCTAssertTrue("89AB".contains(Array(u)[19]))
    }
}

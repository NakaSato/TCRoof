import XCTest
@testable import TCRoof
import TCRoofCore

/// Who added a scan or photo travels on its record (`AddedByRecord`): firestore.rules let a contractor change or
/// delete only their own.
final class AddedByRecordTests: XCTestCase {
    func testAScanCarriesWhoAddedIt() throws {
        let device = ScannedDevice(kind: .panel, serial: "ZN-001", scannedBy: "ช่างเอ")
        XCTAssertNil(device.record.addedBy)
        device.addedBy = "foreman@contractor.co"
        let data = try JSONEncoder().encode(device.record)
        let decoded = try JSONDecoder().decode(ScannedDevice.Record.self, from: data)
        XCTAssertEqual(decoded.addedBy, "foreman@contractor.co")
    }

    func testACopyFromAnOlderBuildKeepsWhoAddedIt() {
        let device = ScannedDevice(kind: .panel, serial: "ZN-001", scannedBy: "ช่างเอ")
        device.addedBy = "foreman@contractor.co"
        var older = device.record
        older.addedBy = nil
        older.serial = "ZN-002"
        XCTAssertTrue(device.apply(older, jobs: [:]))
        XCTAssertEqual(device.serial, "ZN-002")
        XCTAssertEqual(device.addedBy, "foreman@contractor.co")
        // a copy naming someone is taken
        var named = device.record
        named.addedBy = "team@tcroof.co"
        XCTAssertTrue(device.apply(named, jobs: [:]))
        XCTAssertEqual(device.addedBy, "team@tcroof.co")
    }

    func testARecordFromBeforeItDecodes() throws {
        let json = #"{"kind":"panel","serial":"ZN-001","scannedBy":"ช่างเอ","scannedAt":1730000000000}"#
        let record = try JSONDecoder().decode(ScannedDevice.Record.self, from: Data(json.utf8))
        XCTAssertNil(record.addedBy)
    }
}

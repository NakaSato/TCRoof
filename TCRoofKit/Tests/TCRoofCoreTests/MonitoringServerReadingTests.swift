import XCTest
@testable import TCRoofCore

/// `Monitoring.ServerReading` (CHA-93): a `monitoring/{station}` document from the Cloud Function's poll, its Growatt
/// answers parsed as the app parses its own, and when an iPad takes it instead of reading Growatt itself.
final class MonitoringServerReadingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_200_000)

    /// Growatt's answers as the function keeps them: the reply's text, `error_code` and all.
    let fields: [String: Any] = [
        "stationID": "job-1",
        "plantID": 7,
        "data": #"{"error_code":0,"error_msg":"","data":{"today_energy":"412.5","monthly_energy":"9000","yearly_energy":"0","total_energy":"290000","current_power":148.2,"last_update_time":"2026-11-09 13:55:00","timezone":"GMT+7"}}"#,
        "power": #"{"error_code":0,"data":{"powers":[{"time":"2026-11-09 13:50","power":150000},{"time":"2026-11-09 13:55","power":null}]}}"#,
        "devices": #"{"error_code":0,"data":{"devices":[{"device_sn":"INV1","type":1,"status":3,"last_update_time":"2026-11-09 13:55:00"}]}}"#,
        "days": #"{"error_code":0,"error_msg":"","data":{"energys":[{"date":"2026-11-08","energy":"700"}]}}"#,
        "months": #"{"error_code":0,"data":{"energys":[{"date":"2026-10","energy":21000}]}}"#,
        "failure": NSNull(),
    ]

    func testTheFunctionsAnswersReadAsTheAppsOwn() throws {
        let r = try XCTUnwrap(Monitoring.ServerReading(fields: fields, readAt: now))
        XCTAssertEqual(r.stationID, "job-1")
        XCTAssertEqual(r.plantID, 7)
        XCTAssertEqual(r.reading.data?.todayEnergy, 412.5)
        XCTAssertEqual(r.reading.data?.timezone, "GMT+7")
        XCTAssertEqual(r.reading.power, [.init(time: "2026-11-09 13:50", power: 150_000), .init(time: "2026-11-09 13:55", power: nil)])
        XCTAssertEqual(r.reading.devices?.first?.isFault, true)
        XCTAssertEqual(r.reading.days, [.init(date: "2026-11-08", energy: 700)])
        XCTAssertEqual(r.reading.months, [.init(date: "2026-10", energy: 21_000)])
        XCTAssertNil(r.reading.yesterdayPower, "not read yet: the map keeps the station's own")
        XCTAssertNil(r.failure)
    }

    func testAMissingOrUnreadablePartIsNil() throws {
        var f = fields
        f["power"] = "not json"
        f["devices"] = nil
        f["plantID"] = "7"
        f["failure"] = ["code": "10011", "message": "Growatt ไม่อนุญาต (token ไม่ถูกต้อง)"]
        let r = try XCTUnwrap(Monitoring.ServerReading(fields: f, readAt: nil))
        XCTAssertNil(r.reading.power)
        XCTAssertNil(r.reading.devices)
        XCTAssertNotNil(r.reading.data)
        XCTAssertEqual(r.plantID, 7, "a number written as text still reads")
        XCTAssertEqual(r.failure, "Growatt ไม่อนุญาต (token ไม่ถูกต้อง)")
        XCTAssertNil(Monitoring.ServerReading(fields: ["plantID": 7], readAt: now), "no station")
        XCTAssertNil(Monitoring.ServerReading(fields: ["stationID": "a"], readAt: now), "no plant")
    }

    func testFreshWithinTwoPollsForThePlantPairedNow() throws {
        let r = try XCTUnwrap(Monitoring.ServerReading(fields: fields, readAt: now))
        XCTAssertTrue(r.fresh(now: now.addingTimeInterval(10 * 60), plantID: 7, pollMinutes: 5))
        XCTAssertTrue(r.fresh(now: now.addingTimeInterval(11 * 60), plantID: 7, pollMinutes: 5), "a minute's slack")
        XCTAssertFalse(r.fresh(now: now.addingTimeInterval(12 * 60), plantID: 7, pollMinutes: 5), "the function stopped: the iPad reads")
        XCTAssertTrue(r.fresh(now: now.addingTimeInterval(25 * 60), plantID: 7, pollMinutes: 15))
        XCTAssertFalse(r.fresh(now: now, plantID: 8, pollMinutes: 5), "paired with another plant since")
        let never = Monitoring.ServerReading(stationID: "a", plantID: 7, readAt: nil, reading: .init())
        XCTAssertFalse(never.fresh(now: now, plantID: 7, pollMinutes: 5))
    }
}

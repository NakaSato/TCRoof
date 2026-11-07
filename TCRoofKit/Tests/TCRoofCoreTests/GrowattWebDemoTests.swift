import XCTest
@testable import TCRoofCore

/// `GrowattWebDemo`'s parsing, on the portal's answers for its example plants (server.growatt.com, 7 Nov 2026).
final class GrowattWebDemoTests: XCTestCase {
    private let list = Data(#"[{"timezone":"1","id":"10719705","plantName":"Res*************t"},{"timezone":"1","id":"10839635","plantName":"Ene****************t"}]"#.utf8)

    private let info = Data("""
    {"result":1,"obj":{"country":"not open","timezone":"1","creatDate":"2026-02-11","id":"10719705","plantType":"0",
    "nominalPower":"0","eTotal":"9322.8","plantName":"ENR*******************S","moneyUnitText":"¥"}}
    """.utf8)

    private let devices = Data("""
    {"result":1,"obj":{"currPage":1,"pages":1,"pageSize":4,"count":1,"datas":[{"deviceType":"1","timeServer":"2026-11-07 23:02:02",
    "plantId":"10719705","deviceTypeName":"tlx","nominalPower":"6000.0","eToday":"27.8","eMonth":"211.6","eTotal":"9322.8",
    "pac":"2274.7","datalogSn":"ZGQ0F5705J","deviceModel":"MIN 6000TL-XH","sn":"ZNL1CKR19Z","plantName":"Res*************t",
    "status":"1","lastUpdateTime":"2026-11-07 16:02:02"}]}}
    """.utf8)

    private let notSignedIn = Data("<html><title>Error500</title>you have not login to the system</html>".utf8)

    func testPlantList() throws {
        let plants = try GrowattWebDemo.parseList(list)
        XCTAssertEqual(plants.map(\.id), ["10719705", "10839635"])
        XCTAssertEqual(plants[0].name, "Res*************t")
    }

    func testPlant() throws {
        let p = try GrowattWebDemo.parsePlant(info, devices: devices, id: "10719705", name: "Res*************t")
        XCTAssertEqual(p.name, "Res*************t")
        XCTAssertEqual(p.nominalPower, 0)
        XCTAssertEqual(p.eTotal, 9322.8)
        XCTAssertEqual(p.devices.count, 1)
        XCTAssertEqual(p.devices[0].model, "MIN 6000TL-XH")
        XCTAssertEqual(p.devices[0].pac, 2274.7)
        XCTAssertEqual(p.devices[0].status, 1)
    }

    func testSignedOutPageIsAnError() {
        XCTAssertThrowsError(try GrowattWebDemo.parsePlant(notSignedIn, devices: devices, id: "1", name: "x")) {
            XCTAssertEqual($0 as? GrowattAPI.Failure, .badResponse)
        }
        XCTAssertThrowsError(try GrowattWebDemo.parseList(notSignedIn))
    }

    func testSummary() throws {
        var p = try GrowattWebDemo.parsePlant(info, devices: devices, id: "10719705", name: "Res*************t")
        let s = GrowattWebDemo.summary(p)
        XCTAssertEqual(s.id, "growatt-web-10719705")
        // the plant gives no size: its inverter's 6 kW
        XCTAssertEqual(s.kWp, 6)
        XCTAssertEqual(s.energy, 27.8)
        XCTAssertEqual(s.status, .normal)
        XCTAssertEqual(s.note, "Growatt | 2.27 kW | อัปเดต 16:02")

        p.devices[0].status = 3
        XCTAssertEqual(GrowattWebDemo.summary(p).status, .alarm)
        p.devices[0].status = -1
        XCTAssertEqual(GrowattWebDemo.summary(p).status, .offline)
        p.devices = []
        XCTAssertEqual(GrowattWebDemo.summary(p).status, .offline)
        p.nominalPower = 10880
        XCTAssertEqual(GrowattWebDemo.summary(p).kWp, 10.88)
    }

    func testDayCurve() throws {
        // 288 samples: 1 kW through 06:00–06:55, 2 kW 12:00–12:25 then not reached yet
        var pac: [Any] = Array(repeating: 0.0, count: 288)
        for i in 72..<84 { pac[i] = 1000.0 }
        for i in 144..<150 { pac[i] = 2000.0 }
        for i in 150..<288 { pac[i] = NSNull() }
        let body = try JSONSerialization.data(withJSONObject: ["result": 1, "obj": [["datas": ["pac": pac], "type": "plant"]]])
        let day = try GrowattWebDemo.parseDay(body)
        XCTAssertEqual(day.count, 288)
        XCTAssertNil(day[200])
        let hours = GrowattWebDemo.hourly(day)
        XCTAssertEqual(hours.count, 13)
        XCTAssertEqual(hours[0], 1)
        // 12:00 averages only the samples it has
        XCTAssertEqual(hours[6], 2)
        XCTAssertEqual(hours[12], 0)
        XCTAssertThrowsError(try GrowattWebDemo.parseDay(notSignedIn))
    }

    func testStationDetail() throws {
        let p = try GrowattWebDemo.parsePlant(info, devices: devices, id: "10719705", name: "Res*************t")
        let row = GrowattWebDemo.summary(id: p.id, name: p.name)
        let loading = MaintenanceStationDetail.growatt(summary: row)
        XCTAssertTrue(loading.inverters.isEmpty)
        XCTAssertEqual(loading.summary.name, "Res*************t")

        let d = MaintenanceStationDetail.growatt(summary: row, plant: p, day: Array(repeating: 3000, count: 288))
        XCTAssertEqual(d.summary.energy, 27.8)
        XCTAssertEqual(d.inverters.count, 1)
        XCTAssertEqual(d.inverters[0].model, "MIN 6000TL-XH | SN …R19Z")
        XCTAssertEqual(d.inverters[0].power, "2.27 kW")
        XCTAssertFalse(d.inverters[0].isError)
        XCTAssertEqual(d.actualHourly, Array(repeating: 3, count: 13))
        XCTAssertEqual(d.energyThisMonth, "211.6 kWh")
        XCTAssertEqual(d.energyExpectedThisMonth, "ทั้งหมด 9.3 MWh")
        XCTAssertEqual(d.co2SavedThisMonth, "106 kg")
        XCTAssertEqual(d.lastUpdated, "16:02")
        XCTAssertEqual(d.prToday, 0)
        XCTAssertTrue(d.contractorPhone.isEmpty)
        XCTAssertNil(d.issueTitle)
        XCTAssertEqual(d.equipmentGroups.map(\.title), ["อินเวอร์เตอร์", "สื่อสาร"])
        XCTAssertEqual(d.equipmentGroups[1].rows.first?.key, "ZGQ0F5705J")
        XCTAssertTrue(d.tickets.isEmpty && d.pmHistory.isEmpty && d.nextPM == nil)
    }
}

/// The whole chain against the live portal: `GROWATT_LIVE=1 swift test --filter GrowattWebDemoLiveTests`.
final class GrowattWebDemoLiveTests: XCTestCase {
    func testExamplePlants() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GROWATT_LIVE"] == "1", "set GROWATT_LIVE=1 to call server.growatt.com")
        let web = GrowattWebDemo()
        try await web.openGuest()
        let list = try await web.plantList()
        XCTAssertFalse(list.isEmpty)
        let plant = try await web.plant(id: list[0].id, name: list[0].name)
        XCTAssertFalse(plant.devices.isEmpty)
        let date = String(plant.devices.map(\.lastUpdate).max()?.prefix(10) ?? "")
        let day = try await web.dayPower(plantID: plant.id, date: date)
        XCTAssertEqual(day.count, 288)
        print("live:", GrowattWebDemo.summary(plant), GrowattWebDemo.hourly(day).map { String(format: "%.2f", $0) })
    }
}

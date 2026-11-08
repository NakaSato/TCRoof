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

    func testBusinessListMerged() throws {
        let business = Data(#"[{"unit":"¥","logoImgName":"","timezone":"-4","id":"11089901","plantImgName":"null","plantName":"Com************t","plantType":"1"}]"#.utf8)
        let all = GrowattWebDemo.merged(try GrowattWebDemo.parseList(list), try GrowattWebDemo.parseList(business))
        XCTAssertEqual(all.map(\.id), ["10719705", "10839635", "11089901"])
        XCTAssertEqual(all[2].name, "Com************t")
        // a plant on both lists is listed once
        XCTAssertEqual(GrowattWebDemo.merged(try GrowattWebDemo.parseList(list), try GrowattWebDemo.parseList(list)).count, 2)
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

    /// One page of the portal's device list: `n` inverters from serial `start`, page `page` of `pages`.
    private func devicesPage(_ page: Int, of pages: Int, start: Int, n: Int) throws -> Data {
        let rows = (start..<(start + n)).map { i -> [String: Any] in
            ["sn": "SN\(i)", "deviceModel": "MAX 125KTL3-X2 LV", "deviceTypeName": "max", "status": "1", "pac": "1000.0",
             "eToday": "10", "eMonth": "100", "eTotal": "1000", "nominalPower": "125000.0", "lastUpdateTime": "2026-11-07 11:49:2\(i % 10)"]
        }
        return try JSONSerialization.data(withJSONObject: ["result": 1, "obj": ["currPage": page, "pages": pages, "pageSize": 4,
                                                                                 "count": 10, "datas": rows]])
    }

    func testDevicesOnEveryPage() throws {
        // 10 inverters, 4 to a page: pages 1–3
        let pages = [try devicesPage(1, of: 3, start: 0, n: 4), try devicesPage(2, of: 3, start: 4, n: 4), try devicesPage(3, of: 3, start: 8, n: 2)]
        XCTAssertEqual(try GrowattWebDemo.devicePage(pages[0]).pages, 3)
        XCTAssertEqual(try GrowattWebDemo.devicePage(devices).pages, 1)
        let p = try GrowattWebDemo.parsePlant(info, devicePages: pages, id: "1", name: "C")
        XCTAssertEqual(p.devices.count, 10)
        XCTAssertEqual(p.devices.map(\.sn).last, "SN9")
        // a device repeated on two pages counts once
        let again = try GrowattWebDemo.parsePlant(info, devicePages: pages + [pages[2]], id: "1", name: "C")
        XCTAssertEqual(again.devices.count, 10)
        XCTAssertEqual(GrowattWebDemo.summary(p).kWp, 1250)
        XCTAssertEqual(GrowattWebDemo.summary(p).energy, 100)
    }

    /// `plant(id:name:)` asks for the totals and the device pages together (the portal can take about 70 s over each on a
    /// cold plant) and still keeps the pages in order.
    func testPlantCallsOverlap() async throws {
        let pages = [try devicesPage(1, of: 3, start: 0, n: 4), try devicesPage(2, of: 3, start: 4, n: 4), try devicesPage(3, of: 3, start: 8, n: 2)]
        PortalStub.reset(info: info, pages: pages)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PortalStub.self]
        let p = try await GrowattWebDemo(session: URLSession(configuration: config)).plant(id: "1", name: "C")
        XCTAssertEqual(p.devices.map(\.sn), (0..<10).map { "SN\($0)" })
        XCTAssertEqual(p.eTotal, 9322.8)
        XCTAssertEqual(PortalStub.calls, 4)
        // the totals with page 1, then pages 2 and 3 together
        XCTAssertGreaterThanOrEqual(PortalStub.mostAtOnce, 2)
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
        // the card's live line
        XCTAssertEqual(s.powerNow ?? 0, 2.2747, accuracy: 0.0001)
        XCTAssertEqual(s.invertersOnline, 1)
        XCTAssertEqual(s.invertersTotal, 1)
        XCTAssertEqual(s.updated, "16:02")

        p.devices[0].status = 3
        XCTAssertEqual(GrowattWebDemo.summary(p).status, .alarm)
        p.devices[0].status = -1
        XCTAssertEqual(GrowattWebDemo.summary(p).status, .offline)
        // offline: no live power, no inverter reporting
        XCTAssertNil(GrowattWebDemo.summary(p).powerNow)
        XCTAssertEqual(GrowattWebDemo.summary(p).invertersOnline, 0)
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
        XCTAssertEqual(d.energyTotal, "9.3 MWh")
        // 2274.7 W of a 6000 W inverter
        XCTAssertEqual(d.inverters[0].share ?? 0, 0.3791, accuracy: 0.0001)
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
        // the home dashboard's 2 plants and the business dashboard's commercial one
        XCTAssertGreaterThanOrEqual(list.count, 3)
        let plant = try await web.plant(id: list[list.count - 1].id, name: list[list.count - 1].name)
        XCTAssertFalse(plant.devices.isEmpty)
        let date = String(plant.devices.map(\.lastUpdate).max()?.prefix(10) ?? "")
        let day = try await web.dayPower(plantID: plant.id, date: date)
        XCTAssertEqual(day.count, 288)
        print("live:", GrowattWebDemo.summary(plant), GrowattWebDemo.hourly(day).map { String(format: "%.2f", $0) })
    }

    /// Every plant, one after another as `GrowattDemoFeed` loads them: each must load.
    func testEveryPlantLoads() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GROWATT_LIVE"] == "1", "set GROWATT_LIVE=1 to call server.growatt.com")
        let web = GrowattWebDemo()
        try await web.openGuest()
        for p in try await web.plantList() {
            do {
                let plant = try await web.plant(id: p.id, name: p.name)
                print("live plant:", p.id, p.name, plant.devices.count, "devices")
            } catch {
                XCTFail("plant \(p.id) \(p.name): \(error)")
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

/// The portal for one plant: `getPlantData` gives `info`, `getDevicesByPlantList` the page its form asks for. Each answer
/// waits 0.2 s, so calls asked together are seen open at once (`mostAtOnce`).
private final class PortalStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var info = Data()
    nonisolated(unsafe) private static var pages: [Data] = []
    nonisolated(unsafe) private static var open = 0
    nonisolated(unsafe) private static var most = 0
    nonisolated(unsafe) private static var count = 0

    static func reset(info: Data, pages: [Data]) {
        lock.lock(); self.info = info; self.pages = pages; open = 0; most = 0; count = 0; lock.unlock()
    }
    static var mostAtOnce: Int { lock.lock(); defer { lock.unlock() }; return most }
    static var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.body(of: request)
        let page = body.split(separator: "&").first { $0.hasPrefix("currPage=") }.flatMap { Int($0.dropFirst(9)) }
        Self.lock.lock()
        Self.open += 1; Self.count += 1; Self.most = max(Self.most, Self.open)
        let data = request.url?.path.hasSuffix("getPlantData") == true ? Self.info
            : page.flatMap { Self.pages.indices.contains($0 - 1) ? Self.pages[$0 - 1] : nil } ?? Data()
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
            Self.lock.lock(); Self.open -= 1; Self.lock.unlock()
            if let url = request.url, let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
                client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// A POST's form: URLSession hands it to the protocol as a stream.
    private static func body(of request: URLRequest) -> String {
        if let d = request.httpBody { return String(decoding: d, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

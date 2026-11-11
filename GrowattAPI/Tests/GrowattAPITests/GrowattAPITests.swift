import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GrowattAPI

/// `GrowattAPI`'s parsing, on answers copied from the test server (test.growatt.com, 7 Nov 2026).
final class GrowattAPITests: XCTestCase {
    private let list = Data("""
    {"error_msg":"","data":{"plants":[{"total_energy":"0","plant_id":1913,"country":"China","latitude_f":null,"city":"",
    "image_url":null,"latitude":"32.5671257","current_power":"-1.0","locale":"en-US","peak_power":20000,"user_id":1704,
    "name":"Vi Station","create_date":"2026-09-09","status":4,"longitude":"-114.9943669"},
    {"total_energy":"12.5","plant_id":1917,"country":"Canada","city":"Calgary","latitude":"61.0666922","current_power":"3.2",
    "peak_power":0.800000011920929,"name":"Test","status":1,"longitude":"-107.991707"}],"count":2},"error_code":0}
    """.utf8)

    private let overview = Data("""
    {"error_msg":"","data":{"total_energy":"0","last_update_time":"2026-09-09 15:41:34","carbon_offset":"0","efficiency":"",
    "monthly_energy":"0","peak_power_actual":20000,"timezone":"GMT+8","current_power":0,"yearly_energy":"0","today_energy":"4.5"},
    "error_code":0}
    """.utf8)

    func testPlantList() throws {
        let plants = try GrowattAPI.parsePlants(list)
        XCTAssertEqual(plants.count, 2)
        XCTAssertEqual(plants[0].id, 1913)
        XCTAssertEqual(plants[0].name, "Vi Station")
        XCTAssertEqual(plants[0].peakPower, 20000)
        XCTAssertEqual(plants[0].currentPower, -1)
        XCTAssertEqual(plants[0].status, 4)
        XCTAssertEqual(plants[0].latitude ?? 0, 32.5671257, accuracy: 1e-9)
        XCTAssertEqual(plants[1].city, "Calgary")
        XCTAssertEqual(plants[1].totalEnergy, 12.5)
    }

    func testPlantData() throws {
        let d = try GrowattAPI.parseData(overview)
        XCTAssertEqual(d.todayEnergy, 4.5)
        XCTAssertEqual(d.currentPower, 0)
        XCTAssertEqual(d.lastUpdate, "2026-09-09 15:41:34")
    }

    /// `plant/power`: the day's readings in the guide's shape (W, the plant's clock); an empty power is unknown.
    private let power = Data("""
    {"error_msg":"","data":{"count":4,"powers":[{"time":"2026-11-08 06:00","power":0},{"time":"2026-11-08 06:05","power":"12.5"},
    {"time":"2026-11-08 06:10","power":null},{"time":"2026-11-08 06:15","power":"38200"},{"power":"1"}]},"error_code":0}
    """.utf8)

    private let devices = Data("""
    {"error_msg":"","data":{"count":3,"devices":[
    {"device_sn":"MAX0001","type":4,"manufacturer":"Growatt","model":"MAX 125KTL3-X LV","datalogger_sn":"XGD001","lost":false,"status":1,"last_update_time":"2026-11-08 14:55:10"},
    {"device_sn":"MAX0002","type":"4","model":"MAX 80KTL3 LV","datalogger_sn":"XGD001","lost":"true","status":"-1","last_update_time":"2026-11-08 09:50:00"},
    {"device_sn":"MTR0001","type":3,"model":"Smart meter","datalogger_sn":"XGD001","lost":false,"status":1},
    {"model":"no serial"}]},"error_code":0}
    """.utf8)

    private let energy = Data("""
    {"error_msg":"","data":{"count":3,"energys":[{"date":"2026-11-06","energy":"612.4"},{"date":"2026-11-07","energy":""},
    {"date":"2026-11-08","energy":330}]},"error_code":0}
    """.utf8)

    func testPlantDataCarriesTheZone() throws {
        XCTAssertEqual(try GrowattAPI.parseData(overview).timezone, "GMT+8")
    }

    func testPlantPower() throws {
        let p = try GrowattAPI.parsePower(power)
        // a row without a time is dropped; a null power is unknown, not 0
        XCTAssertEqual(p.count, 4)
        XCTAssertEqual(p[0].power, 0)
        XCTAssertEqual(p[1].power, 12.5)
        XCTAssertNil(p[2].power)
        XCTAssertEqual(p[3].power, 38200)
        XCTAssertEqual(p[3].time, "2026-11-08 06:15")
    }

    func testDeviceList() throws {
        let d = try GrowattAPI.parseDevices(devices)
        XCTAssertEqual(d.map(\.sn), ["MAX0001", "MAX0002", "MTR0001"])
        XCTAssertTrue(d[0].isInverter)
        XCTAssertTrue(d[0].isOnline)
        XCTAssertEqual(d[0].datalogger, "XGD001")
        // numbers and booleans as text
        XCTAssertEqual(d[1].type, 4)
        XCTAssertEqual(d[1].status, -1)
        XCTAssertEqual(d[1].lost, true)
        XCTAssertTrue(d[1].isLost)
        XCTAssertFalse(d[1].isOnline)
        // a meter isn't an inverter
        XCTAssertFalse(d[2].isInverter)
        XCTAssertFalse(GrowattAPI.Device(sn: "x", status: 3).isOnline)
        XCTAssertTrue(GrowattAPI.Device(sn: "x", status: 0).isOnline, "waiting at night is not a fault")
        XCTAssertTrue(GrowattAPI.Device(sn: "x").isInverter, "a type not given counts")
    }

    func testPlantEnergy() throws {
        let e = try GrowattAPI.parseEnergy(energy)
        XCTAssertEqual(e.count, 3)
        XCTAssertEqual(e[0].energy, 612.4)
        XCTAssertNil(e[1].energy)
        XCTAssertEqual(e[2].energy, 330)
    }

    func testNewCallsCarryTheirQueries() async throws {
        GrowattStub.replies = [power, devices, energy]
        let a = api()
        _ = try await a.power(plantID: 7, date: "2026-11-08")
        _ = try await a.devices(plantID: 7, perPage: 10)
        _ = try await a.energy(plantID: 7, start: "2026-11-01", end: "2026-11-07", unit: .day)
        let r = GrowattStub.requests
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0].url?.path, "/v1/plant/power")
        XCTAssertEqual(r[0].url?.query, "date=2026-11-08&plant_id=7")
        XCTAssertEqual(r[1].url?.path, "/v1/device/list")
        XCTAssertEqual(r[1].url?.query, "page=1&perpage=10&plant_id=7")
        XCTAssertEqual(r[2].url?.path, "/v1/plant/energy")
        XCTAssertEqual(r[2].url?.query, "end_date=2026-11-07&plant_id=7&start_date=2026-11-01&time_unit=day")
        XCTAssertEqual(r.map { $0.httpMethod ?? "GET" }, ["GET", "GET", "GET"], "every call reads")
    }

    func testErrorCodes() {
        let denied = Data(#"{"error_msg":"error_permission_denied","data":"","error_code":10011}"#.utf8)
        XCTAssertThrowsError(try GrowattAPI.parsePlants(denied)) { XCTAssertEqual($0 as? GrowattAPI.Failure, .api(10011, "error_permission_denied")) }
        XCTAssertThrowsError(try GrowattAPI.parseData(Data("not json".utf8))) { XCTAssertEqual($0 as? GrowattAPI.Failure, .badResponse) }
    }

    func testServers() {
        XCTAssertTrue(GrowattAPI.demo.isDemo)
        let live = GrowattAPI.live(token: " t0k3n ")
        XCTAssertFalse(live.isDemo)
        XCTAssertEqual(live.baseURL.absoluteString, "https://openapi.growatt.com/v1/")
        XCTAssertEqual(live.token, "t0k3n")
    }

    // MARK: calls, on a stubbed URLSession

    private func api() -> GrowattAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrowattStub.self]
        var a = GrowattAPI(baseURL: URL(string: "https://test.growatt.com/v1/")!, token: " abc \n")
        a.session = URLSession(configuration: config)
        a.retryDelay = 0.01
        return a
    }

    override func tearDown() {
        GrowattStub.reset()
        super.tearDown()
    }

    private let busy = Data(#"{"error_msg":"error_frequently_access","data":"","error_code":10012}"#.utf8)

    func testRequestCarriesTokenAndQuery() async throws {
        GrowattStub.replies = [list]
        let plants = try await api().plants(perPage: 500)
        XCTAssertEqual(plants.count, 2)
        let r = try XCTUnwrap(GrowattStub.requests.first)
        XCTAssertEqual(r.value(forHTTPHeaderField: "token"), "abc")
        XCTAssertEqual(r.url?.path, "/v1/plant/list")
        XCTAssertEqual(r.url?.query, "page=1&perpage=100")
    }

    func testTooFrequentIsRetried() async throws {
        GrowattStub.replies = [busy, busy, busy, overview]
        let d = try await api().data(plantID: 1913)
        XCTAssertEqual(d.todayEnergy, 4.5)
        XCTAssertEqual(GrowattStub.requests.count, 4)
        XCTAssertEqual(GrowattStub.requests.last?.url?.query, "plant_id=1913")
    }

    func testTooFrequentGivesUp() async {
        GrowattStub.replies = [busy, busy, busy, busy, overview]
        do {
            _ = try await api().data(plantID: 1913)
            XCTFail("should give up after 3 retries")
        } catch {
            XCTAssertEqual(error as? GrowattAPI.Failure, .tooFrequent)
        }
        XCTAssertEqual(GrowattStub.requests.count, 4)
    }
}

/// Answers each request with the next of `replies`, HTTP 200.
final class GrowattStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Data] = []
    nonisolated(unsafe) private static var seen: [URLRequest] = []
    nonisolated(unsafe) private static var sent: [String] = []
    nonisolated(unsafe) private static var fields: [String: String] = [:]
    nonisolated(unsafe) private static var codes: [Int] = []

    static var replies: [Data] {
        get { lock.lock(); defer { lock.unlock() }; return queue }
        set { lock.lock(); queue = newValue; lock.unlock() }
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    /// Each request's body as text ("" for a GET).
    static var bodies: [String] { lock.lock(); defer { lock.unlock() }; return sent }
    /// Header fields every reply carries (`Set-Cookie`, …).
    static var headers: [String: String] {
        get { lock.lock(); defer { lock.unlock() }; return fields }
        set { lock.lock(); fields = newValue; lock.unlock() }
    }
    /// HTTP statuses of the next replies, in order; 200 once they run out.
    static var statuses: [Int] {
        get { lock.lock(); defer { lock.unlock() }; return codes }
        set { lock.lock(); codes = newValue; lock.unlock() }
    }
    static func reset() { lock.lock(); queue = []; seen = []; sent = []; fields = [:]; codes = []; lock.unlock() }

    /// A session that answers through this stub.
    static func api() -> GrowattAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrowattStub.self]
        var a = GrowattAPI(baseURL: URL(string: "https://test.growatt.com/v1/")!, token: " abc \n")
        a.session = URLSession(configuration: config)
        a.retryDelay = 0.01
        return a
    }

    /// The body, which URLSession hands a protocol as a stream.
    private static func body(_ r: URLRequest) -> String {
        if let d = r.httpBody { return String(decoding: d, as: UTF8.self) }
        guard let s = r.httpBodyStream else { return "" }
        s.open(); defer { s.close() }
        var out = Data(), buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; out.append(buf, count: n) }
        return String(decoding: out, as: UTF8.self)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        Self.sent.append(Self.body(request))
        let data = Self.queue.isEmpty ? Data() : Self.queue.removeFirst()
        let headers = Self.fields
        let status = Self.codes.isEmpty ? 200 : Self.codes.removeFirst()
        Self.lock.unlock()
        if let url = request.url, let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) {
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

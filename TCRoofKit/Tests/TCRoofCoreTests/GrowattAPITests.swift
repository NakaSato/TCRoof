import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TCRoofCore

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

    func testErrorCodes() {
        let denied = Data(#"{"error_msg":"error_permission_denied","data":"","error_code":10011}"#.utf8)
        XCTAssertThrowsError(try GrowattAPI.parsePlants(denied)) { XCTAssertEqual($0 as? GrowattAPI.Failure, .api(10011, "error_permission_denied")) }
        XCTAssertThrowsError(try GrowattAPI.parseData(Data("not json".utf8))) { XCTAssertEqual($0 as? GrowattAPI.Failure, .badResponse) }
    }

    func testSummary() throws {
        let plants = try GrowattAPI.parsePlants(list)
        let never = GrowattAPI.summary(plants[0])
        XCTAssertEqual(never.id, "growatt-1913")
        XCTAssertEqual(never.status, .offline)
        XCTAssertEqual(never.kWp, 20000)
        XCTAssertFalse(never.reportsPR)
        // plant/data gives a plant that never reported power 0: it stays offline
        let stillNever = GrowattAPI.summary(plants[0], data: try GrowattAPI.parseData(overview))
        XCTAssertEqual(stillNever.status, .offline)
        XCTAssertEqual(stillNever.note, "Growatt | ไม่มีข้อมูล ตั้งแต่ 2026-09-09 15:41")

        let live = GrowattAPI.summary(plants[1], data: try GrowattAPI.parseData(overview))
        XCTAssertEqual(live.status, .normal)
        XCTAssertEqual(live.energy, 4.5)
        XCTAssertEqual(live.note, "Growatt | 0 kW")
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
private final class GrowattStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Data] = []
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static var replies: [Data] {
        get { lock.lock(); defer { lock.unlock() }; return queue }
        set { lock.lock(); queue = newValue; lock.unlock() }
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    static func reset() { lock.lock(); queue = []; seen = []; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        let data = Self.queue.isEmpty ? Data() : Self.queue.removeFirst()
        Self.lock.unlock()
        if let url = request.url, let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TCRoofCore

/// `FloodLookup.fetch` against a stubbed URLSession: requests, retries and error mapping, without the network.
final class FloodLookupStubTests: XCTestCase {
    private func lookup() -> FloodLookup {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        var l = FloodLookup(apiKey: " key-123 \n")
        l.session = URLSession(configuration: config)
        return l
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private static func body(plots: Int, place: [String: String] = [:]) -> Data {
        let features = place.isEmpty ? "[]" : #"[{"properties":\#(String(data: try! JSONSerialization.data(withJSONObject: place), encoding: .utf8)!)}]"#
        return Data(#"{"features":\#(features),"numberMatched":\#(plots),"numberReturned":1}"#.utf8)
    }

    func testFetchAsksEveryYearAndSortsTheAnswers() async throws {
        StubProtocol.handle { req, year, _ in
            let plots = year == 2011 ? 3 : year == 2017 ? 1 : 0
            let place = year == 2017 ? ["tb_tn": "ต.ยางซ้าย", "ap_tn": "อ.เมืองสุโขทัย", "pv_tn": "จ.สุโขทัย"] : [:]
            return .ok(Self.body(plots: plots, place: place))
        }
        let answered = Counter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let g = try await lookup().fetch(lat: 17.0062, lon: 99.8235, now: now) { answered.set($0) }

        XCTAssertEqual(g.years.map(\.year), Array(2554...2567))
        XCTAssertEqual(g.years.first { $0.year == 2554 }?.plots, 3)
        XCTAssertEqual(g.years.first { $0.year == 2560 }?.plots, 1)
        XCTAssertEqual(g.years.filter { $0.plots > 0 }.count, 2)
        XCTAssertEqual(g.place, "ต.ยางซ้าย อ.เมืองสุโขทัย จ.สุโขทัย")
        XCTAssertEqual(g.lat, 17.0062)
        XCTAssertEqual(g.lon, 99.8235)
        XCTAssertEqual(g.radiusMeters, 1000)
        XCTAssertEqual(g.fetchedAt, now)
        XCTAssertEqual(answered.value, FloodLookup.gregorianYears.count)

        let requests = StubProtocol.requests
        XCTAssertEqual(requests.count, FloodLookup.gregorianYears.count)
        let r = try XCTUnwrap(requests.first)
        XCTAssertEqual(r.value(forHTTPHeaderField: "API-Key"), "key-123", "the key is trimmed")
        XCTAssertEqual(r.url?.path, "/api/2.0/resources/features/flood-freq")
        let items = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "1")
        XCTAssertEqual(items.first { $0.name == "bbox" }?.value, FloodLookup.bbox(lat: 17.0062, lon: 99.8235, meters: 1000))
        XCTAssertEqual(items.filter { $0.name.hasPrefix("y_") }.map(\.value), ["1"])
    }

    func testGatewayErrorsAreRetried() async throws {
        // 2015 fails twice (504, then 502) before answering; every other year answers at once
        StubProtocol.handle { _, year, attempt in
            if year == 2015 && attempt == 1 { return .status(504) }
            if year == 2015 && attempt == 2 { return .status(502) }
            return .ok(Self.body(plots: year == 2015 ? 7 : 0))
        }
        let g = try await lookup().fetch(lat: 13.75, lon: 100.5, attempts: 3)
        XCTAssertEqual(g.years.first { $0.year == 2558 }?.plots, 7)
        XCTAssertEqual(StubProtocol.attempts(year: 2015), 3)
        XCTAssertEqual(StubProtocol.attempts(year: 2016), 1)
    }

    func testRetriesStopAfterTheLastAttempt() async {
        StubProtocol.handle { _, _, _ in .status(503) }
        do { _ = try await lookup().fetch(lat: 13.75, lon: 100.5, attempts: 2); XCTFail("expected a failure") }
        catch { XCTAssertEqual(error as? FloodLookup.Failure, .http(503)) }
        XCTAssertLessThanOrEqual(StubProtocol.attempts(year: 2011), 2)
    }

    func testOtherHTTPErrorsAreNotRetried() async {
        StubProtocol.handle { _, _, _ in .status(401) }
        do { _ = try await lookup().fetch(lat: 13.75, lon: 100.5, attempts: 3); XCTFail("expected a failure") }
        catch { XCTAssertEqual(error as? FloodLookup.Failure, .http(401)) }
        XCTAssertLessThanOrEqual(StubProtocol.attempts(year: 2011), 1)
    }

    func testNetworkErrorsMapToOfflineAndTimeout() async {
        StubProtocol.handle { _, _, _ in .error(URLError(.notConnectedToInternet)) }
        do { _ = try await lookup().fetch(lat: 13.75, lon: 100.5, attempts: 1); XCTFail("expected a failure") }
        catch { XCTAssertEqual(error as? FloodLookup.Failure, .offline) }

        StubProtocol.reset()
        StubProtocol.handle { _, _, _ in .error(URLError(.timedOut)) }
        do { _ = try await lookup().fetch(lat: 13.75, lon: 100.5, attempts: 1); XCTFail("expected a failure") }
        catch { XCTAssertEqual(error as? FloodLookup.Failure, .timeout) }
    }

    func testAnUnreadableAnswerFails() async {
        StubProtocol.handle { _, _, _ in .ok(Data("<html>gateway</html>".utf8)) }
        do { _ = try await lookup().fetch(lat: 13.75, lon: 100.5, attempts: 1); XCTFail("expected a failure") }
        catch { XCTAssertEqual(error as? FloodLookup.Failure, .badResponse) }
    }

    func testCoordinatesOutsideTheGlobeAreRejected() async {
        for (lat, lon) in [(91.0, 100.0), (13.0, -181.0)] {
            do { _ = try await lookup().fetch(lat: lat, lon: lon); XCTFail("expected a failure") }
            catch { XCTAssertEqual(error as? FloodLookup.Failure, .badCoordinates) }
        }
        XCTAssertTrue(StubProtocol.requests.isEmpty)
    }

    func testBoundingBoxIsASquareRoundThePoint() {
        // at the equator 1 km is 1/111.32 of a degree both ways
        XCTAssertEqual(FloodLookup.bbox(lat: 0, lon: 100, meters: 1000), "99.99102,-0.00898,100.00898,0.00898")
        // further north a degree of longitude is shorter, so the box is wider in degrees
        let parts = FloodLookup.bbox(lat: 60, lon: 10, meters: 1000).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(parts[2] - parts[0], 2 * (parts[3] - parts[1]), accuracy: 0.0001)
    }

    func testValuesAndMessages() {
        XCTAssertEqual(FloodLookup.int(4), 4)
        XCTAssertEqual(FloodLookup.int(2.6), 3)
        XCTAssertEqual(FloodLookup.int("12"), 12)
        XCTAssertNil(FloodLookup.int("x"))
        XCTAssertNil(FloodLookup.int(nil))
        XCTAssertEqual(FloodLookup.place(["tb_tn": "ต.ก", "ap_tn": "", "pv_tn": "จ.ข"]), "ต.ก จ.ข")
        XCTAssertEqual(FloodLookup.bundledKey, "", "the test bundle carries no key")
        let failures: [FloodLookup.Failure] = [.noKey, .badCoordinates, .offline, .timeout, .http(504), .badResponse]
        XCTAssertEqual(Set(failures.map(\.message)).count, failures.count)
        XCTAssertTrue(FloodLookup.Failure.http(504).message.contains("504"))
    }
}

/// Counts reported progress from the lookup's task group.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func set(_ v: Int) { lock.lock(); n = max(n, v); lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// Answers each request from a handler given the request, its `y_YYYY` year and the attempt number for that year.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply { case ok(Data), status(Int), error(URLError) }
    typealias Handler = @Sendable (URLRequest, Int, Int) -> Reply

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var seen: [URLRequest] = []
    nonisolated(unsafe) private static var tries: [Int: Int] = [:]

    static func handle(_ h: @escaping Handler) { lock.lock(); handler = h; lock.unlock() }
    static func reset() { lock.lock(); handler = nil; seen = []; tries = [:]; lock.unlock() }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    static func attempts(year: Int) -> Int { lock.lock(); defer { lock.unlock() }; return tries[year] ?? 0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let year = items.first { $0.name.hasPrefix("y_") }.flatMap { Int($0.name.dropFirst(2)) } ?? 0
        Self.lock.lock()
        Self.seen.append(request)
        Self.tries[year, default: 0] += 1
        let attempt = Self.tries[year] ?? 1
        let h = Self.handler
        Self.lock.unlock()

        switch h?(request, year, attempt) ?? .status(500) {
        case .ok(let data):
            respond(200)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .status(let code):
            respond(code)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        case .error(let e):
            client?.urlProtocol(self, didFailWithError: e)
        }
    }

    override func stopLoading() {}

    private func respond(_ code: Int) {
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
    }
}

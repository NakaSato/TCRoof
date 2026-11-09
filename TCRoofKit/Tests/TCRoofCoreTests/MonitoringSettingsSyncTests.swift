import XCTest
@testable import TCRoofCore

/// ตั้งค่า Monitoring shared by the team through `config/monitoring` (CHA-91): which copy wins, what a save sends,
/// and that each iPad keeps its own connection tests.
final class MonitoringSettingsSyncTests: XCTestCase {
    typealias Settings = Monitoring.Settings
    let server = UUID()

    private func paired(revision: Int = 0) -> Settings {
        var s = Settings(servers: [.init(id: server, name: "Growatt", url: "https://openapi.growatt.com/v1/", tokenSuffix: "3f2a")],
                         revision: revision)
        s.pair("job-12", plant: "1234", server: server)
        return s
    }

    func testASaveIsTheNextRevisionSignedByItsManager() {
        let current = paired(revision: 3)
        var edited = current
        edited.pollMinutes = 10
        let at = Date(timeIntervalSince1970: 1_800_000_000.7)
        let sent = edited.signed(after: current, by: "boss@tcroof.co", at: at)
        XCTAssertEqual(sent.revision, 4)
        XCTAssertEqual(sent.savedBy, "boss@tcroof.co")
        XCTAssertEqual(sent.savedAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(sent.pollMinutes, 10)
    }

    func testALaterOrSameRevisionReplacesTheLocalCopyButNeverAnOlderOne() {
        let local = paired(revision: 2)
        var later = local; later.revision = 3; later.rate = 4.5
        var same = local; same.rate = 3.9
        var older = local; older.revision = 1; older.rate = 5
        XCTAssertTrue(local.takes(later))
        // Firestore keeps one save per revision: at the same revision its copy is the team's
        XCTAssertTrue(local.takes(same))
        XCTAssertFalse(local.takes(older))
        // its own save coming back changes nothing
        XCTAssertFalse(local.takes(local))
    }

    func testEachIPadKeepsItsOwnConnectionTests() {
        var local = paired(revision: 1)
        local.servers[0].testOK = false
        local.servers[0].testedAt = Date(timeIntervalSince1970: 100)
        local.servers[0].plants = nil
        var remote = paired(revision: 2)
        remote.servers[0].testOK = true
        remote.servers[0].plants = 6
        remote.servers.append(.init(name: "บัญชีเฟส 3", url: "https://openapi.growatt.com/v1/", testOK: true))

        let kept = remote.keepingTests(of: local)
        XCTAssertEqual(kept.servers[0].testOK, false)
        XCTAssertEqual(kept.servers[0].testedAt, Date(timeIntervalSince1970: 100))
        XCTAssertNil(kept.servers[0].plants)
        // a server new to this iPad: never tested here
        XCTAssertNil(kept.servers[1].testOK)
        XCTAssertEqual(kept.pairings, remote.pairings)
        XCTAssertEqual(kept.revision, 2)
        // a copy differing only in another iPad's tests is not taken
        var onlyTests = local; onlyTests.servers[0].testOK = true
        XCTAssertFalse(local.takes(onlyTests))
    }

    func testOnlySettingsSetUpBeforeSyncGoUpOnce() {
        XCTAssertFalse(Settings().unsentSetup)
        XCTAssertTrue(paired().unsentSetup)
        XCTAssertFalse(paired(revision: 1).unsentSetup)
    }

    func testSettingsFromBeforeTheRevisionStillReadAndTheRevisionRoundTrips() throws {
        let old = Data(#"{"pollMinutes":10,"pairings":{"job-12":"1234"}}"#.utf8)
        let s = try JSONDecoder().decode(Settings.self, from: old)
        XCTAssertEqual(s.revision, 0)
        XCTAssertNil(s.savedBy)
        XCTAssertEqual(s.pairings["job-12"], "1234")
        XCTAssertTrue(s.unsentSetup)

        let sent = paired().signed(after: paired(revision: 4), by: "boss@tcroof.co", at: Date(timeIntervalSince1970: 1_800_000_000))
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(sent))
        XCTAssertEqual(back, sent)
    }
}

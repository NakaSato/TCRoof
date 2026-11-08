import Foundation
import Security
import SwiftData
import TCRoofCore

/// `Monitoring ทุกสถานี`'s data (issue #259): the settings, the stations and when they were last read. One store for
/// the page and the dock's badge.
///
/// For now the stations are the handed-over PWA stations, unpaired (their rows read `ไม่มีข้อมูล`), or with
/// `-monitoringDemo YES` the board's example fleet. Reading the paired plants from Growatt's OpenAPI every
/// `pollMinutes` is the next step; the settings, the token and the connection test are here already.
@MainActor @Observable
final class MonitoringStore {
    static let shared = MonitoringStore()

    private(set) var settings: Monitoring.Settings
    private(set) var stations: [Monitoring.Station] = []
    /// The clock the figures are worked out at: now, or the board's 14:55 in the demo.
    private(set) var now = Date()
    private(set) var refreshedAt: Date?

    private static let settingsKey = "monitoring.settings"

    private init() {
        settings = UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(Monitoring.Settings.self, from: $0) } ?? .init()
    }

    static var demo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "monitoringDemo")
        #else
        false
        #endif
    }

    var fleet: Monitoring.Fleet { Monitoring.Fleet(stations, now: now, settings: settings) }

    /// The dock's badge: the lines of `ต้องดำเนินการ`.
    var actionCount: Int { fleet.actions.count }

    /// Reads the stations again: the demo's, or the handed-over PWA stations (`jobs` from the page's query).
    func refresh(jobs: [Job]) {
        if Self.demo {
            now = Monitoring.demoNow()
            stations = Monitoring.demo(now: now)
        } else {
            now = Date()
            stations = Self.handedOver(jobs).map { job in
                Monitoring.Station.unpaired(id: job.syncID ?? job.code, mpNumber: job.mpNumber, name: job.stationName,
                                            kWp: job.capacityKW, inverters: Self.inverters(job))
            }
        }
        refreshedAt = Date()
    }

    /// PWA stations handed over (`ส่งมอบแล้ว`): the ones maintenance looks after.
    static func handedOver(_ jobs: [Job]) -> [Job] {
        jobs.pwaStations.filter { $0.status == .completed }
    }

    /// The station's inverters: its IEC test's, else one.
    private static func inverters(_ job: Job) -> Int { max(job.iecReport?.inverters.count ?? 1, 1) }

    func save(_ s: Monitoring.Settings) {
        settings = s
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: Self.settingsKey) }
    }

    // MARK: connection test

    /// Lists the token's plants on the server (read only, `plant/list`) and records the result on the server's row.
    func test(_ server: Monitoring.Settings.Server) async -> Result<Int, GrowattAPI.Failure> {
        guard let token = MonitoringToken.token(server.id), let url = URL(string: server.url) else {
            return .failure(.api(10011, "ไม่มี token"))
        }
        let result: Result<Int, GrowattAPI.Failure>
        do { result = .success(try await GrowattAPI(baseURL: url, token: token).plants().count) }
        catch let f as GrowattAPI.Failure { result = .failure(f) }
        catch { result = .failure(.badResponse) }
        var s = settings
        if let i = s.servers.firstIndex(where: { $0.id == server.id }) {
            s.servers[i].testedAt = Date()
            s.servers[i].testOK = (try? result.get()) != nil
            if case .success(let n) = result { s.servers[i].plants = n }
            save(s)
        }
        return result
    }
}

/// A monitoring server's token, kept in this device's Keychain (only the last four characters are in the settings). A
/// manager saves it on their iPad, as the assistant's key (`AssistantKey`); moving it to the backend is a later step.
enum MonitoringToken {
    private static let service = "com.tcroof.monitoring"

    static func token(_ server: UUID) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: server.uuidString, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String, for server: UUID) -> Bool {
        remove(server)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: server.uuidString, kSecValueData as String: Data(token.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ server: UUID) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: server.uuidString]
        SecItemDelete(q as CFDictionary)
    }
}

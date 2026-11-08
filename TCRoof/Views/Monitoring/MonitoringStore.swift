import Foundation
import Security
import SwiftData
import TCRoofCore

/// `Monitoring ทุกสถานี`'s data (issue #259): the settings, the stations and when they were last read. One store for
/// the page and the dock's badge.
///
/// The stations are the handed-over PWA stations, or with `-monitoringDemo YES` the board's example fleet. A station
/// paired with a Growatt plant (`Settings.pairings`) is read from Growatt's OpenAPI every `pollMinutes` while the page
/// shows (`poll`, `MonitoringFeed`); an unpaired one reads `ไม่มีข้อมูล`.
@MainActor @Observable
final class MonitoringStore {
    static let shared = MonitoringStore()

    private(set) var settings: Monitoring.Settings
    private(set) var stations: [Monitoring.Station] = []
    /// The clock the figures are worked out at: now, or the board's 14:55 in the demo.
    private(set) var now = Date()
    private(set) var refreshedAt: Date?
    /// Why the last poll couldn't read a station's plant (`ต่อ Growatt ไม่ได้`), nil when every paired station read.
    private(set) var feedFailure: String?
    @ObservationIgnored private let feed = MonitoringFeed()

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

    /// DEBUG: Growatt's web portal example plants in place of the stations (`-growattDemo YES`, or the PWA settings'
    /// `สถานีตัวอย่าง Growatt` switch, the same flag as the `บำรุงรักษา` overview's). `test` and `-growattToken` stay
    /// the overview's only: here a token goes in ตั้งค่า Monitoring and a station is paired with its plant.
    static var growattWebDemo: Bool {
        #if DEBUG
        let d = UserDefaults.standard
        let flag = (d.string(forKey: "growattDemo") ?? "").lowercased()
        let token = (d.string(forKey: "growattToken") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !demo && token.isEmpty && !["", "no", "0", "false", "test"].contains(flag)
        #else
        false
        #endif
    }

    /// The line under the page's header naming where the rows come from, nil for the stations' own.
    var sourceNote: String? { Self.growattWebDemo ? "สถานีตัวอย่างจากเว็บ Growatt" : nil }

    var fleet: Monitoring.Fleet { Monitoring.Fleet(stations, now: now, settings: settings) }

    /// The dock's badge: the stations in alarm or offline (`Fleet.needingAttention`), worked out when the stations or the
    /// settings change, not on each redraw of the dock.
    private(set) var attentionCount = 0

    private func recount() {
        let n = fleet.needingAttention
        if n != attentionCount { attentionCount = n }
    }

    /// Reads the stations again: the demo's, or the handed-over PWA stations (`jobs` from the page's query). A paired
    /// station keeps what Growatt last gave until the next `poll`.
    func refresh(jobs: [Job]) {
        if Self.demo {
            now = Monitoring.demoNow()
            stations = Monitoring.demo(now: now)
        } else if Self.growattWebDemo {
            // the example plants come with the next poll; keep the ones read
            if !stations.allSatisfy({ $0.id.hasPrefix(Monitoring.GrowattWebMap.stationID("")) }) { stations = [] }
            return recount()
        } else {
            now = Date()
            stations = Self.handedOver(jobs).map { job in
                let base = Self.base(job)
                guard settings.pairing(of: base.id) != nil, let last = stations.first(where: { $0.id == base.id }), last.paired else { return base }
                return last
            }
        }
        refreshedAt = Date()
        recount()
    }

    /// Reads every paired station's plant from Growatt (read only, one call after another, off the main actor) and fills
    /// its row. A station whose server has no token on this device, or whose read failed, keeps its last figures.
    func poll(jobs: [Job]) async {
        guard !Self.demo else { return refresh(jobs: jobs) }
        if Self.growattWebDemo { return await pollWebDemo() }
        let handed = Self.handedOver(jobs)
        var targets: [MonitoringFeed.Target] = []
        for job in handed {
            let id = Self.stationID(job)
            guard let p = settings.pairing(of: id), let url = URL(string: p.server.url),
                  let token = MonitoringToken.token(p.server.id) else { continue }
            targets.append(.init(stationID: id, api: GrowattAPI(baseURL: url, token: token), plantID: p.plantID,
                                 latitude: job.latitude, longitude: job.longitude))
        }
        guard !targets.isEmpty else { return refresh(jobs: jobs) }
        let readAt = Date()
        let readings = await feed.read(targets, now: readAt, calendar: .current)
        guard !Task.isCancelled else { return }
        let byID = Dictionary(readings.map { ($0.stationID, $0) }, uniquingKeysWith: { a, _ in a })
        let previous = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // what each station read as before this poll, for the alerts; a station never read since launch has none
        let before = previous.values.reduce(into: [String: Monitoring.Health]()) { out, s in
            if s.lastReading != nil { out[s.id] = s.health(now: readAt, offlineAfter: settings.loggerOfflineMinutes) }
        }
        now = readAt
        stations = handed.map { job in
            let base = Self.base(job)
            guard let r = byID[base.id] else { return previous[base.id].flatMap { $0.paired ? $0 : nil } ?? base }
            return Monitoring.GrowattMap.station(base, reading: r.reading, previous: previous[base.id], now: readAt,
                                                 offlineAfter: settings.loggerOfflineMinutes,
                                                 forecastDailyKWhPerKWp: r.forecastDailyKWhPerKWp,
                                                 belowExpectedPercent: settings.belowExpectedPercent)
        }
        feedFailure = readings.compactMap(\.failure).first?.message
        refreshedAt = Date()
        recount()
        // `ผู้รับแจ้งเตือน`'s maintenance team: this device is the team's (contractors don't read Growatt)
        if settings.notifyMaintenance {
            MonitoringNotification.plans(previous: before, stations: stations, now: readAt,
                                         offlineAfter: settings.loggerOfflineMinutes).forEach(NotificationService.shared.post)
        }
    }

    /// DEBUG `growattWebDemo`: every example plant read again (a guest session on the portal, read only), mapped as a
    /// paired station's. A plant whose figures fail keeps its last row; no alerts are posted for them.
    private func pollWebDemo() async {
        let readAt = Date()
        let result = await feed.readWebDemo()
        guard !Task.isCancelled, Self.growattWebDemo else { return }
        let previous = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        now = readAt
        stations = result.plants.compactMap { p in
            let id = Monitoring.GrowattWebMap.stationID(p.id)
            guard let plant = p.plant else { return previous[id] }
            return Monitoring.GrowattWebMap.station(plant, day: p.day, previous: previous[id], now: readAt,
                                                    offlineAfter: settings.loggerOfflineMinutes,
                                                    belowExpectedPercent: settings.belowExpectedPercent)
        }
        feedFailure = result.failure?.message
        refreshedAt = Date()
        recount()
    }

    private static func stationID(_ job: Job) -> String { job.syncID ?? job.code }

    private static func base(_ job: Job) -> Monitoring.Station {
        Monitoring.Station.unpaired(id: stationID(job), mpNumber: job.mpNumber, name: job.stationName,
                                    kWp: job.capacityKW, inverters: inverters(job))
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
        // the offline threshold is a setting
        recount()
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
/// Like that key it belongs to the device, shared by every account signed in there and kept through account switches.
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

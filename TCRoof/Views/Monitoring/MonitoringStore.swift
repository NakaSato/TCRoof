import Foundation
import Security
import SwiftData
import UIKit
import TCRoofCore

/// `Monitoring ทุกสถานี`'s data (issue #259): the settings, the stations and when they were last read. One store for
/// the page and the dock's badge.
///
/// The stations are the handed-over PWA stations, or with `-monitoringDemo YES` the board's example fleet. A station
/// paired with a Growatt plant (`Settings.pairings`) is read from Growatt's OpenAPI by this device every `pollMinutes`
/// while the Monitor tab is shown and it has the token (`poll`, `MonitoringFeed`); an unpaired one reads `ไม่มีข้อมูล`.
/// Each poll reads every station's summary; the history and the string currents only for the screen that shows them
/// (`overviewRange`, `focus`: CHA-107). Growatt's figures never go through Firebase: only the settings sync
/// (`config/monitoring`).
@MainActor @Observable
final class MonitoringStore {
    static let shared = MonitoringStore()

    private(set) var settings: Monitoring.Settings
    private(set) var stations: [Monitoring.Station] = []
    /// Bumped when a server's token is saved or removed in the Keychain, so `MonitoringPoller` reads again even when
    /// `settings` itself didn't change (for example, entering the token on a second iPad).
    private(set) var tokenRevision = 0
    /// The clock the figures are worked out at: now, or the board's 14:55 in the demo.
    private(set) var now = Date()
    private(set) var refreshedAt: Date?
    /// Why the last poll couldn't read a station's plant (`ต่อ Growatt ไม่ได้`), nil when every paired station read.
    private(set) var feedFailure: String?
    @ObservationIgnored private let feed = MonitoringFeed()

    /// The iPad overview's chart range: its history is read for every station (nil where no screen draws one, as on
    /// the iPhone). Set by `MonitoringPage`.
    var overviewRange: Monitoring.ChartRange?
    /// The station page shown and its chart's range: its string currents and history are read. Set by
    /// `StationMonitorPage`, nil when it closes.
    var focus: Focus?
    struct Focus: Hashable {
        var stationID: String
        var range: Monitoring.ChartRange
    }

    /// The last summary read, and the pairings and tokens it read with: a change reads again at once.
    @ObservationIgnored private var summaryRead: (at: Date, key: ReadKey)?
    /// When each station's string currents were last read.
    @ObservationIgnored private var stringsRead: [String: Date] = [:]
    private struct ReadKey: Equatable {
        var pairings: [String: String], pairingServers: [String: UUID], servers: [Monitoring.Settings.Server.ID: String]
        var tokenRevision: Int
    }
    private var readKey: ReadKey {
        ReadKey(pairings: settings.pairings, pairingServers: settings.pairingServers,
                servers: Dictionary(settings.servers.map { ($0.id, $0.url) }, uniquingKeysWith: { a, _ in a }),
                tokenRevision: tokenRevision)
    }

    /// The summary is due: never read, read with other pairings or tokens, or `pollInterval` ago (a second early, so a
    /// sleep that wakes just short of it still reads).
    private func summaryDue(at now: Date) -> Bool {
        guard let r = summaryRead, r.key == readKey else { return true }
        return now.timeIntervalSince(r.at) >= settings.pollInterval - 1
    }

    /// Seconds until the next summary is due, for `MonitoringPoller`'s sleep: leaving the tab and coming back, or
    /// changing a range, doesn't read the summary again before its time.
    var nextPollDelay: TimeInterval {
        guard let r = summaryRead, r.key == readKey else { return 1 }
        return max(settings.pollInterval - Date().timeIntervalSince(r.at), 1)
    }

    /// The first read since launch is under way and nothing has come back yet (CHA-74): the page shows skeletons in
    /// its shape instead of `—` and zeros. Only when there is something to read (a paired station with its token on
    /// this iPad, or the demo plants); later polls keep the last figures until the new ones come. DEBUG
    /// `-monitoringLoading YES` holds it on for screenshots.
    var awaitingFirstRead: Bool { readingFirst || Self.debugLoading }
    private var readingFirst = false
    @ObservationIgnored private var hasRead = false

    static var debugLoading: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "monitoringLoading")
        #else
        false
        #endif
    }

    private static let settingsKey = "monitoring.settings"
    /// Called with each manager's save here (not with copies received), for `CloudSync` to send to `config/monitoring`.
    @ObservationIgnored var onChange: ((Monitoring.Settings) -> Void)?

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

    var fleet: Monitoring.Fleet { Monitoring.Fleet(stations, now: now, settings: settings, raised: raised) }

    /// The app's own lines (`ผลิตต่ำกว่าที่คาด`, `สตริงกระแสต่ำ`, `PR ต่ำ`) as last raised, so each keeps its age and
    /// today's count from one reading to the next (`Monitoring.Raised`).
    private var raised: [String: Monitoring.Raised] = [:]

    /// The dock's badge: the stations in alarm or offline, or with a low string or PR (`Fleet.needingAttention`),
    /// worked out when the stations or the settings change, not on each redraw of the dock.
    private(set) var attentionCount = 0

    private func recount() {
        let f = fleet
        if f.raised != raised { raised = f.raised }
        let n = f.needingAttention
        if n != attentionCount { attentionCount = n }
    }

    /// Reads the stations again: the demo's, or the handed-over PWA stations (`jobs` from the page's query). A paired
    /// station keeps what Growatt last gave until the next `poll`.
    func refresh(jobs: [Job]) {
        if Self.demo {
            now = Monitoring.demoNow()
            stations = Monitoring.demo(now: now)
            if raised.isEmpty { raised = Monitoring.demoRaised(stations, now: now, settings: settings) }
        } else if Self.growattWebDemo {
            // the example plants come with the next poll; keep the ones read
            if !stations.allSatisfy({ $0.id.hasPrefix(Monitoring.GrowattWebMap.stationID("")) }) { stations = [] }
            return recount()
        } else {
            now = Date()
            sources = Self.handedOver(jobs).map { Source(base: Self.base($0), latitude: $0.latitude, longitude: $0.longitude) }
            stations = Self.handedOver(jobs).map { job in
                let base = Self.base(job)
                guard settings.pairing(of: base.id) != nil, let last = stations.first(where: { $0.id == base.id }), last.paired else { return base }
                return last
            }
        }
        refreshedAt = Date()
        recount()
    }

    /// Reads the paired stations from Growatt itself (read only, one call after another, off the main actor) when this
    /// device has the server's token: every station's summary when it is due, and what the shown screens need beyond
    /// it (`parts(for:summary:now:)`). A station not read, or whose read failed, keeps its last figures.
    func poll(jobs: [Job]) async {
        guard !Self.demo else { return refresh(jobs: jobs) }
        let readAt = Date()
        let summary = summaryDue(at: readAt)
        if Self.growattWebDemo {
            guard summary else { return }
            summaryRead = (readAt, readKey)
            return await pollWebDemo()
        }
        sources = Self.handedOver(jobs).map { Source(base: Self.base($0), latitude: $0.latitude, longitude: $0.longitude) }
        var targets: [MonitoringFeed.Target] = []
        for src in sources {
            guard let p = settings.pairing(of: src.base.id), let url = URL(string: p.server.url),
                  let token = MonitoringToken.token(p.server.id) else { continue }
            let parts = parts(for: src.base.id, summary: summary, now: readAt)
            guard !parts.isEmpty else { continue }
            targets.append(.init(stationID: src.base.id, api: GrowattAPI(baseURL: url, token: token), plantID: p.plantID,
                                 latitude: src.latitude, longitude: src.longitude, parts: parts))
        }
        let key = readKey
        guard !targets.isEmpty else {
            guard summary else { return }
            summaryRead = (readAt, key)
            refresh(jobs: jobs)
            feedFailure = nil
            return
        }
        if summary, !hasRead { readingFirst = true }
        let readings = await feed.read(targets, now: readAt, calendar: .current)
        // cancelled (the tab left): no skeleton left on; the next poll starts the wait again
        guard !Task.isCancelled else { readingFirst = false; return }
        for t in targets where t.parts.contains(.strings) { stringsRead[t.stationID] = readAt }
        guard !readings.isEmpty else { return }
        let all = Dictionary(readings.map { ($0.stationID, $0) }, uniquingKeysWith: { a, _ in a })
        if summary {
            summaryRead = (readAt, key)
            // a failed first read ends the wait too: the header says why (`feedFailure`)
            hasRead = true
            readingFirst = false
            apply(all, at: readAt, failure: .some(readings.compactMap(\.failure).first?.message))
        } else {
            // the history or the strings alone: the header's failure stays the summary's
            apply(all, at: readAt, failure: nil)
        }
    }

    /// A station's parts this poll: the summary when due, the overview chart's history, and for the station page shown
    /// its chart's history, this month's energy (its card) and the string currents (with each summary, else once
    /// `pollInterval` has passed). The feed skips history already read today.
    private func parts(for id: String, summary: Bool, now: Date) -> MonitoringFeed.Parts {
        var p: MonitoringFeed.Parts = summary ? .summary : []
        if let r = overviewRange { p.formUnion(.history(for: r)) }
        if let f = focus, f.stationID == id {
            p.formUnion(.history(for: f.range))
            p.insert(.months)
            let stale = stringsRead[id].map { now.timeIntervalSince($0) >= settings.pollInterval - 1 } ?? true
            if summary || stale { p.insert(.strings) }
        }
        return p
    }

    /// The handed-over stations as last listed by `poll`.
    private struct Source {
        var base: Monitoring.Station
        var latitude: Double?
        var longitude: Double?
    }
    @ObservationIgnored private var sources: [Source] = []

    /// The readings as the stations' rows; a station without one keeps its row. Alerts for what changed since.
    /// `failure` nil leaves the header's as it is (a read without the summary); `.some(nil)` clears it.
    private func apply(_ byID: [String: MonitoringFeed.Reading], at readAt: Date, failure: String??) {
        let previous = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // what each station read as before, for the alerts; a station never read since launch has none
        let before = previous.values.reduce(into: [String: Monitoring.Health]()) { out, s in
            if s.lastReading != nil { out[s.id] = s.health(now: readAt, offlineAfter: settings.loggerOfflineMinutes) }
        }
        now = readAt
        stations = sources.map { src in
            let base = src.base
            guard let r = byID[base.id] else { return previous[base.id].flatMap { $0.paired ? $0 : nil } ?? base }
            return Monitoring.GrowattMap.station(base, reading: r.reading, previous: previous[base.id], now: readAt,
                                                 offlineAfter: settings.loggerOfflineMinutes,
                                                 forecastDailyKWhPerKWp: r.forecastDailyKWhPerKWp)
        }
        if let failure { feedFailure = failure }
        refreshedAt = Date()
        recount()
        // `ผู้รับแจ้งเตือน`'s maintenance team: this device is the team's (contractors don't read Growatt). Only an
        // iPad posts them: a phone shows the readings and the badge, so someone with both isn't told twice (CHA-34)
        if settings.notifyMaintenance, Self.postsAlerts {
            MonitoringNotification.plans(previous: before, stations: stations, now: readAt,
                                         offlineAfter: settings.loggerOfflineMinutes).forEach(NotificationService.shared.post)
        }
    }

    /// DEBUG `growattWebDemo`: every example plant read again (a guest session on the portal, read only), mapped as a
    /// paired station's. A plant whose figures fail keeps its last row; no alerts are posted for them.
    private func pollWebDemo() async {
        let readAt = Date()
        if !hasRead { readingFirst = true }
        let result = await feed.readWebDemo()
        guard !Task.isCancelled, Self.growattWebDemo else { readingFirst = false; return }
        hasRead = true
        readingFirst = false
        let previous = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        now = readAt
        stations = result.plants.compactMap { p in
            let id = Monitoring.GrowattWebMap.stationID(p.id)
            guard let plant = p.plant else { return previous[id] }
            return Monitoring.GrowattWebMap.station(plant, day: p.day, previous: previous[id], now: readAt,
                                                    offlineAfter: settings.loggerOfflineMinutes)
        }
        feedFailure = result.failure?.message
        refreshedAt = Date()
        recount()
    }

    /// Whether this device posts the `ออฟไลน์` / `แจ้งเตือน` notifications: the iPad only.
    static var postsAlerts: Bool { UIDevice.current.userInterfaceIdiom == .pad }

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

    /// A manager's `บันทึก` in ตั้งค่า Monitoring: the next revision, signed with their email and sent to the team
    /// (CHA-91). Nothing is sent when only a token changed: a token stays on this device.
    func save(_ s: Monitoring.Settings) {
        guard s != settings else { return }
        let signed = s.signed(after: settings, by: MemberRole.shared.permissions.email)
        keep(signed)
        onChange?(signed)
    }

    /// The team's copy from Firestore: taken when it is this revision or later, with this iPad's connection tests.
    @discardableResult
    func receive(_ remote: Monitoring.Settings) -> Bool {
        guard settings.takes(remote) else { return false }
        keep(remote.keepingTests(of: settings))
        return true
    }

    /// Sends settings set up here before they synced, once Firestore is known to have none (`unsentSetup`).
    func sendUnsentSetup() {
        // a manager's only: the rules refuse anyone else's, and the revision would rise here for nothing
        guard settings.unsentSetup, MemberRole.shared.permissions.role.managesTeam else { return }
        let signed = settings.signed(after: settings, by: MemberRole.shared.permissions.email)
        keep(signed)
        onChange?(signed)
    }

    private func keep(_ s: Monitoring.Settings) {
        settings = s
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: Self.settingsKey) }
        // the offline threshold is a setting
        recount()
    }

    func noteTokenChange() {
        tokenRevision &+= 1
    }

    // MARK: connection test

    /// Lists the token's plants on the server (read only, `plant/list`, every page up to 10) and records the result on
    /// the server's row.
    func test(_ server: Monitoring.Settings.Server) async -> Result<[GrowattAPI.Plant], GrowattAPI.Failure> {
        guard let token = MonitoringToken.token(server.id), let url = URL(string: server.url) else {
            return .failure(.api(10011, "ไม่มี token"))
        }
        let result: Result<[GrowattAPI.Plant], GrowattAPI.Failure>
        do { result = .success(try await GrowattAPI(baseURL: url, token: token).allPlants(maxPages: 10)) }
        catch let f as GrowattAPI.Failure { result = .failure(f) }
        catch { result = .failure(.badResponse) }
        var s = settings
        if let i = s.servers.firstIndex(where: { $0.id == server.id }) {
            s.servers[i].testedAt = Date()
            s.servers[i].testOK = (try? result.get()) != nil
            if case .success(let list) = result { s.servers[i].plants = list.count }
            // a test is this iPad's (its token), so it stays here and isn't sent
            keep(s)
        }
        return result
    }
}

/// A monitoring server's token, kept in this device's Keychain (only the last four characters are in the settings) for
/// this iPad's own poll, and never sent anywhere. Like the assistant's key (`AssistantKey`)
/// it belongs to the device, shared by every account signed in there and kept through account switches.
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

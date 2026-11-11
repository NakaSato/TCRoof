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
        var tokenRevision: Int, plantsRevision: Int
    }
    private var readKey: ReadKey {
        ReadKey(pairings: settings.pairings, pairingServers: settings.pairingServers,
                servers: Dictionary(settings.servers.map { ($0.id, $0.url) }, uniquingKeysWith: { a, _ in a }),
                tokenRevision: tokenRevision, plantsRevision: plantsRevision)
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
        // the PWA settings' `สถานีตัวอย่าง Growatt` switch writes the device's defaults: follow it at once
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.followDemoSwitch() }
        }
    }

    /// `growattWebDemo` as last seen, so the pages and the poller follow the switch while they show (`followDemoSwitch`).
    private(set) var webDemoOn = MonitoringStore.growattWebDemo
    /// The jobs of the last `refresh` or `poll`, to rebuild the stations when the switch changes.
    @ObservationIgnored private var lastJobs: [Job] = []

    /// The example plants were switched on or off: drops what was read for the other side, so the stations are the
    /// example plants or the real ones at once, and the next poll (restarted by `MonitoringPoller`) reads them.
    func followDemoSwitch() {
        let on = Self.growattWebDemo
        guard on != webDemoOn else { return }
        webDemoOn = on
        stations = []
        sources = []
        raised = [:]
        stringsRead = [:]
        summaryRead = nil
        hasRead = false
        readingFirst = false
        feedFailure = nil
        refresh(jobs: lastJobs)
    }

    static var demo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "monitoringDemo")
        #else
        false
        #endif
    }

    /// DEBUG: Growatt's web portal example plants in place of the stations (`-growattDemo YES`, or the PWA settings'
    /// `สถานีตัวอย่าง Growatt` switch, the same flag as the `บำรุงรักษา` overview's). Off, the stations are the real
    /// ones: a token goes in ตั้งค่า Monitoring and a station is paired with its plant.
    static var growattWebDemo: Bool {
        #if DEBUG
        let flag = (UserDefaults.standard.string(forKey: "growattDemo") ?? "").lowercased()
        return !demo && !["", "no", "0", "false"].contains(flag)
        #else
        false
        #endif
    }

    /// A paired station read from Growatt, for the `บำรุงรักษา` overview and its station page; nil when the station
    /// isn't paired or hasn't been read since launch (Growatt is read only while Monitor shows, CHA-107), or with either
    /// demo on, whose stations are none of the jobs.
    func reading(of stationID: String) -> Monitoring.Station? {
        guard !Self.demo, !Self.growattWebDemo else { return nil }
        return stations.first { $0.id == stationID && $0.paired && $0.lastReading != nil }
    }

    /// The overview's row with its paired station's figures from Growatt (`MaintenanceStationSummary.monitored`).
    func maintenanceRow(_ row: MaintenanceStationSummary) -> MaintenanceStationSummary {
        guard let s = reading(of: row.id) else { return row }
        return row.monitored(by: s, now: now, offlineAfter: settings.loggerOfflineMinutes)
    }

    /// The station page of a paired station read from Growatt; nil for any other, which keeps its own page.
    func maintenanceDetail(_ row: MaintenanceStationSummary) -> MaintenanceStationDetail? {
        guard let s = reading(of: row.id) else { return nil }
        return .monitored(summary: row, station: s, now: now, offlineAfter: settings.loggerOfflineMinutes)
    }

    /// The line under the page's header naming where the rows come from, nil for the stations' own.
    var sourceNote: String? { webDemoOn ? "สถานีตัวอย่างจากเว็บ Growatt" : nil }

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
        lastJobs = jobs
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
            sources = allSources(jobs)
            let previous = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            stations = sources.map { src in
                guard src.plant != nil, let last = previous[src.base.id], last.paired else { return src.base }
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
        lastJobs = jobs
        let readAt = Date()
        let summary = summaryDue(at: readAt)
        if Self.growattWebDemo {
            guard summary else { return }
            return await pollWebDemo(key: readKey)
        }
        sources = allSources(jobs)
        var targets: [MonitoringFeed.Target] = []
        for src in sources {
            guard let p = src.plant, let url = URL(string: p.server.url),
                  let token = MonitoringToken.token(p.server.id) else { continue }
            let parts = parts(for: src.base.id, summary: summary, now: readAt)
            guard !parts.isEmpty else { continue }
            targets.append(.init(stationID: src.base.id, api: Self.api(url, token: token), plantID: p.plantID,
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
        // a few plants at a time, each batch shown as it comes: with the account's plants listed too, a whole poll
        // takes minutes (every call is spaced by `GrowattGate`); the paired stations come first
        var failure: String?
        var readAny = false
        for start in stride(from: 0, to: targets.count, by: Self.readBatch) {
            let batch = Array(targets[start..<min(start + Self.readBatch, targets.count)])
            let readings = await feed.read(batch, now: readAt, calendar: .current)
            // cancelled (the tab left): no skeleton left on; the next poll starts the wait again
            guard !Task.isCancelled else { readingFirst = false; return }
            for t in batch where t.parts.contains(.strings) { stringsRead[t.stationID] = readAt }
            guard !readings.isEmpty else { continue }
            readAny = true
            let all = Dictionary(readings.map { ($0.stationID, $0) }, uniquingKeysWith: { a, _ in a })
            if summary {
                failure = failure ?? readings.compactMap(\.failure).first?.message
                // a failed first read ends the wait too: the header says why (`feedFailure`)
                hasRead = true
                readingFirst = false
                apply(all, at: readAt, failure: .some(failure))
            } else {
                // the history or the strings alone: the header's failure stays the summary's
                apply(all, at: readAt, failure: nil)
            }
        }
        if summary, readAny { summaryRead = (readAt, key) }
    }

    /// Plants read before their rows are shown (`poll`).
    private static let readBatch = 5

    /// Every row: the handed-over PWA stations, then each account's plants that none of them is paired with
    /// (`plantLists`, from the account's last `ทดสอบ`), when this device has the account's token. Those are read as a
    /// paired station is, without being one; ตั้งค่า Monitoring's pairing lists only the stations.
    private func allSources(_ jobs: [Job]) -> [Source] {
        let handed = Self.handedOver(jobs).map { job -> Source in
            let base = Self.base(job)
            return Source(base: base, latitude: job.latitude, longitude: job.longitude, plant: settings.pairing(of: base.id))
        }
        let taken = Set(handed.compactMap { $0.plant.map { Self.accountPlantID($0.server.id, $0.plantID) } })
        var extra: [Source] = []
        for server in settings.servers where MonitoringToken.token(server.id) != nil {
            for p in plantLists[server.id] ?? [] {
                guard let plantID = Int(p.id) else { continue }
                let id = Self.accountPlantID(server.id, plantID)
                guard !taken.contains(id), !extra.contains(where: { $0.base.id == id }) else { continue }
                let base = Monitoring.Station.unpaired(id: id, mpNumber: nil, name: p.name, kWp: p.kWp, inverters: 1)
                extra.append(Source(base: base, latitude: nil, longitude: nil, plant: (server, plantID)))
            }
        }
        return handed + extra
    }

    private static let accountPlantPrefix = "growatt-plant-"

    /// An account's plant shown on its own (not a station's): `growatt-plant-<server>-<plant id>`.
    static func accountPlantID(_ server: UUID, _ plantID: Int) -> String {
        accountPlantPrefix + server.uuidString + "-" + String(plantID)
    }

    /// A row that is an account's plant, not a handed-over station: left out of the pairing and its counts.
    static func isAccountPlant(_ id: String) -> Bool { id.hasPrefix(accountPlantPrefix) }

    /// The handed-over stations only, for ตั้งค่า Monitoring's pairing and the `จับคู่แล้ว` counts.
    var jobStations: [Monitoring.Station] { stations.filter { !Self.isAccountPlant($0.id) } }

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

    /// The rows as last listed by `poll`: the handed-over stations and the accounts' plants (`allSources`).
    private struct Source {
        var base: Monitoring.Station
        var latitude: Double?
        var longitude: Double?
        /// What it is read from: a station's pairing, or the account's plant itself; nil for a station not paired.
        var plant: (server: Monitoring.Settings.Server, plantID: Int)?
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
            MonitoringNotification.plans(previous: before, stations: jobStations, now: readAt,
                                         offlineAfter: settings.loggerOfflineMinutes).forEach(NotificationService.shared.post)
        }
    }

    /// DEBUG `growattWebDemo`: every example plant read again (a guest session on the portal, read only), mapped as a
    /// paired station's. A plant whose figures fail keeps its last row; no alerts are posted for them.
    private func pollWebDemo(key: ReadKey) async {
        let readAt = Date()
        if !hasRead { readingFirst = true }
        let result = await feed.readWebDemo()
        // cancelled (the tab left, or the poller restarted as the page set its range): not marked read, so the next
        // poll reads at once rather than after `pollInterval`
        guard !Task.isCancelled, Self.growattWebDemo else { readingFirst = false; return }
        summaryRead = (readAt, key)
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

    // MARK: Growatt calls

    /// Every Growatt client of the app: paced by the shared `GrowattGate` (a call repeated within its window is refused
    /// before it's sent, calls on a token are spaced, a 10012 isn't retried).
    static func api(_ url: URL, token: String) -> GrowattAPI {
        var a = GrowattAPI(baseURL: url, token: token)
        a.gate = .shared
        return a
    }

    /// The plants each account last listed (`plant/list`, and the end users' picked in the pairing pane), kept on the
    /// device (`monitoring.plants`), so the pairing pane and a reopened dialog don't ask Growatt again: plants rarely
    /// change, and `ทดสอบ` reads them again.
    private(set) var plantLists: [UUID: [Monitoring.Pairing.Plant]] = MonitoringStore.loadPlants()

    private static let plantsKey = "monitoring.plants"

    private static func loadPlants() -> [UUID: [Monitoring.Pairing.Plant]] {
        guard let d = UserDefaults.standard.data(forKey: plantsKey),
              let raw = try? JSONDecoder().decode([String: [Monitoring.Pairing.Plant]].self, from: d) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    /// The last test's `plant/list` answer with its values hidden (`GrowattAPI.outline`), when it listed no plants.
    private(set) var answerOutline: [UUID: String] = [:]

    /// Keeps (or with nil forgets) an account's plants.
    func setPlants(_ list: [Monitoring.Pairing.Plant]?, for server: UUID) {
        guard plantLists[server] != list else { return }
        plantLists[server] = list
        let raw = Dictionary(uniqueKeysWithValues: plantLists.map { ($0.key.uuidString, $0.value) })
        if let d = try? JSONEncoder().encode(raw) { UserDefaults.standard.set(d, forKey: Self.plantsKey) }
        // the account's plants are rows of their own: list them now, and the poller reads them
        plantsRevision &+= 1
        if !Self.demo, !Self.growattWebDemo { refresh(jobs: lastJobs) }
    }

    /// Bumped when an account's plant list changes, so `MonitoringPoller` reads the new rows at once.
    private(set) var plantsRevision = 0

    // MARK: Growatt's wait (10012)

    /// When each account's `plant/list` may be called again after Growatt's 10012 (`GrowattGate`); none once passed.
    private(set) var retryAt: [UUID: Date] = [:]

    /// The account's wait as the gate has it now (a test, or the pairing pane's list, may have started one).
    func noteWait(_ server: UUID, token: String) async {
        let at = await GrowattGate.shared.freeAt(token: token, path: "plant/list")
        if retryAt[server] != at { retryAt[server] = at }
    }

    /// Forgets the waits that are over (the settings dialog calls it when the next one ends).
    func clearPastWaits(now: Date = Date()) {
        let left = retryAt.filter { $0.value > now }
        if left != retryAt { retryAt = left }
    }

    /// `เรียก Growatt ถี่เกินไป · ลองใหม่ได้เวลา 23:58`, or Growatt's plain message without a time.
    static func tooFrequentNote(until at: Date?) -> String {
        guard let at else { return GrowattAPI.Failure.tooFrequent.message }
        return "Growatt ให้รอ 5 นาทีหลังเรียกถี่เกินไป · ลองใหม่ได้เวลา " + MonFormat.time(at)
    }

    // MARK: connection test

    /// Lists the token's plants on the server (read only, `plant/list`, every page up to 10) and records the result on
    /// the server's row.
    func test(_ server: Monitoring.Settings.Server) async -> Result<[GrowattAPI.Plant], GrowattAPI.Failure> {
        guard let token = MonitoringToken.token(server.id), let url = URL(string: server.url) else {
            return .failure(.api(10011, "ไม่มี token"))
        }
        // Growatt answered 10012 to this account's `plant/list` lately: nothing is sent until its wait is over, since
        // each call into the wait starts it again
        if let at = await GrowattGate.shared.freeAt(token: token, path: "plant/list") {
            retryAt[server.id] = at
            return .failure(.tooFrequent)
        }
        let result: Result<[GrowattAPI.Plant], GrowattAPI.Failure>
        answerOutline[server.id] = nil
        do {
            let (list, first) = try await Self.api(url, token: token).allPlantsAnswer(maxPages: 10)
            // no plants: what Growatt sent, values hidden, so the cause can be told from the screen without another call
            if list.isEmpty { answerOutline[server.id] = GrowattAPI.outline(first) }
            result = .success(list)
        }
        catch let f as GrowattAPI.Failure { result = .failure(f) }
        catch { result = .failure(.badResponse) }
        await noteWait(server.id, token: token)
        var s = settings
        if let i = s.servers.firstIndex(where: { $0.id == server.id }) {
            s.servers[i].testedAt = Date()
            s.servers[i].testOK = (try? result.get()) != nil
            if case .success(let list) = result {
                s.servers[i].plants = list.count
                setPlants(list.map(Monitoring.Pairing.Plant.init), for: server.id)
            }
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

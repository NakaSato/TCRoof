import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `Monitoring ทุกสถานี` on iPad (issue #259, board `iPadPwaMonitoring`): the handed-over PWA stations' output from
/// Growatt, read only. The dock's `Monitor` tab. From the top: the since-installed strip, six figure cards, the total
/// power chart beside `ต้องดำเนินการ`, and the stations' table (or cards). A row opens the station's page.
/// `-monitoringDemo YES` shows the board's example fleet at its 14:55.
struct MonitoringPage: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State var store = MonitoringStore.shared
    @State var range: Monitoring.ChartRange = .today
    /// `แยกสถานี`, and the stations whose lines are hidden there.
    @State var split = false
    @State var hidden: Set<String> = []
    @State var filter: Monitoring.Filter = .all
    @State var sort: Monitoring.Sort = .loss
    @State var asCards = false
    @State var showSettings = MonitoringPage.debugSettings
    @State var opened: Monitoring.Station?
    @Environment(\.permissions) var permissions
    @Environment(\.isPresented) private var isPushed
    @Environment(\.dismiss) private var dismiss
    @Environment(SurveyModel.self) private var envSurvey: SurveyModel?
    /// iPad: the dock, whose `MonitoringPoller` reads Growatt; nil where the page is pushed on its own.
    @Environment(PadDock.self) private var dock: PadDock?
    var survey: SurveyModel { envSurvey ?? SurveyModel.shared }

    /// Leading and trailing margin, as the board's 1366 pt page.
    static let margin: CGFloat = 63

    var body: some View {
        let fleet = store.fleet
        ScrollView {
            Group {
                // the first Growatt read since launch: skeletons in the page's shape, never `—` and zeros (CHA-74)
                if store.awaitingFirstRead { loadingContent } else { content(fleet) }
            }
            .padding(.horizontal, Self.margin)
            .padding(.top, 14)
            .padding(.bottom, 116)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: jobs.map(\.persistentModelID)) { store.refresh(jobs: jobs) }
        // Growatt is read by the dock's `MonitoringPoller` while the app is open; off the dock (pushed elsewhere) here
        .background { if dock == nil { MonitoringPoller() } }
        .overlay {
            if showSettings {
                MonitoringSettingsDialog(store: store, stations: fleet.stations, canEdit: canEdit, startOnPairing: Self.debugPairing) { showSettings = false }
            }
        }
        .navigationDestination(item: $opened) { s in
            PWAMaintenanceStationView(station: Self.summary(s, health: s.health(now: store.now, offlineAfter: store.settings.loggerOfflineMinutes)))
        }
    }

    private func content(_ fleet: Monitoring.Fleet) -> some View {
        VStack(spacing: 14) {
            sinceStrip(fleet)
            kpiRow(fleet)
            HStack(alignment: .top, spacing: 14) {
                chartCard(fleet).frame(maxWidth: .infinity)
                actionsCard(fleet).frame(width: 398)
            }
            stationsCard(fleet)
        }
    }

    /// Managers edit the settings (issue #259 §7); everyone else sees them.
    var canEdit: Bool { permissions.role == .manager }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            if isPushed {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("กลับ")
            }
            Text("Monitoring ทุกสถานี").font(.sarabun(24, .bold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if let note = store.sourceNote {
                Text(note).font(.sarabunFixed(13, .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    .accessibilityIdentifier("monitoring.source")
            }
            Spacer(minLength: 12)
            if let failure = store.feedFailure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.sarabunFixed(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                    .accessibilityIdentifier("monitoring.feedFailure")
            }
            Button { showSettings = true } label: {
                Label("ตั้งค่า Monitoring", systemImage: "gearshape").font(.sarabun(15, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(.white.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("monitoring.settings")
        }
        .padding(.leading, isPushed ? 40 : Self.margin).padding(.trailing, Self.margin)
        .padding(.top, 10).padding(.bottom, 16)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    // MARK: since installed

    private func sinceStrip(_ f: Monitoring.Fleet) -> some View {
        let energy = MonFormat.energy(f.totalEnergy), value = MonFormat.baht(f.value)
        let rate = store.settings.rate.map { MonFormat.number($0, 2) + " ฿/kWh" } ?? "ยังไม่ตั้งอัตราค่าไฟ"
        return MonCard(padding: 0) {
            HStack(spacing: 0) {
                Text("ตั้งแต่ติดตั้ง").font(.sarabun(13, .bold)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 16)
                stripItem("พลังงานสะสม", energy.value, energy.unit)
                stripItem("กำลังติดตั้ง", MonFormat.number(f.kWp, 1), "kWp", note: "\(f.inverters) อินเวอร์เตอร์")
                stripItem("มูลค่าไฟที่ผลิตได้", value.value, value.unit + " · " + rate)
                stripItem("ลด CO₂", MonFormat.number(f.co2Tonnes), "t", last: true)
            }
            .frame(height: 52)
        }
        .accessibilityElement(children: .combine)
    }

    private func stripItem(_ title: String, _ value: String, _ unit: String, note: String? = nil, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabun(21, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
            Text(unit).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            if let note { Text(note).font(.sarabun(12)).foregroundStyle(Theme.inkMuted.opacity(0.8)).lineLimit(1) }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1, height: 26) }
    }

    // MARK: the six cards

    private func kpiRow(_ f: Monitoring.Fleet) -> some View {
        let chart = Monitoring.Chart(f.stations, range: .today, now: f.now)
        let week = Monitoring.Chart(f.stations, range: .week, now: f.now)
        return HStack(spacing: 12) {
            MonitoringKPI(icon: "bolt", tint: Theme.primary, title: "กำลังตอนนี้",
                          value: MonFormat.number(f.powerNow), unit: "kW",
                          chip: (MonFormat.percent(f.powerShare), .info), caption: "ของ " + MonFormat.number(f.kWp) + " kWp",
                          spark: .line(chart.total.compactMap(\.actual)))
            MonitoringKPI(icon: "sun.max", tint: Theme.warning, title: "พลังงานวันนี้",
                          value: MonFormat.number(f.energyToday), unit: "kWh",
                          chip: (MonFormat.percent(f.yieldShare) + " คาด", tone(share: f.yieldShare)),
                          caption: "คาด " + MonFormat.number(f.expectedSoFar) + " kWh",
                          spark: .bars(week.total.map { $0.actual ?? 0 }, highlightLast: true))
            MonitoringKPI(icon: "gauge.with.dots.needle.33percent", tint: Theme.primary, title: "ผลผลิตจำเพาะ",
                          value: MonFormat.number(f.specificYield, 2), unit: "kWh/kWp",
                          chip: (MonFormat.percent(f.specificVsMedian, signed: true), tone(delta: f.specificVsMedian)),
                          caption: "จากค่ากลาง " + MonFormat.number(f.medianYield, 2),
                          spark: .line(week.total.map { ($0.actual ?? 0) / max(f.kWp, 1) }))
            MonitoringKPI(icon: "arrow.down.right", tint: Theme.warning, title: "สูญเสียวันนี้",
                          value: MonFormat.number(f.lossToday), unit: "kWh", valueTint: (f.lossToday ?? 0) > 0 ? Theme.warningInk : nil,
                          chip: (MonFormat.percent(f.lossShare), (f.lossToday ?? 0) > 0 ? .warn : .ok),
                          caption: "ของที่คาด · \(f.lossStations) สถานี",
                          spark: .bars(week.total.map { $0.loss ?? 0 }, highlightLast: true))
            MonitoringKPI(icon: "cpu", tint: Theme.danger, title: "พร้อมใช้งาน",
                          value: MonFormat.number(f.availability.map { $0 * 100 }, 1), unit: "%",
                          valueTint: (f.availability ?? 1) < 1 ? Theme.dangerText : nil,
                          chip: ("\(f.invertersOnline)/\(f.inverters)", (f.availability ?? 1) < 1 ? .bad : .ok),
                          caption: f.inverters - f.invertersOnline > 0 ? "\(f.inverters - f.invertersOnline) เครื่องไม่ทำงาน" : "ทำงานครบ",
                          spark: .blocks(inverterBlocks(f)))
            MonitoringKPI(icon: "shield", tint: Theme.success, title: "ไหลย้อน",
                          value: MonFormat.number(f.backfeed), unit: "kWh",
                          chip: ("ปกติ \(f.backfeedClean)/\(f.stations.count)", f.backfeedClean == f.backfeedReporting ? .ok : .warn),
                          caption: backfeedCaption(f),
                          spark: .blocks(f.stations.map { $0.backfeedToday == nil ? .unknown : ($0.backfeedToday ?? 0) < 0.05 ? .on : .off }))
        }
    }

    private func backfeedCaption(_ f: Monitoring.Fleet) -> String {
        let missing = f.stations.count - f.backfeedReporting
        return missing > 0 ? "\(missing) สถานีไม่มีข้อมูล" : "ไม่มีไหลย้อน"
    }

    /// One block per inverter: working, down, or its station offline.
    private func inverterBlocks(_ f: Monitoring.Fleet) -> [MonitoringKPI.Block] {
        f.rows.flatMap { r -> [MonitoringKPI.Block] in
            let online = r.health == .offline ? 0 : (r.station.invertersOnline ?? r.station.inverters)
            return (0..<r.station.inverters).map { i in r.health == .offline ? .unknown : i < online ? .on : .off }
        }
    }

    func tone(share: Double?) -> MonTone {
        guard let s = share else { return .muted }
        return s * 100 >= Double(store.settings.belowExpectedPercent) ? .ok : .warn
    }

    func tone(delta: Double?) -> MonTone {
        guard let d = delta else { return .muted }
        return d >= -0.1 ? .ok : .warn
    }

    #if DEBUG
    static var debugSettings: Bool { UserDefaults.standard.bool(forKey: "monitoringSettings") || debugPairing }
    /// `-monitoringPairing YES`: the dialog open on `จับคู่สถานีกับ Plant`, with example plants.
    static var debugPairing: Bool { UserDefaults.standard.bool(forKey: "monitoringPairing") }
    #else
    static var debugSettings: Bool { false }
    static var debugPairing: Bool { false }
    #endif
}

/// Reads Growatt while the app is open, at once and then every `pollMinutes` (never closer than its 5 minutes), so the
/// dock's badge and the alerts follow the stations whichever tab shows (CHA-21). A new pairing or server reads again at
/// once. Draws nothing.
struct MonitoringPoller: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var store = MonitoringStore.shared

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: PollKey(minutes: store.settings.pollMinutes, pairings: store.settings.pairings,
                              servers: store.settings.servers.map(\.id))) {
                while !Task.isCancelled {
                    await store.poll(jobs: jobs)
                    try? await Task.sleep(for: .seconds(store.settings.pollInterval))
                }
            }
    }

    private struct PollKey: Equatable {
        var minutes: Int, pairings: [String: String], servers: [UUID]
    }
}

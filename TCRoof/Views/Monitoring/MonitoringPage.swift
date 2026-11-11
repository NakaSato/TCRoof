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
    /// The chart card's height: `ต้องดำเนินการ` keeps it and scrolls inside (CHA-110).
    @State var chartHeight: CGFloat = 0
    /// `ต้องดำเนินการ`'s rows and the room they have, to show `ดูทั้งหมด` when they don't fit.
    @State var actionsContent: CGFloat = 0
    @State var actionsViewport: CGFloat = 0
    /// `ดูทั้งหมด`: the table, filtered to `มีปัญหา`, scrolled to.
    @State var scrollToStations = 0
    @Environment(\.permissions) var permissions
    @Environment(\.isPresented) private var isPushed
    @Environment(\.dismiss) private var dismiss
    @Environment(SurveyModel.self) private var envSurvey: SurveyModel?
    /// iPad: the dock, whose tabs read Growatt while `Monitor` is shown (`MonitoringPoller`); nil where the page is
    /// pushed on its own.
    @Environment(PadDock.self) private var dock: PadDock?
    var survey: SurveyModel { envSurvey ?? SurveyModel.shared }

    /// Leading and trailing margin, as the board's 1366 pt page.
    static let margin: CGFloat = 63

    var body: some View {
        let fleet = store.fleet
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    // the first Growatt read since launch: skeletons in the page's shape, never `—` and zeros (CHA-74)
                    if store.awaitingFirstRead { loadingContent } else { content(fleet) }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, 14)
                .padding(.bottom, 116)
            }
            .onChange(of: scrollToStations) { withAnimation { proxy.scrollTo(Self.stationsAnchor, anchor: .top) } }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: jobs.map(\.persistentModelID)) { store.refresh(jobs: jobs) }
        // Growatt is read by `PadTabs`' `MonitoringPoller` while this tab is shown; off the dock (pushed elsewhere) here
        .background { if dock == nil { MonitoringPoller() } }
        // the chart's history is read for the range shown (CHA-107)
        .onChange(of: range, initial: true) { _, r in store.overviewRange = r }
        .overlay {
            if showSettings {
                MonitoringSettingsDialog(store: store, stations: store.jobStations, canEdit: canEdit, startOnPairing: Self.debugPairing) { showSettings = false }
            }
        }
        // one station's page (CHA-73); `-monitoringStation <mp>` opens it in DEBUG
        .navigationDestination(item: $opened) { s in StationMonitorPage(station: s) }
        .task(id: store.stations.count) { openDebugStation() }
    }

    private func content(_ fleet: Monitoring.Fleet) -> some View {
        VStack(spacing: 14) {
            sinceStrip(fleet)
            kpiRow(fleet)
            HStack(alignment: .top, spacing: 14) {
                chartCard(fleet).frame(maxWidth: .infinity)
                actionsCard(fleet).frame(width: 398)
            }
            stationsCard(fleet).id(Self.stationsAnchor)
        }
    }

    static let stationsAnchor = "monitoring.stationsAnchor"

    /// Managers and the Maintainer edit the settings (issue #259 §7), as `config/monitoring`'s rule allows; everyone
    /// else sees them.
    var canEdit: Bool { permissions.role.managesTeam }

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

    /// The value and its unit never shrink; only the grey note may be cut (CHA-110).
    private func sinceStrip(_ f: Monitoring.Fleet) -> some View {
        let energy = MonFormat.energy(f.totalEnergy), value = MonFormat.baht(f.value), size = MonFormat.capacity(f.kWp)
        let rate = store.settings.rate.map { "ที่ " + MonFormat.number($0, 2) + " ฿/kWh" } ?? "ยังไม่ตั้งอัตราค่าไฟ"
        return MonCard(padding: 0) {
            HStack(spacing: 0) {
                Text("ตั้งแต่ติดตั้ง").font(.sarabun(13, .bold)).foregroundStyle(Theme.inkMuted).fixedSize().padding(.horizontal, 16)
                stripItem("พลังงานสะสม", energy.value, energy.unit)
                stripItem("กำลังติดตั้ง", size.value, size.unit, note: "\(f.inverters) อินเวอร์เตอร์")
                stripItem("มูลค่าไฟที่ผลิตได้", value.value, value.unit, note: rate)
                stripItem("ลด CO₂", MonFormat.number(f.co2Tonnes), "t", last: true)
            }
            .frame(minHeight: 52)
        }
        .accessibilityElement(children: .combine)
    }

    private func stripItem(_ title: String, _ value: String, _ unit: String, note: String? = nil, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize()
            Text(value).font(.sarabun(21, .bold)).foregroundStyle(Theme.navy).monospacedDigit().lineLimit(1).fixedSize()
            Text(unit).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize()
            if let note {
                Text(note).font(.sarabun(12)).foregroundStyle(Theme.inkMuted.opacity(0.8)).lineLimit(1).truncationMode(.tail)
                    .layoutPriority(-1)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1, height: 26) }
    }

    // MARK: the six cards

    /// The six cards. At night they say so (CHA-110): `กลางคืน`, and before sunrise yesterday's figures under `—`,
    /// not zeros that read as a fault.
    private func kpiRow(_ f: Monitoring.Fleet) -> some View {
        let chart = Monitoring.Chart(f.stations, range: .today, now: f.now)
        let week = Monitoring.Chart(f.stations, range: .week, now: f.now)
        return HStack(spacing: 12) {
            powerKPI(f, chart)
            energyKPI(f, week)
            yieldKPI(f, week)
            lossKPI(f, week)
            availabilityKPI(f)
            MonitoringKPI(icon: "shield", tint: Theme.success, title: "ไหลย้อน",
                          value: MonFormat.number(f.backfeed), unit: "kWh",
                          chip: ("ปกติ \(f.backfeedClean)/\(f.stations.count)", f.backfeedClean == f.backfeedReporting ? .ok : .warn),
                          caption: backfeedCaption(f),
                          spark: .blocks(f.stations.map { $0.backfeedToday == nil ? .unknown : ($0.backfeedToday ?? 0) < 0.05 ? .on : .off }))
        }
    }

    private func powerKPI(_ f: Monitoring.Fleet, _ chart: Monitoring.Chart) -> some View {
        MonitoringKPI(icon: "bolt", tint: Theme.primary, title: "กำลังตอนนี้",
                      value: MonFormat.number(f.isNight && f.powerNow == nil && f.online > 0 ? 0 : f.powerNow), unit: "kW",
                      chip: f.isNight ? ("กลางคืน", .muted) : (MonFormat.percent(f.powerShare), .info),
                      caption: "ของ " + MonFormat.number(f.kWp) + " kWp",
                      spark: .line(chart.total.compactMap(\.actual)))
    }

    private func energyKPI(_ f: Monitoring.Fleet, _ week: Monitoring.Chart) -> some View {
        let night = f.isBeforeSunrise
        return MonitoringKPI(icon: "sun.max", tint: Theme.warning, title: "พลังงานวันนี้",
                             value: night ? "0" : MonFormat.number(f.energyToday), unit: "kWh",
                             chip: night ? ("ยังไม่เริ่ม", .muted) : (MonFormat.percent(f.yieldShare) + " คาด", tone(share: f.yieldShare)),
                             caption: night ? Self.yesterday(f.yesterdayEnergy) : "คาด " + MonFormat.number(f.expectedSoFar) + " kWh",
                             spark: .bars(week.total.map { $0.actual ?? 0 }, highlightLast: !night))
    }

    private func yieldKPI(_ f: Monitoring.Fleet, _ week: Monitoring.Chart) -> some View {
        let night = f.isBeforeSunrise
        return MonitoringKPI(icon: "gauge.with.dots.needle.33percent", tint: Theme.primary, title: "ผลผลิตจำเพาะ",
                             value: night ? MonFormat.dash : MonFormat.number(f.specificYield, 2), unit: "kWh/kWp",
                             chip: night ? ("กลางคืน", .muted) : (MonFormat.percent(f.specificVsMedian, signed: true), tone(delta: f.specificVsMedian)),
                             caption: night ? "เมื่อวาน " + MonFormat.number(f.yesterdaySpecificYield, 2)
                                 : "จากค่ากลาง " + MonFormat.number(f.medianYield, 2),
                             spark: .line(week.total.map { ($0.actual ?? 0) / max(f.kWp, 1) }))
    }

    private func lossKPI(_ f: Monitoring.Fleet, _ week: Monitoring.Chart) -> some View {
        let night = f.isBeforeSunrise, loss = f.lossToday ?? 0
        return MonitoringKPI(icon: "arrow.down.right", tint: Theme.warning, title: "สูญเสียวันนี้",
                             value: night ? MonFormat.dash : MonFormat.number(f.lossToday), unit: "kWh",
                             valueTint: !night && loss > 0 ? Theme.warningInk : nil,
                             chip: night ? ("กลางคืน", .muted) : (MonFormat.percent(f.lossShare), loss > 0 ? .warn : .ok),
                             caption: night ? "เมื่อวาน " + MonFormat.number(f.yesterdayLoss) + " kWh" : "ของที่คาด · \(f.lossStations) สถานี",
                             spark: .bars(week.total.map { $0.loss ?? 0 }, highlightLast: !night))
    }

    private func availabilityKPI(_ f: Monitoring.Fleet) -> some View {
        let down = f.inverters - f.invertersOnline, asleep = f.isNight ? f.invertersAsleep : 0
        let caption = asleep > 0 ? "พัก \(asleep) เครื่องไม่นับ" : down > 0 ? "\(down) เครื่องไม่ทำงาน" : "ทำงานครบ"
        return MonitoringKPI(icon: "cpu", tint: Theme.danger, title: "พร้อมใช้งาน",
                             value: MonFormat.number(f.availability.map { $0 * 100 }, 1), unit: "%",
                             valueTint: (f.availability ?? 1) < 1 ? Theme.dangerText : nil,
                             chip: ("\(f.invertersOnline)/\(f.inverters)", (f.availability ?? 1) < 1 ? .bad : .ok),
                             caption: caption,
                             spark: .blocks(inverterBlocks(f)))
    }

    /// `เมื่อวาน 12.4 MWh`.
    static func yesterday(_ kWh: Double?) -> String {
        let e = MonFormat.energy(kWh)
        return "เมื่อวาน " + e.value + " " + e.unit
    }

    private func backfeedCaption(_ f: Monitoring.Fleet) -> String {
        let missing = f.stations.count - f.backfeedReporting
        return missing > 0 ? "\(missing) สถานีไม่มีข้อมูล" : "ไม่มีไหลย้อน"
    }

    /// One block per inverter: working, down, or its station offline.
    private func inverterBlocks(_ f: Monitoring.Fleet) -> [MonitoringKPI.Block] {
        f.rows.flatMap { r -> [MonitoringKPI.Block] in
            let online = r.health == .offline ? 0 : (r.station.invertersOnline ?? r.station.inverters)
            let asleep = r.health == .offline ? 0 : (r.station.invertersAsleep ?? 0)
            return (0..<r.station.inverters).map { i in
                r.health == .offline || (i >= online && i < online + asleep) ? .unknown : i < online ? .on : .off
            }
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

/// Reads Growatt while it is shown: `PadTabs` and `PhoneTabs` put it in only while the Monitor tab is selected, so no
/// other tab calls Growatt and leaving the tab stops it (CHA-107). It polls once the summary is due (`pollMinutes`,
/// never closer than its 5 minutes, so coming back to the tab within them reads nothing) and sleeps until the next. A
/// new pairing, server or token reads at once, and a screen asking for more (`overviewRange`, `focus`) reads just
/// that. Draws nothing.
struct MonitoringPoller: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var store = MonitoringStore.shared

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: PollKey(minutes: store.settings.pollMinutes, pairings: store.settings.pairings,
                              pairingServers: store.settings.pairingServers,
                              servers: store.settings.servers.map(\.id), tokenRevision: store.tokenRevision,
                              overviewRange: store.overviewRange, focus: store.focus, webDemo: store.webDemoOn,
                              plants: store.plantsRevision)) {
                while !Task.isCancelled {
                    await store.poll(jobs: jobs)
                    try? await Task.sleep(for: .seconds(store.nextPollDelay))
                }
            }
    }

    private struct PollKey: Equatable {
        var minutes: Int, pairings: [String: String], pairingServers: [String: UUID], servers: [UUID], tokenRevision: Int
        var overviewRange: Monitoring.ChartRange?, focus: MonitoringStore.Focus?
        /// The example plants switched on or off: read the other side at once.
        var webDemo: Bool
        /// An account's plant list changed: its plants are rows to read.
        var plants: Int
    }
}

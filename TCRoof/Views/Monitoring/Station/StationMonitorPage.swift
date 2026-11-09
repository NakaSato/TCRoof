import SwiftUI
import TCRoofUI
import TCRoofCore

/// `Monitoring สถานี (เฉพาะโครงการ)` on iPad (CHA-73, board `iPadPwaStationMonitor`): one station's monitoring, pushed
/// from a row of `Monitoring ทุกสถานี`. The blue header with the station's health and a `สถานี` picker that switches
/// station in place, a capsule tab bar with badges, and the 7 tabs (one extension file each). Read only: nothing is
/// written to Growatt. The main dock stays under it.
///
/// What the page knows beyond the fleet's row is `Monitoring.StationDetail`: the demo's example (`-monitoringDemo YES`),
/// else only the row's (the inverters' count and states, the logger's last reading, the current alarms); the device
/// readings Growatt's device endpoints would give are not read yet, so those parts read `ไม่มีข้อมูล`.
struct StationMonitorPage: View {
    @State var store = MonitoringStore.shared
    @State var acks = StationAlarmAcks.shared
    @State var stationID: String
    /// The station as pushed, until the store lists it.
    let pushed: Monitoring.Station
    @State var tab: Monitoring.StationTab
    @State var range: Monitoring.ChartRange = .today
    @State var selectedInverter: String?
    @State var compare = Monitoring.CompareSelection()
    @State var compareDevice: String?
    @State var compareGroup: Monitoring.CompareGroup = .power
    @State var compareRange: CompareRange = .fiveMinutes
    @State var compareDaysBack = 0
    @State var compareNote: String?
    /// The first inverter's PAC has been put on the compare chart for this station.
    @State var compareSeeded = false
    @State var alarmPeriod: Monitoring.AlarmFilter.Period = .month
    @State var alarmDaysBack = 0
    @State var alarmDevice: Monitoring.AlarmFilter.Device = .all
    @State var alarmState: Monitoring.AlarmFilter.State = .all
    @State var selectedEvent: String?
    @State var maintenance: Monitoring.Station?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.permissions) var permissions
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    enum CompareRange: String, CaseIterable, Hashable { case fiveMinutes, daily, monthly, yearly }

    init(station: Monitoring.Station, tab: Monitoring.StationTab = .overview) {
        pushed = station
        _stationID = State(initialValue: station.id)
        _tab = State(initialValue: Self.debugTab ?? tab)
    }

    static let margin: CGFloat = 63

    var station: Monitoring.Station { store.stations.first { $0.id == stationID } ?? pushed }
    var now: Date { store.now }
    var health: Monitoring.Health { station.health(now: now, offlineAfter: store.settings.loggerOfflineMinutes) }
    var offline: Bool { health == .offline }
    var nowSlot: Int { Monitoring.Forecast.slot(of: now) }

    /// The demo's example, else what the row knows.
    func detail(_ s: Monitoring.Station) -> Monitoring.StationDetail {
        MonitoringStore.demo
            ? Monitoring.demoDetail(s, now: now, offlineAfter: store.settings.loggerOfflineMinutes)
            : Monitoring.StationDetail(station: s, health: health)
    }

    var body: some View {
        let s = station, d = detail(s)
        VStack(spacing: 0) {
            tabBar(s, d).padding(.horizontal, Self.margin).padding(.top, 12).padding(.bottom, 12)
            ScrollView {
                tabContent(s, d)
                    .padding(.horizontal, Self.margin)
                    .padding(.bottom, 116)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header(s) }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .padDock(fade: nil)
        .task(id: permissions.email) { acks.load(account: permissions.email, demo: MonitoringStore.demo) }
        .onChange(of: stationID) { _, _ in
            selectedInverter = nil; selectedEvent = nil; compareDevice = nil; compare = .init(); compareNote = nil
            compareSeeded = false
            alarmDevice = .all
        }
        .navigationDestination(item: $maintenance) { m in
            PWAMaintenanceStationView(station: MonitoringPage.summary(m, health: m.health(now: now, offlineAfter: store.settings.loggerOfflineMinutes)))
        }
        .accessibilityIdentifier("station.page")
    }

    @ViewBuilder private func tabContent(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        switch tab {
        case .overview: overviewTab(s, d)
        case .inverters: invertersTab(s, d)
        case .logger: loggerTab(s, d)
        case .meter: meterTab(s, d)
        case .weather: weatherTab(s, d)
        case .compare: compareTab(s, d)
        case .alarms: alarmsTab(s, d)
        }
    }

    // MARK: header

    private func header(_ s: Monitoring.Station) -> some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44).background(Theme.onPrimary.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("กลับ").accessibilityIdentifier("station.back")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(s.name).font(.sarabun(24, .bold)).foregroundStyle(Theme.onPrimary).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(health.title).font(.sarabun(13, .bold)).foregroundStyle(health.ink)
                        .padding(.horizontal, 9).frame(height: 24)
                        .background(Theme.surface, in: Capsule())
                        .accessibilityIdentifier("station.health")
                }
                Text(subtitle(s)).font(.sarabun(15)).foregroundStyle(Theme.onPrimary.opacity(0.9)).lineLimit(1)
            }
            Spacer(minLength: 12)
            stationPicker(s)
        }
        .padding(.leading, 40).padding(.trailing, Self.margin)
        .padding(.top, 10).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    /// `Monitoring · MP 25 · 220 kWp · อัปเดต 14:55`.
    private func subtitle(_ s: Monitoring.Station) -> String {
        ["Monitoring", s.mpNumber.map { "MP \($0)" }, MonFormat.number(s.kWp) + " kWp", timeLine(s)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// `อัปเดต 14:55`, `ข้อมูลล่าสุด 09:00` when offline, `ไม่มีข้อมูล` before any reading.
    func timeLine(_ s: Monitoring.Station) -> String {
        guard s.paired, let last = s.lastReading else { return "ไม่มีข้อมูล" }
        return (offline ? "ข้อมูลล่าสุด " : "อัปเดต ") + MonFormat.time(last)
    }

    private func stationPicker(_ s: Monitoring.Station) -> some View {
        HStack(spacing: 8) {
            Text("สถานี").font(.sarabun(15, .semibold)).foregroundStyle(Theme.onPrimary).padding(.leading, 12)
            Menu {
                Picker("สถานี", selection: $stationID) {
                    ForEach(store.stations) { st in Text(Self.pickerName(st)).tag(st.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(Self.pickerName(s)).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.navy)
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityIdentifier("station.picker")
        }
        .padding(3)
        .background(Theme.onPrimary.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.onPrimary.opacity(0.35)))
    }

    /// `MP 25 · นครชัยศรี`.
    static func pickerName(_ s: Monitoring.Station) -> String {
        [s.mpNumber.map { "MP \($0)" }, MonitoringPage.shortName(s)].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: tab bar

    private func tabBar(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(Monitoring.StationTab.allCases, id: \.self) { t in
                    tabButton(t, badge: Monitoring.badge(t, station: s, detail: d, health: health, acknowledged: acks.ids))
                }
            }
            .padding(3)
            .background(Theme.segmentTrack, in: Capsule())
            VStack(alignment: .leading, spacing: 0) {
                Text(s.paired ? "Growatt · ทุก \(store.settings.pollMinutes) นาที" : "ยังไม่จับคู่ Plant")
                Text(s.paired ? timeLine(s) : "ไม่มีข้อมูล")
            }
            .font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("station.source")
        }
    }

    private func tabButton(_ t: Monitoring.StationTab, badge: Monitoring.TabBadge?) -> some View {
        let on = t == tab
        return Button { tab = t } label: {
            HStack(spacing: 6) {
                Text(t.title).font(.sarabun(15, on ? .bold : .medium)).foregroundStyle(on ? Theme.navy : Theme.inkTab)
                    .lineLimit(1).fixedSize()
                if let badge {
                    Text(badge.text).font(.sarabun(12, .bold))
                        .foregroundStyle(badge.tone == .bad ? Theme.dangerText : Theme.inkMuted)
                        .padding(.horizontal, 6).frame(height: 20)
                        .background(badge.tone == .bad ? Theme.dangerSoft : Theme.track, in: Capsule())
                        .lineLimit(1).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background { if on { Capsule().fill(Theme.surface).shadow(color: Theme.navy.opacity(0.16), radius: 2, y: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.map { t.title + " | " + $0.text } ?? t.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("station.tab." + t.rawValue)
    }

    // MARK: shared parts

    /// A figure card: title, value with its unit, a caption.
    func figureCard(_ title: String, _ value: String, _ unit: String, caption: String, tint: Color = Theme.navy,
                    suffix: String? = nil) -> some View {
        MonCard(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).font(.sarabun(28, .bold)).foregroundStyle(tint).monospacedDigit().lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(unit).font(.sarabun(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    if let suffix { Text(suffix).font(.sarabun(14)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                }
                Text(caption).font(.sarabun(12)).foregroundStyle(Theme.inkMuted.opacity(0.85)).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    func cardTitle(_ title: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.sarabun(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            if let note { Text(note).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
        }
    }

    /// `ไม่มีข้อมูล` with why, in place of a part the source doesn't give.
    func emptyNote(_ title: String, _ detail: String, symbol: String = "chart.line.downtrend.xyaxis") -> some View {
        MonCard(padding: 28) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Theme.inkMuted)
                Text(title).font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                Text(detail).font(.sarabun(14)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    func statusChip(_ s: Monitoring.DeviceStatus) -> some View {
        MonChip(s.title, s == .normal ? .ok : s == .fault ? .bad : .muted)
    }

    func dot(_ s: Monitoring.DeviceStatus) -> some View {
        Circle().fill(s == .normal ? Theme.success : s == .fault ? Theme.danger : Theme.inkMuted.opacity(0.5))
            .frame(width: 9, height: 9)
    }

    /// `วันนี้ 14:55`, else `7 พ.ย. 14:55`.
    func dayTime(_ d: Date?) -> String {
        guard let d else { return MonFormat.dash }
        let day = Calendar.current.isDate(d, inSameDayAs: now) ? "วันนี้" : Self.thaiDay(d)
        return day + " " + MonFormat.time(d)
    }

    /// `7 พ.ย.`.
    static func thaiDay(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "th_TH")))
    }

    /// `8 พ.ย. 2569`.
    static func thaiDate(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "th_TH")))
    }

    // MARK: DEBUG

    #if DEBUG
    /// `-monitoringStationTab overview|inverters|logger|meter|weather|compare|alarms` (or `ov|inv|log|mt|wx|cmp|ev`).
    static var debugTab: Monitoring.StationTab? {
        UserDefaults.standard.string(forKey: "monitoringStationTab").flatMap(Monitoring.StationTab.init(flag:))
    }
    #else
    static var debugTab: Monitoring.StationTab? { nil }
    #endif
}

extension MonitoringPage {
    /// DEBUG `-monitoringStation <mp>`: pushes that station's page once the stations are read.
    func openDebugStation() {
        #if DEBUG
        guard !StationMonitorDebug.opened, opened == nil else { return }
        let mp = UserDefaults.standard.integer(forKey: "monitoringStation")
        guard mp > 0, let s = store.stations.first(where: { $0.mpNumber == mp }) else { return }
        StationMonitorDebug.opened = true
        opened = s
        #endif
    }
}

@MainActor enum StationMonitorDebug {
    static var opened = false
}

/// The alarms this account acknowledged (`รับทราบ`), kept in the device's defaults per account, like
/// `Monitoring.Settings`; the demo's stay in memory. Not synced: another device of the same account doesn't see them.
@MainActor @Observable
final class StationAlarmAcks {
    static let shared = StationAlarmAcks()

    private(set) var ids: Set<String> = []
    private var account = ""
    private var demo = false
    private var loaded = false

    private init() {}

    private var key: String { "monitoring.acks." + account }

    /// Once per account (and demo or not): the demo's start empty and stay in memory while the app runs.
    func load(account: String, demo: Bool) {
        guard !loaded || account != self.account || demo != self.demo else { return }
        loaded = true
        self.account = account
        self.demo = demo
        ids = demo ? [] : Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func acknowledge(_ new: [String]) {
        ids.formUnion(new)
        guard !demo else { return }
        UserDefaults.standard.set(Array(ids).sorted(), forKey: key)
    }
}

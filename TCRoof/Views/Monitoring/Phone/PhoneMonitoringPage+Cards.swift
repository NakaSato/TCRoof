import SwiftUI
import TCRoofUI
import TCRoofCore

// The iPhone Monitoring page's cards (docs/ui/iphone-monitor-entry §5): the summary, `ต้องดำเนินการ` and the stations.

extension PhoneMonitoringPage {
    // MARK: summary

    func summaryCard(_ f: Monitoring.Fleet) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    yieldRing(f.yieldShare)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("กำลังตอนนี้").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                            Text(MonFormat.number(f.powerNow)).font(.sarabun(17, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                            Text("kW").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                        }
                        Text("วันนี้ " + MonFormat.number(f.energyToday) + " / คาด " + MonFormat.number(f.expectedSoFar) + " kWh")
                            .font(.sarabun(13)).foregroundStyle(Theme.inkStrong).monospacedDigit()
                        if let loss = lossLine(f) {
                            Text(loss).font(.sarabun(13, .semibold)).foregroundStyle(Theme.warningInk).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    healthTile(.normal, f)
                    healthTile(.alarm, f)
                    healthTile(.offline, f)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monitoring.phone.summary")
    }

    /// Today's energy over what was expected so far; `—` inside when not known.
    @ViewBuilder private func yieldRing(_ share: Double?) -> some View {
        if let share {
            TCProgressRing(.percent(share), size: 64)
        } else {
            Circle().strokeBorder(Theme.track, lineWidth: 6).frame(width: 64, height: 64)
                .overlay(Text(MonFormat.dash).font(.sarabun(17, .bold)).foregroundStyle(Theme.inkMuted))
        }
    }

    /// `สูญเสียวันนี้ ~38 kWh · ≈ ฿159`; nil while the loss isn't known.
    private func lossLine(_ f: Monitoring.Fleet) -> String? {
        guard let loss = f.lossToday else { return nil }
        var line = "สูญเสียวันนี้ ~" + MonFormat.number(loss) + " kWh"
        if let rate = store.settings.rate, loss > 0 { line += " · ≈ ฿" + MonFormat.number(loss * rate) }
        return line
    }

    private func healthTile(_ h: Monitoring.Health, _ f: Monitoring.Fleet) -> some View {
        let n = f.rows.filter { $0.health == h }.count
        return VStack(spacing: 0) {
            Text("\(n)").font(.sarabun(20, .bold)).monospacedDigit()
            Text(h.title).font(.sarabun(12, .semibold))
        }
        .foregroundStyle(h.ink)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(h.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: ต้องดำเนินการ

    func actionsCard(_ f: Monitoring.Fleet) -> some View {
        let actions = f.actions
        return MonCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("ต้องดำเนินการ").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                    if !actions.isEmpty {
                        Text("\(actions.count)").font(.sarabun(13, .bold)).foregroundStyle(Theme.dangerText)
                            .frame(minWidth: 24, minHeight: 22).background(Theme.dangerSoft, in: Capsule())
                    }
                    Spacer()
                }
                .padding(16)
                if actions.isEmpty {
                    Divider()
                    Label("ทุกสถานีปกติ", systemImage: "checkmark.circle.fill")
                        .font(.sarabun(15, .semibold)).foregroundStyle(Theme.successInk)
                        .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    ForEach(actions.prefix(Self.actionsShown)) { a in
                        Divider()
                        PhoneMonitoringActionRow(action: a) { opened = a.station }
                    }
                    if actions.count > Self.actionsShown {
                        Divider()
                        Button { allActions = true } label: {
                            HStack(spacing: 4) {
                                Text("ดูทั้งหมด \(actions.count) รายการ")
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            }
                            .font(.sarabun(14, .semibold)).foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("monitoring.phone.allActions")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.actions")
    }

    // MARK: stations

    /// `มีปัญหา` until a filter is picked, or `ทั้งหมด` when nothing has a problem.
    func filter(_ f: Monitoring.Fleet) -> Monitoring.Filter {
        picked ?? (f.count(.problem) > 0 ? .problem : .all)
    }

    private static let filters: [Monitoring.Filter] = [.problem, .offline, .all]

    func stationsCard(_ f: Monitoring.Fleet) -> some View {
        let current = filter(f)
        let rows = f.rows(current, sort: sort)
        let selection = Binding<Int>(
            get: { Self.filters.firstIndex(of: current) ?? 0 },
            set: { picked = Self.filters[$0] })
        return MonCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("สถานี").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                    Spacer()
                    sortMenu
                }
                .padding(.horizontal, 16).padding(.top, 12)
                TCCountSegments(Self.filters.map { flt in
                    TCCountSegments.Segment(MonitoringPage.filterTitle(flt), count: f.count(flt),
                                            alert: flt != .all && f.count(flt) > 0, unit: "สถานี")
                }, selection: selection)
                .padding(.horizontal, 16).padding(.vertical, 10)
                ForEach(rows) { r in
                    Divider()
                    stationRow(r)
                }
                if rows.isEmpty {
                    Divider()
                    Text("ไม่มีสถานีในตัวกรองนี้").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.stations")
    }

    private var sortMenu: some View {
        Menu {
            Picker("เรียง", selection: $sort) {
                Text("สูญเสีย").tag(Monitoring.Sort.loss)
                Text("kWh/kWp").tag(Monitoring.Sort.specificYield)
                Text("MP").tag(Monitoring.Sort.mp)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .semibold))
                Text("เรียง: " + Self.sortTitle(sort))
            }
            .font(.sarabun(14, .semibold)).foregroundStyle(Theme.primary)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("monitoring.phone.sort")
    }

    static func sortTitle(_ s: Monitoring.Sort) -> String {
        switch s {
        case .loss: "สูญเสีย"
        case .specificYield: "kWh/kWp"
        case .mp: "MP"
        }
    }

    private func stationRow(_ r: Monitoring.Row) -> some View {
        let s = r.station
        return Button { opened = s } label: {
            HStack(spacing: 10) {
                if let mp = s.mpNumber {
                    Text("MP \(mp)").font(.sarabun(12, .bold)).foregroundStyle(Theme.navy)
                        .padding(.horizontal, 6).frame(height: 22)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(rowFigures(s)).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).monospacedDigit()
                }
                Spacer(minLength: 6)
                if s.paired {
                    MonChip(r.health.title, r.health == .normal ? .ok : r.health == .alarm ? .bad : .muted)
                } else {
                    MonChip("ไม่มีข้อมูล", .muted)
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(minHeight: 60)
            .overlay(alignment: .leading) { Rectangle().fill(r.health.bar).frame(width: 3).padding(.vertical, 8) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monitoring.row.\(s.id)")
    }

    /// `120 kWp · 82.4 kW · 3.21 kWh/kWp`.
    private func rowFigures(_ s: Monitoring.Station) -> String {
        [MonFormat.number(s.kWp) + " kWp", MonFormat.number(s.powerNow, 1) + " kW",
         MonFormat.number(s.specificYield, 2) + " kWh/kWp"].joined(separator: " · ")
    }
}

/// One line of `ต้องดำเนินการ` on iPhone: the station, its status (`TCRoof ตรวจพบ`, `Error 102`, `ขาดการติดต่อ`), what
/// and since when (`Action.summary`), and on the right the loss.
struct PhoneMonitoringActionRow: View {
    let action: Monitoring.Action
    let open: () -> Void

    var body: some View {
        let alarm = action.alarm
        let bar: Color = alarm.source == .tcroof ? Theme.warning : Theme.danger
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    MonChip(action.status, alarm.source == .tcroof ? .warn : .bad)
                    Text(action.summary(now: Date())).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(loss).font(.sarabun(15, .bold)).foregroundStyle(Theme.warningInk).lineLimit(1).monospacedDigit()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 56)
            .overlay(alignment: .leading) { Rectangle().fill(bar).frame(width: 4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// `MP 25 · นครชัยศรี`, `P1_3 · บ้านโป่ง`.
    private var title: String { MonitoringPage.title(action.station, separator: " · ") }

    /// `~4.2 kWh`, `≤ 430 kWh`, or `—`.
    private var loss: String {
        switch action.alarm.loss {
        case .measured(let v), .about(let v): "~" + MonFormat.number(v, v < 10 ? 1 : 0) + " kWh"
        case .atMost(let v): "≤ " + MonFormat.number(v) + " kWh"
        case .unknown: MonFormat.dash
        }
    }
}

/// `ดูทั้งหมด`: every line of `ต้องดำเนินการ`, the costliest first. A line opens its station's maintenance page.
struct PhoneMonitoringActionsPage: View {
    @State private var store = MonitoringStore.shared
    @State private var opened: Monitoring.Station?

    var body: some View {
        let fleet = store.fleet
        let actions = fleet.actions
        ScrollView {
            MonCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { Divider() }
                        PhoneMonitoringActionRow(action: a) { opened = a.station }
                    }
                    if actions.isEmpty {
                        Label("ทุกสถานีปกติ", systemImage: "checkmark.circle.fill")
                            .font(.sarabun(15, .semibold)).foregroundStyle(Theme.successInk)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .navigationTitle("ต้องดำเนินการ \(actions.count)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { s in PhoneMonitoringPage.station(s, fleet: fleet, store: store) }
    }
}

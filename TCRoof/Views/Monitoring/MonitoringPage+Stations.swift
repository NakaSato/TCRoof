import SwiftUI
import TCRoofUI
import TCRoofCore

// `สถานี` (issue #259 §6): filters with their counts, the sort, table or cards, a totals row; a row opens the
// station's page.

extension MonitoringPage {
    /// The table's columns, in points (the board's 1240 pt card).
    enum Col {
        static let station: CGFloat = 230, status: CGFloat = 96, power: CGFloat = 130, energy: CGFloat = 200
        static let yield: CGFloat = 110, loss: CGFloat = 100, inverters: CGFloat = 110, data: CGFloat = 90
    }

    func stationsCard(_ f: Monitoring.Fleet) -> some View {
        let rows = f.rows(filter, sort: sort)
        return MonCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                stationsBar(f).padding(16)
                if asCards {
                    cardsGrid(rows).padding([.horizontal, .bottom], 16)
                } else {
                    tableHeader
                    ForEach(rows) { r in
                        Divider()
                        tableRow(r, night: Night(f))
                    }
                    if rows.isEmpty {
                        Divider()
                        Text(f.rows.isEmpty ? "ยังไม่มีสถานีที่ส่งมอบแล้ว" : "ไม่มีสถานีในตัวกรองนี้")
                            .font(.sarabun(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 88)
                    }
                    Divider()
                    totalsRow(f)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.stations")
    }

    private func stationsBar(_ f: Monitoring.Fleet) -> some View {
        HStack(spacing: 12) {
            Text("สถานี").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
            MonSwitch(options: Monitoring.Filter.allCases.map { ($0, Self.filterTitle($0) + " \(f.count($0))") }, selection: $filter)
            Spacer(minLength: 8)
            Text("เรียงตาม").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            MonSwitch(options: [(.loss, "สูญเสียมากสุด"), (.specificYield, "kWh/kWp ต่ำสุด"), (.mp, "MP")], selection: $sort)
            MonSwitch(options: [(false, "ตาราง"), (true, "การ์ด")], selection: $asCards)
        }
    }

    static func filterTitle(_ f: Monitoring.Filter) -> String {
        switch f {
        case .all: "ทั้งหมด"
        case .problem: "มีปัญหา"
        case .offline: "ออฟไลน์"
        }
    }

    // MARK: table

    var tableHeader: some View {
        HStack(spacing: 0) {
            head("สถานี", Col.station)
            head("สถานะ", Col.status)
            head("กำลังตอนนี้", Col.power)
            head("พลังงานวันนี้ / คาด", Col.energy)
            head("kWh/kWp", Col.yield, trailing: true)
            head("สูญเสีย", Col.loss, trailing: true)
            head("อินเวอร์เตอร์", Col.inverters)
            head("ข้อมูล", Col.data)
            Text("แจ้งเตือน").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.sarabun(12, .semibold)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 16).frame(height: 34)
        .background(Theme.phonePage)
    }

    private func head(_ t: String, _ w: CGFloat, trailing: Bool = false) -> some View {
        Text(t).lineLimit(1).frame(width: w, alignment: trailing ? .trailing : .leading).padding(.trailing, trailing ? 12 : 0)
    }

    /// At night the row reads as night (CHA-110): `0 kW · กลางคืน`, `0 / — kWh` and `กลางคืน` before sunrise.
    struct Night {
        var on: Bool
        var beforeSunrise: Bool
        init(_ f: Monitoring.Fleet) { on = f.isNight; beforeSunrise = f.isBeforeSunrise }
    }

    private func tableRow(_ r: Monitoring.Row, night: Night) -> some View {
        let s = r.station
        return Button { opened = s } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text([s.mpNumber.map { "MP \($0)" }, MonFormat.number(s.kWp) + " kWp"].compactMap { $0 }.joined(separator: " · "))
                        .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                }
                .frame(width: Col.station, alignment: .leading)
                MonChip(r.health.title, r.health == .normal ? .ok : r.health == .alarm ? .bad : .muted)
                    .frame(width: Col.status, alignment: .leading)
                powerCell(r, night: night).frame(width: Col.power, alignment: .leading)
                energyCell(r, night: night).frame(width: Col.energy, alignment: .leading).padding(.trailing, 12)
                yieldCell(r, night: night).frame(width: Col.yield, alignment: .trailing).padding(.trailing, 12)
                Text(r.loss.map(Self.rowLoss) ?? MonFormat.dash)
                    .font(.sarabun(14, .bold)).foregroundStyle(r.loss == nil ? Theme.inkMuted : Theme.warningInk)
                    .frame(width: Col.loss, alignment: .trailing).padding(.trailing, 12)
                invertersCell(r).frame(width: Col.inverters, alignment: .leading)
                dataCell(r).frame(width: Col.data, alignment: .leading)
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if s.alarms.isEmpty {
                        Text(MonFormat.dash).foregroundStyle(Theme.inkMuted)
                    } else {
                        Text("\(s.alarms.count)").font(.sarabun(12, .bold)).foregroundStyle(Theme.dangerText)
                            .frame(width: 24, height: 24).background(Theme.dangerSoft, in: Circle())
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
            .overlay(alignment: .leading) { Rectangle().fill(r.health.bar).frame(width: 3).padding(.vertical, 8) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monitoring.row.\(s.id)")
    }

    static func rowLoss(_ l: Monitoring.Alarm.Loss) -> String {
        switch l {
        case .atMost(let v): "≤ " + MonFormat.number(v) + " kWh"
        case .about(let v): "≈ " + MonFormat.number(v) + " kWh"
        case .measured(let v): MonFormat.number(v) + " kWh"
        case .unknown: MonFormat.dash
        }
    }

    private func powerCell(_ r: Monitoring.Row, night: Night) -> some View {
        let s = r.station
        return VStack(alignment: .leading, spacing: 3) {
            if night.on, r.health != .offline, (s.powerNow ?? 0) < 0.05 {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("0").font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                    Text("kW · กลางคืน").font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                }
                bar(0, Theme.primary)
            } else if let p = s.powerNow {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(MonFormat.number(p, 1)).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                    Text("kW · " + MonFormat.percent(s.powerShare)).font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                }
                bar(s.powerShare ?? 0, Theme.primary)
            } else {
                Text("— ไม่มีข้อมูล").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.trailing, 14)
    }

    @ViewBuilder private func energyCell(_ r: Monitoring.Row, night: Night) -> some View {
        if night.beforeSunrise, r.health != .offline {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("0").font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                    Text("/ " + MonFormat.dash + " kWh").font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                }
                bar(0, Theme.success)
            }
        } else {
            dayEnergyCell(r.station)
        }
    }

    private func dayEnergyCell(_ s: Monitoring.Station) -> some View {
        let share = s.yieldShare
        let color: Color = (share ?? 1) * 100 < Double(store.settings.belowExpectedPercent) ? Theme.warning : Theme.success
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(MonFormat.number(s.energyToday)).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                Text("/ " + MonFormat.number(s.expectedSoFar) + " kWh").font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 4)
                Text(MonFormat.percent(share)).font(.sarabun(12, .bold)).foregroundStyle(share == nil ? Theme.inkMuted : color == Theme.warning ? Theme.warningInk : Theme.successInk)
            }
            bar(share ?? 0, color)
        }
    }

    private func yieldCell(_ r: Monitoring.Row, night: Night) -> some View {
        let offline = r.health == .offline
        return VStack(alignment: .trailing, spacing: 1) {
            if night.beforeSunrise, !offline {
                Text("กลางคืน").font(.sarabun(13, .semibold)).foregroundStyle(Theme.inkMuted)
            } else {
                yieldFigures(r, offline: offline)
            }
        }
    }

    @ViewBuilder private func yieldFigures(_ r: Monitoring.Row, offline: Bool) -> some View {
            Text(offline ? MonFormat.dash : MonFormat.number(r.station.specificYield, 2)).font(.sarabun(14, .bold))
                .foregroundStyle((r.yieldVsMedian ?? 0) < -0.1 ? Theme.dangerText : Theme.navy)
            Text(r.yieldVsMedian.map { MonFormat.percent($0, signed: true) + " จากค่ากลาง" } ?? "ไม่มีข้อมูล")
                .font(.sarabun(10)).foregroundStyle(Theme.inkMuted).lineLimit(1)
    }

    private func invertersCell(_ r: Monitoring.Row) -> some View {
        let s = r.station
        let online = r.health == .offline ? 0 : (s.invertersOnline ?? s.inverters)
        let asleep = r.health == .offline ? 0 : (s.invertersAsleep ?? 0)
        // a square each up to 4 (the column's width); a bigger station shows the share working as one bar
        let squares = s.inverters <= 4
        return HStack(spacing: 4) {
            if squares {
                ForEach(0..<max(s.inverters, 0), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(r.health == .offline || (i >= online && i < online + asleep) ? Theme.track
                              : i < online ? Theme.success : Theme.danger)
                        .frame(width: 14, height: 14)
                }
            } else {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(r.health == .offline ? Theme.track : Theme.danger)
                        // asleep at night: grey, after the working ones
                        RoundedRectangle(cornerRadius: 3).fill(Theme.track)
                            .frame(width: g.size.width * Double(online + asleep) / Double(max(s.inverters, 1)))
                        RoundedRectangle(cornerRadius: 3).fill(Theme.success)
                            .frame(width: g.size.width * Double(online) / Double(max(s.inverters, 1)))
                    }
                }
                .frame(width: 68, height: 14)
            }
            Text(asleep > 0 ? "พัก \(asleep)" : "\(online)/\(s.inverters)").font(.sarabun(12)).foregroundStyle(Theme.inkMuted).padding(.leading, 2)
                .lineLimit(1).fixedSize()
        }
    }

    private func dataCell(_ r: Monitoring.Row) -> some View {
        HStack(spacing: 5) {
            Circle().fill(r.health == .offline ? Theme.danger : Theme.success).frame(width: 7, height: 7)
            Text(r.station.paired ? MonFormat.time(r.station.lastReading) : "ยังไม่จับคู่")
                .font(.sarabun(13, r.health == .offline ? .bold : .regular))
                .foregroundStyle(r.health == .offline ? Theme.dangerText : Theme.navy)
        }
    }

    private func bar(_ share: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: g.size.width * min(max(share, 0), 1))
            }
        }
        .frame(height: 4)
    }

    private func totalsRow(_ f: Monitoring.Fleet) -> some View {
        HStack(spacing: 0) {
            Text("รวม \(f.stations.count) สถานี · \(MonFormat.number(f.kWp)) kWp").frame(width: Col.station + Col.status, alignment: .leading)
            Text(MonFormat.number(f.powerNow) + " kW").frame(width: Col.power, alignment: .leading)
            Text(MonFormat.number(f.energyToday) + " / " + MonFormat.number(f.expectedSoFar) + " kWh · " + MonFormat.percent(f.yieldShare))
                .frame(width: Col.energy + 12, alignment: .leading)
            Text(MonFormat.number(f.specificYield, 2)).frame(width: Col.yield, alignment: .trailing).padding(.trailing, 12)
            Text(MonFormat.number(f.lossToday) + " kWh").foregroundStyle(Theme.warningInk).frame(width: Col.loss, alignment: .trailing).padding(.trailing, 12)
            Text("\(f.invertersOnline)/\(f.inverters) ทำงาน" + (f.isNight && f.invertersAsleep > 0 ? " · พัก \(f.invertersAsleep)" : "")).frame(width: Col.inverters, alignment: .leading)
            Text("\(f.online)/\(f.stations.count) ออนไลน์").frame(width: Col.data, alignment: .leading)
            Text("\(f.alarmCount)").frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 22)
        }
        .font(.sarabun(13, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 16).frame(height: 46)
        .background(Theme.phonePage)
        .accessibilityElement(children: .combine)
    }

    // MARK: cards

    private func cardsGrid(_ rows: [Monitoring.Row]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
            ForEach(rows) { r in
                Button { opened = r.station } label: { MonitoringStationCard(row: r, picture: picture(r.station)) }
                    .buttonStyle(.plain)
            }
        }
    }

    /// The station's site picture (A2 of its survey report), when this device has it.
    private func picture(_ s: Monitoring.Station) -> UIImage? {
        guard let report = survey.jobs(linkedTo: s.id).max(by: { $0.updated < $1.updated }),
              let photo = report.values.photo("siteMap") else { return nil }
        return survey.image(photo, in: report.id)
    }

    /// The station page's row (`PWAMaintenanceStationView`) for a monitored station.
    static func summary(_ s: Monitoring.Station, health: Monitoring.Health) -> MaintenanceStationSummary {
        let status: MaintenanceStationSummary.Status = health == .normal ? .normal : health == .alarm ? .alarm : .offline
        return MaintenanceStationSummary(id: s.id, mpNumber: s.mpNumber, name: s.name, kWp: s.kWp, energy: s.energyToday ?? 0,
                                         expected: s.expectedSoFar ?? 0, pr: s.prToday ?? 0, status: status,
                                         openRepairs: s.alarms.filter { $0.workOrder != nil }.count,
                                         note: health.title, powerNow: s.powerNow, invertersOnline: s.invertersOnline,
                                         invertersTotal: s.inverters, updated: MonFormat.time(s.lastReading))
    }
}

/// A station as a card: its site picture, name, health and today's figures.
struct MonitoringStationCard: View {
    let row: Monitoring.Row
    let picture: UIImage?

    var body: some View {
        let s = row.station
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let picture {
                    Image(uiImage: picture).resizable().scaledToFill()
                } else {
                    Theme.track.overlay { Image(systemName: "photo").font(.system(size: 26)).foregroundStyle(Theme.inkMuted) }
                }
                MonChip(row.health.title, row.health == .normal ? .ok : row.health == .alarm ? .bad : .muted).padding(10)
            }
            .frame(height: 120).clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(s.name).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text([s.mpNumber.map { "MP \($0)" }, MonFormat.number(s.kWp) + " kWp"].compactMap { $0 }.joined(separator: " · "))
                    .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                HStack {
                    figure("ตอนนี้", MonFormat.number(s.powerNow, 1), "kW")
                    figure("วันนี้", MonFormat.number(s.energyToday), "kWh")
                    figure("kWh/kWp", MonFormat.number(s.specificYield, 2), "")
                }
            }
            .padding(12)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        .overlay(alignment: .leading) { Rectangle().fill(row.health.bar).frame(width: 3) }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                if !unit.isEmpty { Text(unit).font(.sarabun(10)).foregroundStyle(Theme.inkMuted) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

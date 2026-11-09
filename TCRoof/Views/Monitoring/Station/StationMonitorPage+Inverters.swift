import SwiftUI
import Charts
import TCRoofUI
import TCRoofCore

// `อินเวอร์เตอร์` (CHA-73 §2): a card per inverter on the left, the selected one's facts, electrical values, string
// currents and its power today on the right.

extension StationMonitorPage {
    func invertersTab(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        let picked = d.inverters.first { $0.id == selectedInverter } ?? d.inverters.first
        return HStack(alignment: .top, spacing: 14) {
            inverterList(d, picked: picked?.id).frame(width: 320)
            if let inv = picked {
                VStack(spacing: 14) {
                    inverterFacts(inv)
                    inverterElectrical(inv)
                    inverterPower(inv)
                }
                .frame(maxWidth: .infinity)
            } else {
                emptyNote("ไม่มีอินเวอร์เตอร์", "สถานีนี้ยังไม่มีรายการอินเวอร์เตอร์").frame(maxWidth: .infinity)
            }
        }
    }

    private func inverterList(_ d: Monitoring.StationDetail, picked: String?) -> some View {
        let rated = d.inverters.compactMap(\.ratedKW)
        return VStack(alignment: .leading, spacing: 10) {
            cardTitle("อินเวอร์เตอร์ \(d.inverters.count) เครื่อง",
                      note: rated.count == d.inverters.count && !rated.isEmpty ? "รวม " + MonFormat.number(rated.reduce(0, +)) + " kW" : nil)
            ForEach(d.inverters) { inv in
                Button { selectedInverter = inv.id } label: { inverterCard(inv, on: inv.id == picked) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(inv.id == picked ? .isSelected : [])
                    .accessibilityIdentifier("station.inverter." + inv.id)
            }
        }
    }

    private func inverterCard(_ inv: Monitoring.Inverter, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(inv.name).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                if let r = inv.ratedKW { Text(MonFormat.number(r) + " kW").font(.sarabun(13)).foregroundStyle(Theme.inkMuted) }
                Spacer()
                statusChip(inv.status)
            }
            Text([inv.model, inv.sn.map { "SN " + $0 }].compactMap { $0 }.joined(separator: " · ").ifEmpty(MonFormat.dash))
                .font(.sarabun(13)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text(MonFormat.number(inv.powerNow, 1)).font(.sarabun(26, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                Text("kW").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Text("วันนี้").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                Text(MonFormat.number(inv.today) + " kWh").font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
            }
            Text(["อัปเดต " + dayTime(inv.lastUpdate), inv.stoppedSince.map { "หยุดผลิตตั้งแต่ " + MonFormat.time($0) }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.sarabun(12)).foregroundStyle(Theme.inkMuted.opacity(0.85)).lineLimit(1)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func inverterFacts(_ inv: Monitoring.Inverter) -> some View {
        let facts: [(String, String)] = [
            ("SN", inv.sn ?? MonFormat.dash),
            ("กำลังพิกัด", inv.ratedKW.map { MonFormat.number($0) + " kW" } ?? MonFormat.dash),
            ("กำลังตอนนี้", inv.powerNow.map { MonFormat.number($0, 1) + " kW" } ?? MonFormat.dash),
            ("อัปเดต", dayTime(inv.lastUpdate)),
            ("ผลิตวันนี้", inv.today.map { MonFormat.number($0) + " kWh" } ?? MonFormat.dash),
            ("ผลิตเดือนนี้", Self.scaled(inv.month)),
            ("ผลิตสะสม", Self.scaled(inv.total)),
            ("ดาต้าล็อกเกอร์", inv.datalogger ?? MonFormat.dash),
        ]
        return MonCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle(inv.name, note: inv.model.map { "Growatt " + $0 })
                    Spacer()
                    statusChip(inv.status)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(facts, id: \.0) { title, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                            Text(value).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func inverterElectrical(_ inv: Monitoring.Inverter) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    cardTitle("ค่าทางไฟฟ้า · " + inv.name)
                    Spacer()
                    Text("queryLastData").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                }
                if inv.ac.isEmpty && inv.strings.isEmpty {
                    Text("ไม่มีข้อมูล · ยังไม่ได้อ่านค่าของอุปกรณ์จาก Growatt").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        acTable(inv).frame(width: 300)
                        stringGrid(inv)
                    }
                }
            }
        }
    }

    private func acTable(_ inv: Monitoring.Inverter) -> some View {
        VStack(spacing: 6) {
            acRow("AC", "V", "A", "kW", header: true)
            ForEach(inv.ac, id: \.name) { p in
                acRow(p.name, MonFormat.number(p.volts, 1), MonFormat.number(p.amps, 1), MonFormat.number(p.kW, 1))
            }
            Divider().overlay(Theme.hairline)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    small("ความถี่"); smallValue(inv.frequency.map { MonFormat.number($0, 2) + " Hz" })
                    small("อุณหภูมิ"); smallValue(inv.temperature.map { MonFormat.number($0) + " °C" })
                }
                GridRow {
                    small("IPM"); smallValue(inv.ipmTemperature.map { MonFormat.number($0) + " °C" })
                    small("จำกัดกำลัง"); smallValue(inv.powerLimit.map { MonFormat.number($0) + "%" })
                }
            }
        }
    }

    private func acRow(_ a: String, _ b: String, _ c: String, _ d: String, header: Bool = false) -> some View {
        HStack {
            Text(a).frame(width: 40, alignment: .leading)
            Text(b).frame(maxWidth: .infinity, alignment: .trailing)
            Text(c).frame(maxWidth: .infinity, alignment: .trailing)
            Text(d).frame(maxWidth: .infinity, alignment: .trailing).fontWeight(header ? .regular : .bold)
        }
        .font(.sarabun(header ? 13 : 15)).foregroundStyle(header ? Theme.inkMuted : Theme.navy).monospacedDigit()
    }

    private func small(_ t: String) -> some View { Text(t).font(.sarabun(12)).foregroundStyle(Theme.inkMuted) }
    private func smallValue(_ t: String?) -> some View {
        Text(t ?? MonFormat.dash).font(.sarabun(13, .bold)).foregroundStyle(Theme.navy).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func stringGrid(_ inv: Monitoring.Inverter) -> some View {
        let tints = inv.stringTints
        let lows = tints.joined().filter { $0 != .normal }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("กระแสสตริง (A)").font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                Text((lows == 0 ? "ใกล้เคียงกันทุกสตริง" : "\(lows) สตริงผิดปกติ") + " · ค่ากลาง " + MonFormat.number(inv.stringMedian, 1) + " A")
                    .font(.sarabun(12)).foregroundStyle(lows == 0 ? Theme.inkMuted : Theme.warningText)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Text("MPPT").font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                    ForEach(inv.strings.indices, id: \.self) { m in
                        Text("\(m + 1)").font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                    }
                }
                ForEach(0..<2, id: \.self) { b in
                    GridRow {
                        Text(b == 0 ? "a" : "b").font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                        ForEach(inv.strings.indices, id: \.self) { m in
                            let v = b < inv.strings[m].count ? inv.strings[m][b] : nil
                            let t = b < tints[m].count ? tints[m][b] : .none
                            stringCell(v, t)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                swatch(Theme.primarySoft, "ปกติ")
                swatch(Theme.warningSoft, "ต่ำกว่าค่ากลาง 20% ขึ้นไป")
                swatch(Theme.dangerSoft, "ไม่มีกระแส")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stringCell(_ v: Double?, _ t: Monitoring.StringTint) -> some View {
        Text(MonFormat.number(v, 1)).font(.sarabun(13, .bold)).monospacedDigit()
            .foregroundStyle(t == .normal ? Theme.navy : t == .low ? Theme.warningText : Theme.dangerText)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(t == .normal ? Theme.primarySoft : t == .low ? Theme.warningSoft : Theme.dangerSoft,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    func swatch(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(t).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
        }
    }

    private func inverterPower(_ inv: Monitoring.Inverter) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("กำลังผลิต \(inv.name) (kW) · ทุก 5 นาที · วันนี้").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                        Text("queryHistoricalData · เก็บย้อนหลังได้ทีละ 1 วัน").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    if let r = inv.ratedKW { Text("พิกัด " + MonFormat.number(r) + " kW").font(.sarabun(13)).foregroundStyle(Theme.inkMuted) }
                }
                if inv.curve.isEmpty {
                    Text("ไม่มีข้อมูล").font(.sarabun(15, .semibold)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    DayLinesChart(now: now, lines: [
                        .init(id: "exp", values: inv.expectedCurve.map { Optional($0) }, color: Theme.inkMuted, dashed: true),
                        .init(id: "pv", values: inv.curve, color: Theme.success, filled: true),
                    ])
                    .frame(height: 240)
                }
            }
        }
    }
}

/// Lines of today's 5-minute values from 06:00 to 18:00, each optionally dashed or filled (the station's pages).
struct DayLinesChart: View {
    struct Line: Identifiable {
        var id: String
        var values: [Double?]
        var color: Color
        var dashed = false
        var filled = false
    }

    let now: Date
    let lines: [Line]
    var yAxis = false

    private var window: ClosedRange<Int> { (6 * 60 / Monitoring.slotMinutes)...(18 * 60 / Monitoring.slotMinutes) }

    private func x(_ i: Int) -> Date {
        Calendar.current.startOfDay(for: now).addingTimeInterval(TimeInterval(i * Monitoring.slotMinutes * 60))
    }

    var body: some View {
        Chart {
            ForEach(lines) { l in
                ForEach(Array(window), id: \.self) { i in
                    if i < l.values.count, let v = l.values[i] {
                        if l.filled {
                            AreaMark(x: .value("เวลา", x(i)), y: .value("ค่า", v), series: .value("ชุด", l.id))
                                .foregroundStyle(l.color.opacity(0.14))
                        }
                        LineMark(x: .value("เวลา", x(i)), y: .value("ค่า", v), series: .value("ชุด", l.id))
                            .foregroundStyle(l.color)
                            .lineStyle(StrokeStyle(lineWidth: l.dashed ? 1.5 : 2, dash: l.dashed ? [4, 3] : []))
                    }
                }
            }
        }
        .chartXScale(domain: x(window.lowerBound)...x(window.upperBound))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).font(.sarabun(11))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                if yAxis { AxisValueLabel().font(.sarabun(11)) }
            }
        }
        .chartLegend(.hidden)
    }
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

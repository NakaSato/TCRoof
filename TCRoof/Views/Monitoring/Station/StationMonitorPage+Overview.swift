import SwiftUI
import Charts
import TCRoofUI
import TCRoofCore

// `ภาพรวม` (CHA-73 §1): the issue banner, five figure cards, the power chart, the energy flow, the inverters and the
// latest alarms. Offline, every live figure reads `—`.

extension StationMonitorPage {
    func overviewTab(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        VStack(spacing: 14) {
            if let banner = issueBanner(s, d) { banner }
            overviewCards(s, d)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    powerCard(s, d)
                    inverterTable(d)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    StationEnergyFlow(flow: Monitoring.EnergyFlow(station: s, detail: d, slot: nowSlot, offline: offline),
                                      zeroExport: d.zeroExport, known: !offline && d.meter != nil, reduceMotion: reduceMotion)
                    recentAlarms(d)
                }
                .frame(width: 358)
            }
        }
    }

    // MARK: banner

    private func issueBanner(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> AnyView? {
        let (title, line): (String, String)
        if !s.paired {
            title = "ยังไม่จับคู่กับ Plant ของ Growatt"
            line = "ไม่มีข้อมูล · จับคู่ได้ที่ ตั้งค่า Monitoring"
        } else if health == .normal {
            return nil
        } else if offline {
            let hours = s.lastReading.map { max(Int(now.timeIntervalSince($0) / 3600), 0) }
            title = hours.map { "ไม่มีข้อมูล \($0) ชม." } ?? "ไม่มีข้อมูล"
            let lost = s.alarms.first { $0.source == .lost }
            line = ["ดาต้าล็อกเกอร์ไม่ส่งข้อมูล" + (s.lastReading.map { "ตั้งแต่ " + MonFormat.time($0) } ?? ""),
                    lost?.workOrder.map { "ใบงาน " + $0 }].compactMap { $0 }.joined(separator: " · ")
        } else {
            let a = s.alarms.first { $0.source == .growatt } ?? s.alarms.first { $0.source != .tcroof }
            let days = d.events.filter { $0.device == a?.part && $0.source == .growatt }
                .map { Calendar.current.startOfDay(for: $0.firstSeen) }
            let count = Set(days).count
            title = [a?.part, "fault", count > 1 ? "· \(count) วัน" : nil].compactMap { $0 }.joined(separator: " ")
            line = [a.map { $0.label + " " + $0.detail }, a?.workOrder.map { "ใบงาน " + $0 }]
                .compactMap { $0 }.joined(separator: " · ")
        }
        let danger = health == .alarm
        return AnyView(
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(danger ? Theme.dangerText : Theme.navy)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sarabun(15, .bold)).foregroundStyle(danger ? Theme.dangerText : Theme.navy)
                    Text(line).font(.sarabun(13)).foregroundStyle(danger ? Theme.dangerText : Theme.inkStrong).lineLimit(1)
                }
                Spacer(minLength: 10)
                if s.paired {
                    Button { maintenance = s } label: { Text("ไปหน้าบำรุงรักษา ›") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                        .accessibilityIdentifier("station.toMaintenance")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(danger ? Theme.dangerSoft : Theme.track, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("station.banner")
        )
    }

    // MARK: the five cards

    private func overviewCards(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        let share = s.yieldShare
        let under = (share ?? 1) < 0.75
        let load = d.loadToday(through: nowSlot)
        let upTo = offline ? "ถึง " + MonFormat.time(s.lastReading) : nil
        let total = MonFormat.energy(s.totalEnergy)
        let month = MonFormat.energy(s.months.last?.energy)
        let loadTotal: Double? = {
            guard let m = d.meter, let i = m.importTotal, let pv = s.totalEnergy else { return nil }
            return i + pv - (m.exportTotal ?? 0)
        }()
        return HStack(spacing: 12) {
            figureCard("ผลิตจาก PV วันนี้", MonFormat.number(s.energyToday), "",
                       caption: MonFormat.percent(share) + " ของที่คาด · ตอนนี้ " + (offline ? MonFormat.dash : MonFormat.number(s.powerNow, 1) + " kW"),
                       tint: under ? Theme.dangerText : Theme.navy, suffix: "/ คาด " + MonFormat.number(s.expectedSoFar) + " kWh")
            figureCard("ใช้ไฟของสถานี วันนี้", MonFormat.number(load), "kWh",
                       caption: [upTo, "สะสม " + Self.scaled(loadTotal)].compactMap { $0 }.joined(separator: " · "))
            figureCard("ซื้อจากการไฟฟ้า วันนี้", MonFormat.number(d.meter?.importToday), "kWh",
                       caption: [upTo, "สะสม " + Self.scaled(d.meter?.importTotal)].compactMap { $0 }.joined(separator: " · "))
            figureCard("ไหลย้อน วันนี้", MonFormat.number(d.meter?.exportToday), "kWh",
                       caption: [zeroExportText(d), "สะสม " + Self.scaled(d.meter?.exportTotal)].compactMap { $0 }.joined(separator: " · "))
            figureCard("PV สะสมตั้งแต่ติดตั้ง", total.value, total.unit,
                       caption: "ลด CO₂ " + MonFormat.number(s.totalEnergy.map { $0 * Monitoring.co2PerKWh / 1000 }) + " t · เดือนนี้ "
                           + month.value + " " + month.unit)
        }
    }

    func zeroExportText(_ d: Monitoring.StationDetail) -> String? {
        d.zeroExport.map { $0 ? "กันย้อนเปิด" : "กันย้อนปิด" }
    }

    /// `1.82 GWh`, `0 kWh`, `—`.
    static func scaled(_ kWh: Double?) -> String {
        let e = MonFormat.energy(kWh)
        return e.value == MonFormat.dash ? MonFormat.dash : e.value + " " + e.unit
    }

    // MARK: power chart

    private func powerCard(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(range == .today ? "กำลัง (kW) · ทุก 5 นาที · วันนี้" : "พลังงาน (kWh) · " + MonitoringPage.rangeTitle(range))
                            .font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                        Text(sourceNote(s, d)).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    MonSwitch(options: Monitoring.ChartRange.allCases.map { ($0, MonitoringPage.rangeLabel($0)) }, selection: $range)
                }
                if s.curve.isEmpty && s.days.isEmpty {
                    Text("ไม่มีข้อมูล").font(.sarabun(15, .semibold)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    StationPowerChart(station: s, load: d.loadCurve, range: range, now: now, pvColor: pvColor)
                        .frame(height: 300)
                }
                HStack(spacing: 14) {
                    legend(pvColor, "PV ผลิตจริง")
                    if range == .today, !d.loadCurve.isEmpty { legend(Theme.teamPurple, "ใช้ไฟของสถานี") }
                    legend(Theme.inkMuted, "PV คาดการณ์", dashed: true)
                    Spacer()
                    if range == .today {
                        Text(offline ? "ข้อมูลหยุดที่ " + MonFormat.time(s.lastReading) : "ถึง " + MonFormat.time(s.lastReading))
                            .font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("station.powerChart")
    }

    var pvColor: Color { health == .alarm ? Theme.danger : health == .offline ? Theme.inkMuted : Theme.success }

    /// `PV จาก plant/power · ใช้ไฟจากมิเตอร์ · ไม่มีเซนเซอร์แสง`.
    private func sourceNote(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> String {
        [s.paired ? "PV จาก plant/power" : "ยังไม่จับคู่ Plant",
         d.meter == nil ? "ไม่มีข้อมูลมิเตอร์" : "ใช้ไฟจากมิเตอร์",
         d.sensor == nil ? "ไม่มีเซนเซอร์แสง" : "มีเซนเซอร์แสง"].joined(separator: " · ")
    }

    func legend(_ color: Color, _ title: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Capsule().stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [3, 2] : [])).frame(width: 16, height: 2.5)
            Text(title).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
        }
    }

    // MARK: inverters

    private func inverterTable(_ d: Monitoring.StationDetail) -> some View {
        let working = d.inverters.filter { $0.status == .normal }.count
        return MonCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    cardTitle("อินเวอร์เตอร์", note: d.inverters.isEmpty ? nil : "\(working)/\(d.inverters.count) ทำงาน")
                    Spacer()
                    Button("ดูทุกเครื่อง ›") { tab = .inverters }
                        .font(.sarabun(14, .bold)).foregroundStyle(Theme.primary).frame(minHeight: 44)
                        .accessibilityIdentifier("station.allInverters")
                }
                tableHeader(["เครื่อง", "รุ่น", "ตอนนี้", "วันนี้", "เดือนนี้", "สถานะ"])
                ForEach(d.inverters) { inv in
                    Button { selectedInverter = inv.id; tab = .inverters } label: { inverterRow(inv) }
                        .buttonStyle(.plain)
                    Divider().overlay(Theme.hairline)
                }
            }
        }
    }

    private static let columns: [(CGFloat?, Alignment)] = [(130, .leading), (nil, .leading), (70, .trailing), (90, .trailing),
                                                           (100, .trailing), (90, .trailing)]

    private func tableHeader(_ titles: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                cell(Text(t).font(.sarabun(13)).foregroundStyle(Theme.inkMuted), i)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    private func cell<V: View>(_ v: V, _ i: Int) -> some View {
        let (w, a) = Self.columns[i]
        return Group {
            if let w { v.frame(width: w, alignment: a) } else { v.frame(maxWidth: .infinity, alignment: a) }
        }
    }

    private func inverterRow(_ inv: Monitoring.Inverter) -> some View {
        HStack(spacing: 10) {
            cell(HStack(spacing: 8) { dot(inv.status); Text(inv.name).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy) }, 0)
            cell(Text(inv.model ?? MonFormat.dash).font(.sarabun(14)).foregroundStyle(Theme.inkStrong).lineLimit(1), 1)
            cell(Text(MonFormat.number(inv.powerNow, 1)).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).monospacedDigit(), 2)
            cell(Text(Self.scaled(inv.today)).font(.sarabun(14)).foregroundStyle(Theme.navy).monospacedDigit(), 3)
            cell(Text(Self.scaled(inv.month)).font(.sarabun(14)).foregroundStyle(Theme.navy).monospacedDigit(), 4)
            cell(statusChip(inv.status), 5)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: alarms

    private func recentAlarms(_ d: Monitoring.StationDetail) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    cardTitle("แจ้งเตือนจากอินเวอร์เตอร์")
                    Spacer()
                    Button("ประวัติทั้งหมด ›") { tab = .alarms }
                        .font(.sarabun(14, .bold)).foregroundStyle(Theme.primary).frame(minHeight: 44)
                }
                if d.events.isEmpty {
                    Text("ไม่มีแจ้งเตือน").font(.sarabun(14)).foregroundStyle(Theme.inkMuted).padding(.vertical, 12)
                }
                ForEach(d.events.prefix(4)) { e in
                    Button { selectedEvent = e.id; tab = .alarms } label: { alarmLine(e) }.buttonStyle(.plain)
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func alarmLine(_ e: Monitoring.AlarmEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(e.isOpen ? Theme.danger : e.isAcknowledged(acks.ids) ? Theme.inkMuted.opacity(0.5) : Theme.jobOrange)
                .frame(width: 9, height: 9).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.label + " · " + e.device).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text([e.titleTH, e.repeats.count > 1 ? "\(e.repeats.count) ครั้ง" : nil, e.workOrder]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(e.isOpen ? "ยังไม่ปิด" : Self.thaiDay(e.firstSeen)).font(.sarabun(13, .bold))
                .foregroundStyle(e.isOpen ? Theme.dangerText : Theme.inkMuted)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The station's power today (PV, its use and the forecast) or its energy by day or month against the forecast.
struct StationPowerChart: View {
    let station: Monitoring.Station
    let load: [Double?]
    let range: Monitoring.ChartRange
    let now: Date
    let pvColor: Color

    var body: some View {
        let chart = Monitoring.Chart([station], range: range, now: now)
        Chart {
            if range == .today {
                ForEach(chart.total) { p in
                    if let e = p.expected {
                        LineMark(x: .value("เวลา", p.x), y: .value("kW", e), series: .value("ชุด", "คาด"))
                            .foregroundStyle(Theme.inkMuted.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    if let a = p.actual {
                        AreaMark(x: .value("เวลา", p.x), y: .value("kW", a), series: .value("ชุด", "PV"))
                            .foregroundStyle(pvColor.opacity(0.14))
                        LineMark(x: .value("เวลา", p.x), y: .value("kW", a), series: .value("ชุด", "PV"))
                            .foregroundStyle(pvColor).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                ForEach(loadPoints, id: \.0) { x, v in
                    LineMark(x: .value("เวลา", x), y: .value("kW", v), series: .value("ชุด", "ใช้ไฟ"))
                        .foregroundStyle(Theme.teamPurple).lineStyle(StrokeStyle(lineWidth: 1.8))
                }
                RuleMark(x: .value("เวลา", now)).foregroundStyle(Theme.navy.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else {
                ForEach(chart.total) { p in
                    if let a = p.actual {
                        BarMark(x: .value("วัน", p.x, unit: range == .year ? .month : .day), y: .value("kWh", a))
                            .foregroundStyle(pvColor.opacity(0.75))
                    }
                    if let e = p.expected {
                        LineMark(x: .value("วัน", p.x, unit: range == .year ? .month : .day), y: .value("kWh", e), series: .value("ชุด", "คาด"))
                            .foregroundStyle(Theme.inkMuted).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
            }
        }
        .chartXScale(domain: chart.domain)
        .chartXAxis {
            AxisMarks(values: range == .today ? .stride(by: .hour, count: 3) : .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                if range == .today {
                    AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).font(.sarabun(11))
                } else if range == .year {
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.sarabun(11))
                } else {
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits)).font(.sarabun(11))
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel().font(.sarabun(11)) } }
        .chartLegend(.hidden)
        .accessibilityLabel("กราฟกำลังผลิตของสถานี")
    }

    /// The use from 06:00 to 19:00, where read.
    private var loadPoints: [(Date, Double)] {
        let start = Calendar.current.startOfDay(for: now)
        return Monitoring.Chart.dayWindow.compactMap { i in
            guard i < load.count, let v = load[i] else { return nil }
            return (start.addingTimeInterval(TimeInterval(i * Monitoring.slotMinutes * 60)), v)
        }
    }
}

/// `การไหลของพลังงาน`: the grid (bought) and PV feeding the station's use, the kW on each line, and PV's share of the
/// day's use. A line's dashes move only while power flows on it, and never with Reduce Motion.
struct StationEnergyFlow: View {
    let flow: Monitoring.EnergyFlow
    let zeroExport: Bool?
    /// The meter is read and the station reporting; else every figure is `—` and the chip reads `ไม่มีข้อมูล`.
    let known: Bool
    let reduceMotion: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("การไหลของพลังงาน").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                    Spacer()
                    if known {
                        MonChip(["On-grid", zeroExport.map { $0 ? "กันย้อนเปิด" : "กันย้อนปิด" }].compactMap { $0 }.joined(separator: " · "), .ok)
                    } else {
                        MonChip("ไม่มีข้อมูล", .muted)
                    }
                }
                diagram.frame(height: 200)
                shareBar
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("station.flow")
        .onAppear(perform: animate)
        .onChange(of: reduceMotion) { _, _ in animate() }
    }

    private func animate() {
        guard !reduceMotion else { phase = 0; return }
        phase = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { phase = -14 }
    }

    private var diagram: some View {
        GeometryReader { g in
            let w = g.size.width
            let grid = CGPoint(x: 46, y: 28), pv = CGPoint(x: w - 46, y: 28), load = CGPoint(x: w / 2, y: 140)
            ZStack {
                line(from: CGPoint(x: grid.x + 30, y: grid.y), to: CGPoint(x: pv.x - 30, y: pv.y), kW: flow.sentBack, color: Theme.inkMuted, reverse: true)
                line(from: CGPoint(x: grid.x + 16, y: grid.y + 46), to: CGPoint(x: load.x - 22, y: load.y - 16), kW: flow.bought, color: Theme.jobOrange)
                line(from: CGPoint(x: pv.x - 16, y: pv.y + 46), to: CGPoint(x: load.x + 22, y: load.y - 16), kW: flow.pv, color: Theme.success)
                Text(known ? "ไหลย้อน " + MonFormat.number(flow.sentBack, 1) + " kW" : "ไม่มีข้อมูล")
                    .font(.sarabun(12, .bold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 4).background(Theme.surface)
                    .position(x: w / 2, y: grid.y - 6)
                node("bolt.horizontal", Theme.jobOrange, "การไฟฟ้า (ซื้อ)", flow.bought).position(x: grid.x, y: grid.y + 30)
                node("sun.max", Theme.success, "PV", flow.pv).position(x: pv.x, y: pv.y + 30)
                node("house", Theme.teamPurple, "โหลดสถานี", flow.load).position(x: load.x, y: load.y + 26)
            }
        }
    }

    private func node(_ symbol: String, _ tint: Color, _ title: String, _ kW: Double?) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 46, height: 46).background(tint.opacity(0.14), in: Circle())
            Text(title).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize()
            Text(known ? MonFormat.number(kW, 1) + " kW" : MonFormat.dash).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                .fixedSize()
        }
    }

    private func line(from a: CGPoint, to b: CGPoint, kW: Double?, color: Color, reverse: Bool = false) -> some View {
        let flows = known && Monitoring.EnergyFlow.flows(kW)
        return Path { p in p.move(to: a); p.addLine(to: b) }
            .stroke(flows ? color : Theme.borderSubtle,
                    style: StrokeStyle(lineWidth: flows ? 3 : 2, lineCap: .round, dash: [6, 8],
                                       dashPhase: flows ? (reverse ? -phase : phase) : 0))
    }

    private var shareBar: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.warningSoft)
                    Capsule().fill(Theme.success).frame(width: g.size.width * CGFloat(flow.pvShareOfUse ?? 0))
                }
            }
            .frame(height: 8)
            Text("PV " + MonFormat.percent(flow.pvShareOfUse) + " ของไฟที่ใช้วันนี้").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                .fixedSize()
        }
    }

    private var accessibilityText: String {
        guard known else { return "การไหลของพลังงาน ไม่มีข้อมูล" }
        return "การไหลของพลังงาน: ซื้อจากการไฟฟ้า \(MonFormat.number(flow.bought, 1)) kW, PV \(MonFormat.number(flow.pv, 1)) kW, "
            + "โหลดสถานี \(MonFormat.number(flow.load, 1)) kW, ไหลย้อน \(MonFormat.number(flow.sentBack, 1)) kW, "
            + "PV \(MonFormat.percent(flow.pvShareOfUse)) ของไฟที่ใช้วันนี้"
    }
}

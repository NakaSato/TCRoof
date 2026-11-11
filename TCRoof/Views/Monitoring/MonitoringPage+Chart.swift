import SwiftUI
import Charts
import Accessibility
import TCRoofUI
import TCRoofCore

// `กำลังผลิตรวม` (issue #259 §4): the fleet's power against the forecast, or one line per station; the gap under the
// forecast shaded as lost energy; the day's peak, the reading now and when alarms began marked; a summary column.

extension MonitoringPage {
    func chartCard(_ f: Monitoring.Fleet) -> some View {
        let chart = Monitoring.Chart(f.stations, range: range, now: f.now, hidden: hidden)
        // before sunrise the day has nothing read yet: the forecast alone, and a note saying so (CHA-110)
        let night = range == .today && f.isBeforeSunrise
        return MonCard {
            VStack(alignment: .leading, spacing: 10) {
                chartHeader(chart, f)
                HStack(alignment: .top, spacing: 14) {
                    MonitoringChartView(chart: chart, split: split, now: f.now, forecastOnly: night, colors: chartColors(chart))
                        .frame(height: chart.range == .today && !chart.clusters.isEmpty ? 190 + MonitoringChartView.laneHeight : 190)
                        .overlay(alignment: .top) { if night { nightNote(f).padding(.top, 36) } }
                    chartSummary(chart).frame(width: 150, alignment: .leading)
                }
                if split { stationChips(chart, f) }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chartHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.chart")
    }

    /// `ยังไม่มีแสง · คาดเริ่มผลิตราว 06:10` and yesterday's energy.
    private func nightNote(_ f: Monitoring.Fleet) -> some View {
        VStack(spacing: 2) {
            Label("ยังไม่มีแสง · คาดเริ่มผลิตราว " + MonFormat.time(f.productionStart), systemImage: "moon.stars")
                .font(.sarabun(14, .semibold)).foregroundStyle(Theme.navy)
            Text(Self.yesterday(f.yesterdayEnergy)).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monitoring.chart.night")
    }

    private func chartHeader(_ chart: Monitoring.Chart, _ f: Monitoring.Fleet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("กำลังผลิตรวม (\(range == .today ? "kW" : "kWh")) " + Self.rangeTitle(range))
                    .font(.sarabun(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 8)
                MonSwitch(options: Monitoring.ChartRange.allCases.map { ($0, Self.rangeLabel($0)) }, selection: $range)
                MonSwitch(options: [(false, "รวม"), (true, "แยกสถานี")], selection: $split)
            }
            HStack(spacing: 14) {
                Text(chartLine(chart, f)).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 8)
                legend(Theme.primary, "ผลิตจริง", dashed: false)
                legend(Theme.inkMuted, "คาดการณ์", dashed: true)
                legendSwatch(Theme.warningSoft, "สูญเสีย")
            }
        }
    }

    /// `ตอนนี้ 372 kW · คาด 495 kW · 6 สถานี`.
    private func chartLine(_ chart: Monitoring.Chart, _ f: Monitoring.Fleet) -> String {
        if let c = chart.current {
            return "ตอนนี้ \(MonFormat.number(c.actual)) kW · คาด \(MonFormat.number(c.expected)) kW · \(f.stations.count) สถานี"
        }
        return "\(f.stations.count) สถานี"
    }

    private func legend(_ color: Color, _ title: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule().stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [3, 2] : [])).frame(width: 16, height: 2.5)
            Text(title).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
        }
    }

    private func legendSwatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 10)
            Text(title).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// The column beside the chart, for the range picked.
    private func chartSummary(_ chart: Monitoring.Chart) -> some View {
        let s = chart.summary
        return VStack(alignment: .leading, spacing: 8) {
            summaryItem(range == .today ? "ผลิตถึง " + MonFormat.time(s.asOf) : "ผลิตรวม",
                        MonFormat.number(s.produced) + " kWh", detail: MonFormat.percent(s.share) + " คาด")
            if range == .today {
                summaryItem("พยากรณ์ทั้งวัน", MonFormat.number(s.projected) + " kWh", detail: "ที่อัตราตอนนี้")
            } else {
                summaryItem("คาดการณ์", MonFormat.number(s.expected) + " kWh", detail: nil)
            }
            summaryItem(range == .today ? "สูญเสียถึงตอนนี้" : "สูญเสีย", MonFormat.number(s.loss) + " kWh", detail: nil, tint: Theme.warningInk)
            if let d = s.vsPrevious {
                summaryItem(range == .today ? "เทียบเมื่อวานเวลาเดียวกัน" : "เทียบ 7 วันก่อน",
                            MonFormat.percent(d, signed: true), detail: MonFormat.number(s.previous) + " kWh",
                            tint: d < 0 ? Theme.dangerText : Theme.successInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryItem(_ title: String, _ value: String, detail: String?, tint: Color = Theme.navy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.sarabun(16, .bold)).foregroundStyle(tint).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(.sarabun(11)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            }
        }
    }

    /// Each series' colour: a station with its own line by its place among the chips, the others grey.
    private func chartColors(_ chart: Monitoring.Chart) -> [String: Color] {
        var out = Dictionary(uniqueKeysWithValues: chart.leadIDs.enumerated().map { ($1, MonitoringChartView.color($0)) })
        out[Monitoring.Chart.othersID] = MonitoringChartView.othersColor
        return out
    }

    /// `แยกสถานี`: at most six chips by station code (CHA-110); past six, the five largest and `อื่น ๆ n สถานี`, which
    /// hides or shows the rest together. A tap hides or shows its line.
    private func stationChips(_ chart: Monitoring.Chart, _ f: Monitoring.Fleet) -> some View {
        let byID = Dictionary(f.stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let others = chart.otherIDs
        let othersOn = others.contains { !hidden.contains($0) }
        return HStack(spacing: 8) {
            ForEach(Array(chart.leadIDs.enumerated()), id: \.element) { i, id in
                let on = !hidden.contains(id)
                chip(byID[id].map(Monitoring.Chart.name) ?? id, color: MonitoringChartView.color(i), on: on) {
                    if on { hidden.insert(id) } else { hidden.remove(id) }
                }
            }
            if !others.isEmpty {
                chip("อื่น ๆ \(others.count) สถานี", color: MonitoringChartView.othersColor, on: othersOn) {
                    if othersOn { hidden.formUnion(others) } else { hidden.subtract(others) }
                }
            }
        }
    }

    private func chip(_ title: String, color: Color, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Circle().fill(on ? color : Theme.track).frame(width: 10, height: 10)
                Text(title).font(.sarabun(13, on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                    .lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(on ? Theme.surface : Theme.track, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderSubtle))
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "แสดง" : "ซ่อน")
    }

    static func rangeLabel(_ r: Monitoring.ChartRange) -> String {
        switch r {
        case .today: "วันนี้"
        case .week: "7 วัน"
        case .month: "30 วัน"
        case .year: "12 เดือน"
        }
    }

    static func rangeTitle(_ r: Monitoring.ChartRange) -> String {
        switch r {
        case .today: "วันนี้"
        case .week: "7 วันล่าสุด"
        case .month: "30 วันล่าสุด"
        case .year: "12 เดือนล่าสุด"
        }
    }

    // MARK: ต้องดำเนินการ

    /// One row per station (CHA-110), at the chart card's height: the rows scroll inside, and a footer appears when
    /// they don't fit (`ดูทั้งหมด` goes to the table's `มีปัญหา`) or at night with inverters asleep.
    func actionsCard(_ f: Monitoring.Fleet) -> some View {
        let actions = f.actions
        let asleep = f.isNight ? f.invertersAsleep : 0
        let overflow = actionsContent > actionsViewport + 1
        return MonCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                actionsHeader(actions.count)
                Divider()
                if actions.isEmpty {
                    Text("ไม่มีเรื่องต้องดำเนินการ").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                                if i > 0 { Divider() }
                                actionRow(a, now: f.now)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsContent = $0 }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsViewport = $0 }
                }
                if overflow || asleep > 0 {
                    Divider()
                    actionsFooter(asleep: asleep, overflow: overflow)
                }
            }
        }
        .frame(height: chartHeight > 0 ? chartHeight : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.actions")
    }

    private func actionsHeader(_ n: Int) -> some View {
        HStack(spacing: 8) {
            Text("ต้องดำเนินการ").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
            if n > 0 {
                Text("\(n) สถานี").font(.sarabun(13, .bold)).foregroundStyle(Theme.dangerText)
                    .padding(.horizontal, 8).frame(minHeight: 22).background(Theme.dangerSoft, in: Capsule())
                    .fixedSize()
            }
            Spacer()
            Text("เรียงตามพลังงานที่เสีย").font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .padding(16)
    }

    /// `กลางคืน · อินเวอร์เตอร์พัก 42 เครื่องไม่นับ` and `ดูทั้งหมด ›`.
    private func actionsFooter(asleep: Int, overflow: Bool) -> some View {
        HStack(spacing: 8) {
            if asleep > 0 {
                Label("กลางคืน · อินเวอร์เตอร์พัก \(asleep) เครื่องไม่นับ", systemImage: "moon")
                    .font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.85)
                    .accessibilityIdentifier("monitoring.actions.asleep")
            }
            Spacer(minLength: 4)
            if overflow {
                Button {
                    filter = .problem
                    scrollToStations += 1
                } label: {
                    HStack(spacing: 3) {
                        Text("ดูทั้งหมด")
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.sarabun(14, .semibold)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("monitoring.actions.all")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func actionRow(_ a: Monitoring.Action, now: Date) -> some View {
        let alarm = a.alarm
        let bar: Color = alarm.source == .tcroof ? Theme.warning : Theme.danger
        return Button { opened = a.station } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        // the name may be cut, never the chip
                        Text(Self.title(a.station)).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                            .lineLimit(1).truncationMode(.tail)
                        MonChip(a.status, alarm.source == .tcroof ? .warn : .bad)
                    }
                    Text(a.summary(now: now)).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.lossText(alarm.loss)).font(.sarabun(15, .bold)).foregroundStyle(Theme.warningInk)
                        .lineLimit(1).fixedSize()
                    if let wo = alarm.workOrder {
                        MonChip("ใบงาน " + wo, .info)
                    } else {
                        MonChip("ยังไม่มีใบงาน", .warn)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 44)
            .overlay(alignment: .leading) { Rectangle().fill(bar).frame(width: 4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// `380 kWh วันนี้`, `≤ 430 kWh ไม่ทราบ`, `≈ 6 kWh วันนี้`.
    static func lossText(_ l: Monitoring.Alarm.Loss) -> String {
        switch l {
        case .measured(let v): MonFormat.number(v) + " kWh วันนี้"
        case .atMost(let v): "≤ " + MonFormat.number(v) + " kWh ไม่ทราบ"
        case .about(let v): "≈ " + MonFormat.number(v) + " kWh วันนี้"
        case .unknown: MonFormat.dash
        }
    }

    /// `นครชัยศรี` of `สถานีผลิตน้ำนครชัยศรี`, `บ้านโป่ง` of `P1_3 สถานีผลิตน้ำบ้านโป่ง` (its code left out).
    static func shortName(_ s: Monitoring.Station) -> String {
        let prefix = "สถานีผลิตน้ำ", name = Monitoring.Chart.rest(s)
        let short = name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
        return short.isEmpty ? name : short
    }

    /// The station's code and short name: `MP 25 นครชัยศรี`, `P1_3 บ้านโป่ง`; a name with no code, its short name.
    static func title(_ s: Monitoring.Station, separator: String = " ") -> String {
        let code = Monitoring.Chart.name(s)
        return code == s.name ? shortName(s) : code + separator + shortName(s)
    }
}

/// The chart itself (Swift Charts): today's power line over the forecast with the gap shaded, or a day's (month's)
/// energy as bars over the forecast's line. Today's alarms are pills in a lane under the plot (CHA-110), clustered
/// when close; a tap lists them.
struct MonitoringChartView: View {
    let chart: Monitoring.Chart
    let split: Bool
    let now: Date
    /// Before sunrise: the forecast only.
    var forecastOnly = false
    /// Each series' colour by id (`MonitoringPage.chartColors`).
    var colors: [String: Color] = [:]
    /// The plot's left and right edges, for the lane's pills.
    @State private var plotX: ClosedRange<CGFloat>?
    @State private var openCluster: String?

    static let palette: [Color] = [Theme.primary, Theme.teal, Theme.warning, Theme.teamPurple, Theme.success, Theme.jobOrange]
    static func color(_ i: Int) -> Color { palette[i % palette.count] }
    static let othersColor = Theme.inkMuted.opacity(0.55)
    static let laneHeight: CGFloat = 48
    /// Lines listed in a pill's popover before `อีก n รายการ`.
    static let listed = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            plot.frame(maxHeight: .infinity)
            if chart.range == .today && !chart.clusters.isEmpty { lane.frame(height: Self.laneHeight) }
        }
    }

    private var plot: some View {
        Chart {
            if chart.range == .today { dayMarks } else { periodMarks }
        }
        .chartXScale(domain: chart.domain)
        .chartXAxis { xAxis }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel().font(.sarabun(11)) } }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let r = proxy.plotFrame.map { geo[$0] } ?? .zero
                Color.clear
                    .onAppear { plotX = r.minX...max(r.maxX, r.minX) }
                    .onChange(of: r) { _, n in plotX = n.minX...max(n.maxX, n.minX) }
            }
        }
        .accessibilityChartDescriptor(MonitoringChartDescriptor(chart: chart))
    }

    private func seriesColor(_ id: String, _ i: Int) -> Color { colors[id] ?? Self.color(i) }

    private var xAxis: some AxisContent {
        AxisMarks(values: chart.range == .today ? .stride(by: .hour, count: 3) : .automatic(desiredCount: 6)) { _ in
            AxisGridLine().foregroundStyle(Theme.hairline)
            if chart.range == .year {
                AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.sarabun(11))
            } else if chart.range == .today {
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits), collisionResolution: .disabled)
                    .font(.sarabun(11))
            } else {
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits)).font(.sarabun(11))
            }
        }
    }

    @ChartContentBuilder private var dayMarks: some ChartContent {
        ForEach(chart.total) { p in
            if !forecastOnly, let a = p.actual, let e = p.expected, e > a {
                AreaMark(x: .value("เวลา", p.x), yStart: .value("ผลิต", a), yEnd: .value("คาด", e))
                    .foregroundStyle(Theme.warningSoft)
            }
            if let e = p.expected {
                LineMark(x: .value("เวลา", p.x), y: .value("kW", e), series: .value("ชุด", "คาด"))
                    .foregroundStyle(Theme.inkMuted).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        if !forecastOnly { actualMarks }
        // each event inside the axis keeps a thin rule; its label is a pill in the lane under the plot
        ForEach(chart.events.filter { chart.domain.contains($0.x) }) { e in
            RuleMark(x: .value("เวลา", e.x))
                .foregroundStyle(e.source == .lost ? Theme.inkMuted : Theme.danger)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
        }
        if chart.domain.contains(now) {
            RuleMark(x: .value("เวลา", now)).foregroundStyle(Theme.navy).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    @ChartContentBuilder private var actualMarks: some ChartContent {
        if split {
            ForEach(Array(chart.series.enumerated()), id: \.element.id) { i, s in
                ForEach(s.points) { p in
                    if let a = p.actual {
                        LineMark(x: .value("เวลา", p.x), y: .value("kW", a), series: .value("ชุด", s.id))
                            .foregroundStyle(seriesColor(s.id, i)).lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                }
            }
        } else {
            ForEach(chart.total) { p in
                if let a = p.actual {
                    LineMark(x: .value("เวลา", p.x), y: .value("kW", a), series: .value("ชุด", "ผลิต"))
                        .foregroundStyle(Theme.primary).lineStyle(StrokeStyle(lineWidth: 2.2))
                }
            }
        }
        if !split, let peak = chart.peak, let v = peak.actual {
            PointMark(x: .value("เวลา", peak.x), y: .value("kW", v)).foregroundStyle(Theme.primary).symbolSize(50)
                .annotation(position: .top) { pin("สูงสุด " + MonFormat.number(v) + " kW · " + MonFormat.time(peak.x)) }
        }
        if !split, let cur = chart.current, let v = cur.actual {
            PointMark(x: .value("เวลา", cur.x), y: .value("kW", v)).foregroundStyle(Theme.primary).symbolSize(50)
                .annotation(position: .trailing) { pin("ตอนนี้ " + MonFormat.number(v) + " kW") }
        }
    }

    @ChartContentBuilder private var periodMarks: some ChartContent {
        if split {
            ForEach(Array(chart.series.enumerated()), id: \.element.id) { i, s in
                ForEach(s.points) { p in
                    if let a = p.actual {
                        BarMark(x: .value("วัน", p.x, unit: chart.range == .year ? .month : .day), y: .value("kWh", a))
                            .foregroundStyle(seriesColor(s.id, i))
                    }
                }
            }
        } else {
            ForEach(chart.total) { p in
                if let a = p.actual {
                    BarMark(x: .value("วัน", p.x, unit: chart.range == .year ? .month : .day), y: .value("kWh", a))
                        .foregroundStyle(Theme.primary.opacity(0.8))
                }
            }
        }
        ForEach(chart.total) { p in
            if let e = p.expected {
                LineMark(x: .value("วัน", p.x, unit: chart.range == .year ? .month : .day), y: .value("kWh", e), series: .value("ชุด", "คาด"))
                    .foregroundStyle(Theme.inkMuted).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
    }

    private func pin(_ text: String) -> some View {
        Text(text).font(.sarabun(11, .bold)).foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.navy, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: the lane

    /// One pill per cluster, under its time on the axis (the early one at the axis' start), never over another.
    private var lane: some View {
        PillLane {
            ForEach(chart.clusters) { c in
                pill(c).layoutValue(key: PillLane.X.self, value: x(of: c))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.chart.events")
    }

    private func x(of c: Monitoring.EventCluster) -> CGFloat {
        guard let px = plotX else { return 0 }
        if c.early { return px.lowerBound }
        let d = chart.domain, span = d.upperBound.timeIntervalSince(d.lowerBound)
        guard span > 0 else { return px.lowerBound }
        let f = min(max(c.x.timeIntervalSince(d.lowerBound) / span, 0), 1)
        return px.lowerBound + CGFloat(f) * (px.upperBound - px.lowerBound)
    }

    /// `09:00 · 2`, `ก่อน 06:00 · 3`, `11:00`.
    static func pillTitle(_ c: Monitoring.EventCluster, axisStart: Date) -> String {
        if c.early { return "ก่อน " + MonFormat.time(axisStart) + " · \(c.events.count)" }
        return MonFormat.time(c.x) + (c.events.count > 1 ? " · \(c.events.count)" : "")
    }

    private func pill(_ c: Monitoring.EventCluster) -> some View {
        let danger = c.events.contains { $0.source != .lost }
        let title = Self.pillTitle(c, axisStart: chart.domain.lowerBound)
        return Button { openCluster = c.id } label: {
            Text(title).font(.sarabun(12, .bold)).foregroundStyle(danger ? Theme.dangerText : Theme.inkStrong)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).frame(height: 26)
                .background(danger ? Theme.dangerSoft : Theme.track, in: Capsule())
                .overlay(Capsule().strokeBorder(danger ? Theme.dangerLine : Theme.borderSubtle))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เหตุการณ์ " + title)
        .popover(isPresented: Binding(get: { openCluster == c.id }, set: { if !$0 { openCluster = nil } })) {
            clusterList(c).presentationCompactAdaptation(.popover)
        }
    }

    /// At most five lines, then `อีก n รายการ · ดูใน ต้องดำเนินการ ›`.
    private func clusterList(_ c: Monitoring.EventCluster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(c.events.prefix(Self.listed)) { e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MonFormat.time(e.x)).font(.sarabun(13, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                    Text(e.label).font(.sarabun(13)).foregroundStyle(e.source == .lost ? Theme.inkStrong : Theme.dangerText)
                        .lineLimit(1)
                }
            }
            if c.events.count > Self.listed {
                Text("อีก \(c.events.count - Self.listed) รายการ · ดูใน ต้องดำเนินการ ›")
                    .font(.sarabun(12, .semibold)).foregroundStyle(Theme.primary)
            }
        }
        .padding(16)
        .frame(minWidth: 260, alignment: .leading)
    }
}

/// The chart's event lane: each pill centred on its `X` where it fits, pushed right of the one before so none
/// covers another, and kept inside the lane.
struct PillLane: Layout {
    struct X: LayoutValueKey { static let defaultValue: CGFloat = 0 }
    static let gap: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var right = bounds.minX
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            var left = bounds.minX + v[X.self] - size.width / 2
            left = max(left, right + (right > bounds.minX ? Self.gap : 0), bounds.minX)
            left = min(left, bounds.maxX - size.width)
            v.place(at: CGPoint(x: left, y: bounds.midY), anchor: .leading, proposal: .unspecified)
            right = left + size.width
        }
    }
}

/// VoiceOver's summary of the power chart (Audio Graphs): the fleet's total, produced and expected, over time.
struct MonitoringChartDescriptor: AXChartDescriptorRepresentable {
    let chart: Monitoring.Chart

    func makeChartDescriptor() -> AXChartDescriptor {
        let pts = chart.total, unit = chart.range == .today ? "kW" : "kWh"
        let xs = pts.map { $0.x.timeIntervalSince1970 }
        let ys = pts.flatMap { [$0.actual, $0.expected].compactMap { $0 } }
        let x = AXNumericDataAxisDescriptor(title: "เวลา", range: (xs.min() ?? 0)...(max(xs.max() ?? 1, (xs.min() ?? 0) + 1)), gridlinePositions: []) {
            Date(timeIntervalSince1970: $0).formatted(chart.range == .today ? .dateTime.hour().minute() : .dateTime.day().month())
        }
        let y = AXNumericDataAxisDescriptor(title: unit, range: 0...max(ys.max() ?? 1, 1), gridlinePositions: []) {
            "\(Int($0.rounded())) \(unit)"
        }
        let produced = AXDataSeriesDescriptor(name: "ผลิตได้", isContinuous: true,
                                              dataPoints: pts.compactMap { p in p.actual.map { .init(x: p.x.timeIntervalSince1970, y: $0) } })
        let expected = AXDataSeriesDescriptor(name: "คาดการณ์", isContinuous: true,
                                              dataPoints: pts.compactMap { p in p.expected.map { .init(x: p.x.timeIntervalSince1970, y: $0) } })
        return AXChartDescriptor(title: "กำลังผลิตรวมทุกสถานี", summary: nil, xAxis: x, yAxis: y, additionalAxes: [],
                                 series: [produced, expected])
    }
}


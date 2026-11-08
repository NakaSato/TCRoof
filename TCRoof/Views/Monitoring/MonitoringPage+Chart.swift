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
        return MonCard {
            VStack(alignment: .leading, spacing: 10) {
                chartHeader(chart, f)
                HStack(alignment: .top, spacing: 14) {
                    MonitoringChartView(chart: chart, split: split, now: f.now).frame(height: 190)
                    chartSummary(chart).frame(width: 150, alignment: .leading)
                }
                if split { stationChips(f) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.chart")
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

    /// `แยกสถานี`: a chip per station; a tap hides or shows its line.
    private func stationChips(_ f: Monitoring.Fleet) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(f.stations.enumerated()), id: \.element.id) { i, s in
                    let on = !hidden.contains(s.id)
                    Button {
                        if on { hidden.insert(s.id) } else { hidden.remove(s.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(on ? MonitoringChartView.color(i) : Theme.track).frame(width: 10, height: 10)
                            Text(Monitoring.Chart.name(s)).font(.sarabun(13, on ? .bold : .regular))
                                .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(on ? Theme.surface : Theme.track, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderSubtle))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(on ? "แสดง" : "ซ่อน")
                }
            }
        }
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
                    Text("เรียงตามพลังงานที่เสีย").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(16)
                if actions.isEmpty {
                    Text("ไม่มีเรื่องต้องดำเนินการ").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(actions) { a in
                        Divider()
                        actionRow(a)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitoring.actions")
    }

    private func actionRow(_ a: Monitoring.Action) -> some View {
        let alarm = a.alarm
        let bar: Color = alarm.source == .growatt ? Theme.danger : alarm.source == .lost ? Theme.danger : Theme.warning
        return Button { opened = a.station } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(Monitoring.Chart.name(a.station)) \(Self.shortName(a.station)) · \(alarm.part)")
                            .font(.sarabun(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                        Text(alarm.label).font(.sarabun(13, .bold))
                            .foregroundStyle(alarm.source == .tcroof ? Theme.warningInk : Theme.dangerText)
                    }
                    Text(actionDetail(a)).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.lossText(alarm.loss)).font(.sarabun(15, .bold)).foregroundStyle(Theme.warningInk).lineLimit(1)
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
    }

    /// `No AC Connection · ตั้งแต่ 09:50 · เกิด 4 ครั้ง`.
    private func actionDetail(_ a: Monitoring.Action) -> String {
        var parts = [a.alarm.detail]
        if a.alarm.source != .lost { parts.append("ตั้งแต่ " + MonFormat.time(a.alarm.since)) }
        if a.occurrences > 1 { parts.append("เกิด \(a.occurrences) ครั้ง") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
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

    /// `นครชัยศรี` of `สถานีผลิตน้ำนครชัยศรี`.
    static func shortName(_ s: Monitoring.Station) -> String {
        let prefix = "สถานีผลิตน้ำ"
        return s.name.hasPrefix(prefix) ? String(s.name.dropFirst(prefix.count)) : s.name
    }
}

/// The chart itself (Swift Charts): today's power line over the forecast with the gap shaded, or a day's (month's)
/// energy as bars over the forecast's line.
struct MonitoringChartView: View {
    let chart: Monitoring.Chart
    let split: Bool
    let now: Date

    static let palette: [Color] = [Theme.primary, Theme.teal, Theme.warning, Theme.teamPurple, Theme.success, Theme.jobOrange]
    static func color(_ i: Int) -> Color { palette[i % palette.count] }

    var body: some View {
        Chart {
            if chart.range == .today { dayMarks } else { periodMarks }
        }
        .chartXScale(domain: chart.domain)
        .chartXAxis { xAxis }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel().font(.sarabun(11)) } }
        .chartLegend(.hidden)
        .accessibilityChartDescriptor(MonitoringChartDescriptor(chart: chart))
    }

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
            if let a = p.actual, let e = p.expected, e > a {
                AreaMark(x: .value("เวลา", p.x), yStart: .value("ผลิต", a), yEnd: .value("คาด", e))
                    .foregroundStyle(Theme.warningSoft)
            }
            if let e = p.expected {
                LineMark(x: .value("เวลา", p.x), y: .value("kW", e), series: .value("ชุด", "คาด"))
                    .foregroundStyle(Theme.inkMuted).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        if split {
            ForEach(Array(chart.series.enumerated()), id: \.element.id) { i, s in
                ForEach(s.points) { p in
                    if let a = p.actual {
                        LineMark(x: .value("เวลา", p.x), y: .value("kW", a), series: .value("ชุด", s.name))
                            .foregroundStyle(Self.color(i)).lineStyle(StrokeStyle(lineWidth: 1.8))
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
        // the labels take turns above and below, so two close together don't cover each other
        ForEach(Array(chart.events.enumerated()), id: \.element.id) { i, e in
            RuleMark(x: .value("เวลา", e.x))
                .foregroundStyle(e.source == .lost ? Theme.inkMuted : Theme.danger)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .annotation(position: i.isMultiple(of: 2) ? .bottom : .top, alignment: .leading, spacing: 0,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    eventLabel(MonFormat.time(e.x) + " " + e.label, danger: e.source != .lost)
                }
        }
        RuleMark(x: .value("เวลา", now)).foregroundStyle(Theme.navy).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
                            .foregroundStyle(Self.color(i))
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

    private func eventLabel(_ text: String, danger: Bool) -> some View {
        Text(text).font(.sarabun(10, .bold)).foregroundStyle(danger ? Theme.dangerText : Theme.inkMuted)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(danger ? Theme.dangerLine : Theme.borderSubtle))
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


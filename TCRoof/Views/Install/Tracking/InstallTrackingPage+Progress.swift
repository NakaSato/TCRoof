import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ความคืบหน้าเทียบแผน` (docs/ui/install-tracking-ipad-v2 §2–3): the Gantt of the MP plan's install tasks over a day
/// (or, past a month, a week) axis, the station's S-curve by day, or the key plan (`InstallTrackingPage+KeyPlan`),
/// behind a `Gantt | S-Curve | Key Plan` switch. The card ends
/// above the dock and its rows scroll inside it under the pinned day header. A task row opens its sheet.
extension InstallTrackingPage {
    enum ProgressView: String { case gantt, curve, keyplan }

    /// The left column of names and the right column of percents, as on the board.
    static let nameWidth: CGFloat = 250
    static let percentWidth: CGFloat = 64
    /// The page's bottom padding: the last cards end above the dock.
    static let dockClearance: CGFloat = 24
    static let stageHeight: CGFloat = 46
    static let subHeight: CGFloat = 31

    /// The card's height on a tab whose first card sits under a 52 pt strip: what is left above the dock.
    var fittedHeight: CGFloat { max(viewport - 14 - 52 - 14 - Self.dockClearance, 440) }

    func progressCard(_ data: InstallPageData, _ g: InstallGantt) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            progressHeader(data, g)
            switch view {
            case .gantt: ganttGrid(g, nonWorking: data.nonWorking)
            case .curve: curvePanel(data)
            case .keyplan: keyPlanPanel(data)
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
        .frame(height: fittedHeight, alignment: .top)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    private func progressHeader(_ data: InstallPageData, _ g: InstallGantt) -> some View {
        let span = g.span()
        let range = span.map { "\(ThaiFormat.dayMonth.string(from: $0.lowerBound)) – \(ThaiFormat.numericDate.string(from: $0.upperBound))" } ?? ""
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ความคืบหน้าเทียบแผน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).frame(height: 24)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    Text([range, "\(g.rows.count) ขั้นตอน", g.subCount > 0 ? "\(g.subCount) งานย่อย" : ""].filter { !$0.isEmpty }.joined(separator: " | "))
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    if let t = data.tracking { forecastPill(t) }
                }
            }
            Spacer(minLength: 8)
            switch view {
            case .gantt: ganttLegend.padding(.top, 10)
            case .curve: curveLegend.padding(.top, 10)
            case .keyplan:
                keyPlanLegend.padding(.top, 10)
                keyPlanChip(keyPlanModel(data)).padding(.top, 8)
            }
            TCCountSegments([.init("Gantt"), .init("S-Curve"), .init("Key Plan")],
                            selection: Binding(get: { Self.views.firstIndex(of: view) ?? 0 }, set: { view = Self.views[$0] }), equalWidths: false)
                .fixedSize()
                .accessibilityLabel("มุมมองความคืบหน้า")
        }
    }

    /// The switch's order.
    static let views: [ProgressView] = [.gantt, .curve, .keyplan]

    /// The forecast end as `6/10`, or `6/10/2570` when it falls in another year than the due date.
    static func forecastDay(_ t: InstallTracking) -> String {
        let f = t.forecastEnd(), cal = Calendar.current
        return cal.component(.year, from: f) == cal.component(.year, from: t.due) ? ThaiFormat.dayMonth.string(from: f) : ThaiFormat.numericDate.string(from: f)
    }

    /// `คาดส่งมอบ 6/10 ตามกำหนด | เผื่อ 1 วัน`, amber with no spare day, red `คาดส่งมอบช้า n วัน` when late.
    private func forecastPill(_ t: InstallTracking) -> some View {
        let slack = t.slackDays(), end = Self.forecastDay(t)
        let (text, tone): (String, InstallPageData.Tone) = slack < 0 ? ("คาดส่งมอบ \(end) | ช้า \(-slack) วัน", .danger)
            : slack == 0 ? ("คาดส่งมอบ \(end) ตามกำหนดพอดี", .warn) : ("คาดส่งมอบ \(end) ตามกำหนด | เผื่อ \(slack) วัน", .ok)
        return Text(text).font(.sarabunFixed(12, .bold)).foregroundStyle(Self.ink(tone)).lineLimit(1)
            .padding(.horizontal, 10).frame(height: 22)
            .background(Self.fill(tone), in: Capsule())
            .fixedSize()
    }

    /// `คาดการณ์` dashed and `เกินแผน` red; the board's `◆ เหตุการณ์สำคัญ` has no milestones to point at.
    private var ganttLegend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Capsule().strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])).frame(width: 18, height: 10)
                Text("คาดการณ์")
            }
            HStack(spacing: 5) {
                Capsule().fill(Theme.danger).frame(width: 18, height: 10)
                Text("เกินแผน")
            }
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    private var curveLegend: some View {
        HStack(spacing: 14) {
            legendLine(Theme.inkFaint, "แผนสะสม")
            legendLine(Theme.primary, "งานจริงสะสม")
            HStack(spacing: 5) {
                Path { p in p.move(to: CGPoint(x: 0, y: 1.5)); p.addLine(to: CGPoint(x: 18, y: 1.5)) }
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3])).frame(width: 18, height: 3)
                Text("คาดการณ์")
            }
            HStack(spacing: 4) {
                Rectangle().fill(Theme.danger).frame(width: 2, height: 14)
                Text("วันนี้").foregroundStyle(Theme.dangerText)
            }
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    private func legendLine(_ c: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(c).frame(width: 18, height: 3)
            Text(title)
        }
    }

    // MARK: Gantt

    private func ganttGrid(_ g: InstallGantt, nonWorking: Set<Date>) -> some View {
        let axis = InstallAxis(g)
        return VStack(spacing: 0) {
            ganttHeader(axis)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(g.rows) { row in
                        stepRow(row, axis: axis)
                        if isExpanded(row) {
                            ForEach(row.subs) { subRow($0, parent: row, axis: axis) }
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
            // Sundays, days off and today's column behind the rows, today's line over them; they don't scroll
            .background(alignment: .topLeading) { axisLayer(axis) { x, w, h in InstallColumns(axis: axis, nonWorking: nonWorking, x: x, width: w, height: h) } }
            .overlay(alignment: .topLeading) { axisLayer(axis) { x, w, h in todayLine(axis, x: x, w: w, h: h) } }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A layer over the bars' column only, given where it starts, its width and height.
    private func axisLayer(_ axis: InstallAxis, @ViewBuilder _ content: @escaping (CGFloat, CGFloat, CGFloat) -> some View) -> some View {
        GeometryReader { geo in
            let w = geo.size.width - Self.nameWidth - Self.percentWidth
            content(Self.nameWidth, w, geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private func todayLine(_ axis: InstallAxis, x: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Path { p in
            // the middle of today's day, in a week column too
            let tx = x + (axis.x(axis.today, w) + axis.xEnd(axis.today, w)) / 2
            p.move(to: CGPoint(x: tx, y: 0))
            p.addLine(to: CGPoint(x: tx, y: h))
        }
        .stroke(Theme.danger, lineWidth: 1.5)
    }

    /// `ขั้นตอน`, then the months over the days (or weeks), Sundays rose and today in a red pill.
    private func ganttHeader(_ axis: InstallAxis) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("ขั้นตอน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                .frame(width: Self.nameWidth, alignment: .leading).padding(.bottom, 6)
            GeometryReader { geo in
                let w = geo.size.width
                ForEach(axis.months, id: \.self) { m in
                    Text(ThaiFormat.monthYear.string(from: m)).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                        .fixedSize().offset(x: axis.x(max(m, axis.start), w) + 4, y: 2)
                }
                ForEach(axis.labelled, id: \.self) { d in
                    let today = axis.unit == .day ? Calendar.current.isDate(d, inSameDayAs: axis.today) : axis.contains(axis.today, week: d)
                    let sunday = axis.unit == .day && InstallPlan.isSunday(d)
                    Text(axis.label(d)).font(.sarabunFixed(12, today ? .bold : .regular))
                        .foregroundStyle(today ? Theme.onPrimary : sunday ? Theme.survey : Theme.inkMuted)
                        .padding(.horizontal, today ? 7 : 0).frame(height: 16)
                        .background { if today { Capsule().fill(Theme.danger) } }
                        .fixedSize()
                        .frame(width: max(axis.columnWidth(w), 1))
                        .offset(x: axis.x(d, w), y: 24)
                }
            }
            .frame(height: InstallAxis.headerHeight)
            Text("%").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                .frame(width: Self.percentWidth, alignment: .trailing).padding(.bottom, 6)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func isExpanded(_ row: InstallGantt.Row) -> Bool {
        !row.subs.isEmpty && ((row.status == .current) != toggled.contains(row.id))
    }

    /// The right column's pill: green done, blue running, grey waiting.
    private func percentPill(_ row: InstallGantt.Row) -> some View {
        let (ink, fill): (Color, Color) = switch row.status {
        case .done: (Theme.successInk, Theme.successSoft)
        case .current: (Theme.onPrimary, Theme.primary)
        case .waiting: (Theme.inkFaint, Theme.segmentTrack)
        }
        return Text("\(Int(row.percent.rounded()))%").font(.sarabunFixed(15, .bold)).foregroundStyle(ink).monospacedDigit()
            .frame(minWidth: 48).padding(.horizontal, 4).frame(height: 24)
            .background(fill, in: Capsule())
    }

    private func stepRow(_ row: InstallGantt.Row, axis: InstallAxis) -> some View {
        let open = isExpanded(row)
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if toggled.contains(row.id) { toggled.remove(row.id) } else { toggled.insert(row.id) }
                } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted).frame(width: 26, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(row.subs.isEmpty ? 0 : 1).disabled(row.subs.isEmpty)
                .accessibilityLabel(open ? "ซ่อนงานย่อย" : "แสดงงานย่อย")
                stepDisc(row)
                VStack(alignment: .leading, spacing: 0) {
                    if row.subs.isEmpty {
                        // the MP plan's long task names get two lines when there is no sub-task count under them
                        Text(row.title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(2).lineSpacing(-2)
                    } else {
                        Text(row.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).frame(height: 21).lineLimit(1).minimumScaleFactor(0.8)
                        Text("งานย่อย \(row.subs.filter { $0.percent >= 99.95 }.count)/\(row.subs.count)")
                            .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).frame(height: 17)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: Self.nameWidth, alignment: .leading)
            GeometryReader { geo in InstallBars(row: row, axis: axis, width: geo.size.width) }
                .frame(height: Self.stageHeight)
            percentPill(row).frame(width: Self.percentWidth, alignment: .trailing)
        }
        .frame(height: Self.stageHeight)
        .background(row.status == .current ? Theme.primary.opacity(0.035) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { stage = row }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.code) \(row.title) | \(Int(row.percent.rounded()))%" + (row.overrunDays > 0 ? " | เกินแผน \(row.overrunDays) วัน" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "เปิดรายละเอียด") { stage = row }
    }

    /// Green ✓ done, a blue number while it runs, a grey number while it waits.
    private func stepDisc(_ row: InstallGantt.Row) -> some View {
        ZStack {
            switch row.status {
            case .done:
                Circle().fill(Theme.success)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.onPrimary)
            case .current:
                Circle().fill(Theme.primary)
                Text(row.code).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.onPrimary).minimumScaleFactor(0.7)
            case .waiting:
                Circle().fill(Theme.segmentTrack)
                Text(row.code).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted).minimumScaleFactor(0.7)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private func subRow(_ s: InstallGantt.Sub, parent: InstallGantt.Row, axis: InstallAxis) -> some View {
        let ink: Color = s.percent >= 99.95 ? Theme.success : s.percent > 0 || parent.status == .current ? Theme.primary : Theme.chevron
        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(ink).frame(width: 8, height: 8)
                Text(s.title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1)
            }
            .padding(.leading, 66)
            .frame(width: Self.nameWidth + 150, alignment: .leading)
            .padding(.trailing, -150)
            .zIndex(1)
            GeometryReader { geo in InstallSubBar(sub: s, parent: parent, axis: axis, width: geo.size.width) }
                .frame(height: Self.subHeight)
            Text("\(Int(s.percent.rounded()))%").font(.sarabunFixed(14, .bold)).foregroundStyle(s.percent >= 99.95 ? Theme.successInk : Theme.inkFaint)
                .monospacedDigit().frame(width: Self.percentWidth, alignment: .trailing)
        }
        .frame(height: Self.subHeight)
        // a rule under the stage's disc ties the sub-tasks to it
        .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSubtle).frame(width: 1).padding(.leading, 48) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: S-curve

    @ViewBuilder private func curvePanel(_ data: InstallPageData) -> some View {
        if data.curveDays.contains(where: { $0.actual != nil || $0.planned > 0 }) {
            VStack(alignment: .leading, spacing: 6) {
                InstallCurveChart(days: data.curveDays, today: data.gantt?.today ?? .now, forecastEnd: data.tracking?.forecastEnd(),
                                  nonWorking: data.nonWorking, waitLabel: data.waitLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel("S-curve แผนสะสมเทียบงานจริงสะสมรายวัน")
                    .accessibilityValue(curveSummary(data))
                HStack(spacing: 18) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.ganttTrack).frame(width: 10, height: 12)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.primary.opacity(0.55)).frame(width: 10, height: 12)
                        Text("แท่ง = งานต่อวัน (แผน | จริง)")
                    }
                    Text("เส้นแดงที่วันนี้ = ห่างจากแผน")
                }
                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                .padding(.leading, 48)
                .accessibilityHidden(true)
            }
            .padding(.top, 4)
        } else {
            Text("ยังไม่มีแผน MP").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func curveSummary(_ data: InstallPageData) -> String {
        guard let t = data.tracking else { return "" }
        let late = t.slackDays()
        return "แผน \(Int(t.planned.rounded()))% จริง \(Int(t.actual.rounded()))% | คาดเสร็จ \(ThaiFormat.numericDate.string(from: t.forecastEnd()))"
            + (late < 0 ? " ช้า \(-late) วัน" : "")
    }
}

/// The columns behind the Gantt's rows: Sundays tinted, days off and waiting days hatched, today tinted red.
struct InstallColumns: View {
    let axis: InstallAxis
    let nonWorking: Set<Date>
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if axis.unit == .day {
                ForEach(axis.columns, id: \.self) { d in
                    let cw = axis.columnWidth(width)
                    if nonWorking.contains(d) {
                        InstallHatch(ink: Theme.installWait, line: 6).frame(width: cw, height: height).offset(x: x + axis.x(d, width))
                    } else if InstallPlan.isSunday(d) {
                        Theme.installSunday.frame(width: cw, height: height).offset(x: x + axis.x(d, width))
                    }
                }
            }
            let tx = axis.x(axis.today, width), te = axis.xEnd(axis.today, width)
            Theme.installCritical.opacity(0.06).frame(width: max(te - tx, 1), height: height).offset(x: x + tx)
        }
        .frame(width: x + width, height: height, alignment: .topLeading)
    }
}

// MARK: - axis

/// The Gantt's time axis: one column a day, or a week (from Sunday, as the MP plan) when the span passes two months.
struct InstallAxis {
    enum Unit { case day, week }

    static let headerHeight: CGFloat = 46

    let start: Date
    let end: Date
    let today: Date
    let unit: Unit
    /// The first day of each column.
    let columns: [Date]

    /// `dayLimit`: the longest span still drawn a day a column (the iPhone keeps a month, its columns scroll).
    init(_ g: InstallGantt, dayLimit: Int = 62, forecast: InstallPlan? = nil) {
        let cal = MasterSchedule.calendar
        let original = g.span(calendar: cal) ?? g.today...g.today
        let span = min(original.lowerBound, forecast?.start ?? original.lowerBound)...max(original.upperBound, forecast?.end ?? original.upperBound)
        let days = (cal.dateComponents([.day], from: span.lowerBound, to: span.upperBound).day ?? 0) + 1
        // a day a column up to two months (the board's weekends and today's column read), a week past that
        unit = days > dayLimit ? .week : .day
        today = cal.startOfDay(for: g.today)
        if unit == .day {
            start = span.lowerBound
            end = span.upperBound
            columns = (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: span.lowerBound) }
        } else {
            let first = MasterSchedule.weekStart(span.lowerBound, calendar: cal), last = MasterSchedule.weekStart(span.upperBound, calendar: cal)
            start = first
            end = cal.date(byAdding: .day, value: 6, to: last) ?? last
            columns = MasterSchedule.weeks(from: first, to: last, calendar: cal)
        }
    }

    var dayCount: Int { (MasterSchedule.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }

    func columnWidth(_ width: CGFloat) -> CGFloat { width / CGFloat(max(columns.count, 1)) }

    /// Where a day begins along `width`.
    func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        let cal = MasterSchedule.calendar
        let d = CGFloat(cal.dateComponents([.day], from: start, to: cal.startOfDay(for: date)).day ?? 0)
        return width * d / CGFloat(max(dayCount, 1))
    }

    /// Where a day ends along `width`.
    func xEnd(_ date: Date, _ width: CGFloat) -> CGFloat { x(date, width) + width / CGFloat(max(dayCount, 1)) }

    func contains(_ day: Date, week: Date) -> Bool {
        let end = MasterSchedule.calendar.date(byAdding: .day, value: 6, to: week) ?? week
        return day >= week && day <= end
    }

    /// Each month that starts inside the axis, and the axis's own first month.
    var months: [Date] {
        let cal = MasterSchedule.calendar
        var out = [start]
        var m = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        while let next = cal.date(byAdding: .month, value: 1, to: m), next <= end { out.append(next); m = next }
        return out
    }

    /// The columns that get a label: all of them up to 16, else every second, third … so about 16 show.
    var labelled: [Date] {
        let step = max(1, Int((Double(columns.count) / 16).rounded(.up)))
        return columns.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }

    /// `24 พฤ` a day, `4/10` a week.
    func label(_ d: Date) -> String {
        unit == .day ? "\(MasterSchedule.calendar.component(.day, from: d)) " + Self.weekday.string(from: d) : ThaiFormat.dayMonth.string(from: d)
    }

    /// `พฤ`, `อา`: a day's short Thai name.
    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = ThaiFormat.locale
        f.dateFormat = "EEEEE"
        return f
    }()
}

/// A step row's capsules: the plan as a light 24 pt track, the actual over it (green when done; while it runs, blue to
/// its percent of the plan), the forecast dashed, and the days past the plan red with `+n วัน`.
struct InstallBars: View {
    /// Room kept for the `+n วัน` tag at the axis's end.
    static let overrunTag: CGFloat = 76
    let row: InstallGantt.Row
    let axis: InstallAxis
    let width: CGFloat

    var body: some View {
        let x0 = axis.x(row.start, width) + 3, x1 = axis.xEnd(row.end, width) - 3
        let plan = max(x1 - x0, 8)
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.segmentTrack).overlay(Capsule().strokeBorder(Theme.borderSubtle))
                .frame(width: plan, height: 24).offset(x: x0)
            switch row.status {
            case .done:
                if let a = row.actualStart, let b = row.actualEnd {
                    let ax = max(axis.x(a, width) + 7, x0 + 4), bx = min(axis.xEnd(b, width) - 7, x1 - 4)
                    Capsule().fill(Theme.success).frame(width: max(bx - ax, 6), height: 16).offset(x: ax)
                }
            case .current:
                let inner = max(plan - 8, 6), share = CGFloat(min(max(row.percent, 0), 100)) / 100
                Capsule().fill(Theme.primary.opacity(0.14)).frame(width: inner, height: 16)
                    .overlay(alignment: .leading) { if share > 0 { Capsule().fill(Theme.primary).frame(width: max(inner * share, 6)) } }
                    .offset(x: x0 + 4)
            case .waiting:
                EmptyView()
            }
            if row.overrunDays > 0, row.status != .done || (row.actualEnd.map { $0 > row.end } ?? false) {
                let ox = x1 + 7, oend = min(x1 + width * CGFloat(row.overrunDays) / CGFloat(max(axis.dayCount, 1)) - 4, width - 2)
                Group {
                    if row.status == .done { Capsule().fill(Theme.danger) } else { InstallHatch(ink: Theme.danger).clipShape(Capsule()) }
                }
                .frame(width: max(oend - ox, 10), height: 16).offset(x: ox)
                // after the bar, or over its end when that would run past the axis into the % column
                Text("+\(row.overrunDays) วัน").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.dangerText).fixedSize()
                    .padding(.horizontal, 8).frame(height: 22).background(Theme.dangerSoft, in: Capsule())
                    .offset(x: min(max(oend - ox, 10) + ox + 8, width - Self.overrunTag))
            } else if let f = row.forecastEnd, row.status == .current, f > row.end {
                let fx = axis.xEnd(f, width) - 3
                Capsule().strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .background(Theme.primary.opacity(0.06), in: Capsule())
                    .frame(width: max(fx - x1 - 6, 10), height: 24).offset(x: x1 + 6)
            }
        }
        .frame(width: width, height: InstallTrackingPage.stageHeight, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// A sub-row's thin bar: its own days, or its task's when it has none, filled to its percent.
struct InstallSubBar: View {
    let sub: InstallGantt.Sub
    let parent: InstallGantt.Row
    let axis: InstallAxis
    let width: CGFloat

    var body: some View {
        let x0 = axis.x(sub.start ?? parent.start, width), x1 = axis.xEnd(sub.end ?? parent.end, width)
        let w = max(x1 - x0 - 8, 4)
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.ganttTrack).frame(width: w, height: 8)
            Capsule().fill(sub.percent >= 99.95 ? Theme.success : Theme.primary).frame(width: w * CGFloat(min(max(sub.percent, 0), 100)) / 100, height: 8)
        }
        .offset(x: x0 + 4)
        .frame(width: width, height: InstallTrackingPage.subHeight, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Diagonal stripes, for days past the plan and days off.
struct InstallHatch: View {
    let ink: Color
    var line: CGFloat = 2.5

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += max(6, line * 2)
            }
            ctx.stroke(p, with: .color(ink), lineWidth: line)
        }
    }
}

/// The station's S-curve by day (docs/ui/install-tracking-ipad-v2 §3): each day's planned and actual work as bars
/// (×3 so they read), the cumulative plan and actual over filled areas, today's column with its pill and the red gap
/// between plan and actual, the forecast dashed to its end dot at 100 %, and the hatched days off.
struct InstallCurveChart: View {
    let days: [InstallPageData.CurveDay]
    let today: Date
    let forecastEnd: Date?
    let nonWorking: Set<Date>
    let waitLabel: String?
    /// iPhone: the forecast's label goes under the plot, clear of today's tag (docs/ui/install-tracking-iphone state 03).
    var compact = false

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = ThaiFormat.locale
        f.calendar = MasterSchedule.calendar
        f.timeZone = MasterSchedule.calendar.timeZone
        f.dateFormat = "EEEEE"
        return f
    }()

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
    }

    private func label(_ s: String, _ c: Color, size: CGFloat = 12, bold: Bool = false) -> Text {
        Text(s).font(.sarabunFixed(size, bold ? .bold : .regular)).foregroundColor(c)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let cal = MasterSchedule.calendar
        guard !days.isEmpty else { return }
        let day0 = cal.startOfDay(for: today)
        // the axis runs to the forecast end when it falls past the plan
        var axis = days.map(\.date)
        if let f = forecastEnd.map(cal.startOfDay(for:)), let last = axis.last, f > last {
            var d = last
            while d < f, let n = cal.date(byAdding: .day, value: 1, to: d) { axis.append(n); d = n }
        }
        let left: CGFloat = 48, right = size.width - 12, top: CGFloat = 26, bottom = size.height - (compact ? 52 : 30)
        let n = CGFloat(max(axis.count, 1)), cw = (right - left) / n
        func index(_ d: Date) -> Int? { axis.firstIndex { cal.isDate($0, inSameDayAs: d) } }
        func xs(_ i: Int) -> CGFloat { left + cw * CGFloat(i) }
        func y(_ p: Double) -> CGFloat { bottom - CGFloat(min(max(p, 0), 100)) / 100 * (bottom - top) }

        // columns: Sundays, days off hatched (with what they wait on), today
        var waitRun: [Int] = []
        for (i, d) in axis.enumerated() {
            let r = CGRect(x: xs(i), y: top, width: cw, height: bottom - top)
            if nonWorking.contains(d) {
                waitRun.append(i)
                ctx.drawLayer { l in
                    l.clip(to: Path(r))
                    var p = Path(), x = r.minX - r.height
                    while x < r.maxX { p.move(to: CGPoint(x: x, y: r.maxY)); p.addLine(to: CGPoint(x: x + r.height, y: r.minY)); x += 12 }
                    l.stroke(p, with: .color(Theme.installWait), lineWidth: 6)
                }
            } else if InstallPlan.isSunday(d) {
                ctx.fill(Path(r), with: .color(Theme.installSunday))
            }
        }
        if let w = waitLabel, let a = waitRun.first, let b = waitRun.last {
            ctx.draw(label(w, Theme.inkMuted), at: CGPoint(x: (xs(a) + xs(b + 1)) / 2, y: bottom - 10), anchor: .center)
        }
        let ti = index(day0)
        if let ti {
            ctx.fill(Path(CGRect(x: xs(ti), y: top, width: cw, height: bottom - top)), with: .color(Theme.installCritical.opacity(0.06)))
        }
        // grid and Y labels
        for p in stride(from: 0.0, through: 100, by: 25) {
            var g = Path()
            g.move(to: CGPoint(x: left, y: y(p))); g.addLine(to: CGPoint(x: right, y: y(p)))
            ctx.stroke(g, with: .color(Theme.hairline), style: StrokeStyle(lineWidth: 1, dash: p == 0 ? [] : [4, 4]))
            ctx.draw(label("\(Int(p))%", Theme.inkFaint), at: CGPoint(x: left - 10, y: y(p)), anchor: .trailing)
        }
        var axisLine = Path()
        axisLine.move(to: CGPoint(x: left, y: top - 6)); axisLine.addLine(to: CGPoint(x: left, y: bottom))
        ctx.stroke(axisLine, with: .color(Theme.borderSubtle), lineWidth: 1)

        // each day's work, plan grey and actual blue side by side: ×3 so a day's work reads, less when the MP plan's
        // weekly booking lands a week's work on one day
        let bw = min(cw * 0.26, 18)
        let incs = days.indices.flatMap { i -> [Double] in
            let prev = i > 0 ? days[i - 1] : nil
            return [days[i].planned - (prev?.planned ?? 0), (days[i].actual ?? 0) - (prev?.actual ?? 0)]
        }
        let scale = min(3, 40 / max(incs.max() ?? 1, 1))
        for (i, d) in days.enumerated() {
            let prev = i > 0 ? days[i - 1] : nil
            let pInc = d.planned - (prev?.planned ?? 0)
            if pInc > 0 {
                let h = (bottom - top) * CGFloat(min(pInc * scale, 100)) / 100
                ctx.fill(Path(roundedRect: CGRect(x: xs(i) + cw / 2 - bw - 1, y: bottom - h, width: bw, height: h), cornerRadius: 2), with: .color(Theme.ganttTrack))
            }
            if let a = d.actual {
                let inc = a - (prev?.actual ?? 0)
                if inc > 0 {
                    let h = (bottom - top) * CGFloat(min(inc * scale, 100)) / 100
                    ctx.fill(Path(roundedRect: CGRect(x: xs(i) + cw / 2 + 1, y: bottom - h, width: bw, height: h), cornerRadius: 2),
                             with: .color(Theme.primary.opacity(0.55)))
                }
            }
        }

        // the cumulative lines: from 0 at the first day's start to each day's end
        func points(_ v: [Double]) -> [CGPoint] { [CGPoint(x: left, y: y(0))] + v.enumerated().map { CGPoint(x: xs($0.offset + 1), y: y($0.element)) } }
        func line(_ pts: [CGPoint]) -> Path { var p = Path(); p.addLines(pts); return p }
        func area(_ pts: [CGPoint]) -> Path {
            var p = line(pts)
            if let last = pts.last { p.addLine(to: CGPoint(x: last.x, y: bottom)); p.addLine(to: CGPoint(x: left, y: bottom)); p.closeSubpath() }
            return p
        }
        let plan = points(days.map(\.planned))
        let actual = points(days.compactMap(\.actual))
        ctx.fill(area(plan), with: .color(Theme.inkFaint.opacity(0.10)))
        ctx.fill(area(actual), with: .linearGradient(Gradient(colors: [Theme.primary.opacity(0.30), Theme.primary.opacity(0.06)]),
                                                     startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
        ctx.stroke(line(plan), with: .color(Theme.inkFaint), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        ctx.stroke(line(actual), with: .color(Theme.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        // today: the line, its pill, the gap to plan and the two figures
        if let ti, let t = days.indices.contains(ti) ? days[ti] : nil {
            let tx = xs(ti + 1)
            var tl = Path(); tl.move(to: CGPoint(x: tx, y: top)); tl.addLine(to: CGPoint(x: tx, y: bottom))
            ctx.stroke(tl, with: .color(Theme.danger), lineWidth: 1.5)
            let pill = ctx.resolve(label("วันนี้ " + ThaiFormat.dayMonth.string(from: day0), Theme.onPrimary, size: 13, bold: true))
            let ps = pill.measure(in: size)
            let pr = CGRect(x: tx - ps.width / 2 - 9, y: top - 22, width: ps.width + 18, height: 20)
            ctx.fill(Path(roundedRect: pr, cornerRadius: 10), with: .color(Theme.danger))
            ctx.draw(pill, at: CGPoint(x: pr.midX, y: pr.midY), anchor: .center)
            let done = t.actual ?? days[..<ti].last { $0.actual != nil }?.actual ?? 0
            var gap = Path(); gap.move(to: CGPoint(x: tx, y: y(t.planned))); gap.addLine(to: CGPoint(x: tx, y: y(done)))
            ctx.stroke(gap, with: .color(Theme.danger), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for (v, c) in [(t.planned, Theme.inkFaint), (done, Theme.primary)] {
                let r = CGRect(x: tx - 5, y: y(v) - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: r), with: .color(c))
                ctx.stroke(Path(ellipseIn: r), with: .color(Theme.surface), lineWidth: 2)
            }
            ctx.draw(label("แผน \(Int(t.planned.rounded()))%", Theme.inkMuted, size: 14, bold: true), at: CGPoint(x: tx - 10, y: max(y(max(t.planned, done)) - 14, top + 12)), anchor: .trailing)
            ctx.draw(label("จริง \(Int(done.rounded()))%", Theme.primary, size: 14, bold: true), at: CGPoint(x: tx + 10, y: y(min(t.planned, done)) + 14), anchor: .leading)
            // the forecast from today's actual to 100 % on its end day
            if let f = forecastEnd.map(cal.startOfDay(for:)), let fi = index(f), done < 100 {
                let end = CGPoint(x: xs(fi + 1), y: y(100))
                var fp = Path(); fp.move(to: CGPoint(x: tx, y: y(done))); fp.addLine(to: end)
                ctx.stroke(fp, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))
                let dot = CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)
                ctx.fill(Path(ellipseIn: dot), with: .color(Theme.surface))
                ctx.stroke(Path(ellipseIn: dot), with: .color(Theme.primary), lineWidth: 2.5)
                ctx.draw(label("คาดเสร็จ \(ThaiFormat.dayMonth.string(from: f)) | 100%", Theme.primary, size: 14, bold: true),
                         at: compact ? CGPoint(x: right, y: bottom + 40) : CGPoint(x: end.x - 12, y: end.y), anchor: .trailing)
            }
        }

        // X labels: every day, or every other past 20; Sundays rose, today bold red
        let step = axis.count > 40 ? 7 : axis.count > 20 ? 2 : 1
        for (i, d) in axis.enumerated() where i % step == 0 || i == ti {
            let isToday = i == ti
            let text = "\(cal.component(.day, from: d)) " + Self.weekday.string(from: d)
            ctx.draw(label(text, isToday ? Theme.dangerText : InstallPlan.isSunday(d) ? Theme.survey : Theme.inkMuted, size: 13, bold: isToday),
                     at: CGPoint(x: xs(i) + cw / 2, y: bottom + 16), anchor: .center)
        }
    }
}

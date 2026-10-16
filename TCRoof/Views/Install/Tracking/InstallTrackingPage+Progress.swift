import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ความคืบหน้าเทียบแผน` (docs/ui/install-tracking-ipad §B): the Gantt of the MP plan's install tasks over a day (or,
/// past a month, a week) axis, or the station's S-curve, behind a `Gantt | S-Curve` switch. A task row opens its sheet.
extension InstallTrackingPage {
    enum ProgressView: String { case gantt, curve }

    /// The left column of names and the right column of percents, as on the board.
    static let nameWidth: CGFloat = 250
    static let percentWidth: CGFloat = 64

    func progressCard(_ data: InstallPageData, _ g: InstallGantt) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            progressHeader(g)
            if view == .gantt { ganttGrid(g, nonWorking: data.nonWorking) } else { curvePanel(data) }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    private func progressHeader(_ g: InstallGantt) -> some View {
        let span = g.span()
        let range = span.map { "\(ThaiFormat.dayMonth.string(from: $0.lowerBound)) – \(ThaiFormat.numericDate.string(from: $0.upperBound))" } ?? ""
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ความคืบหน้าเทียบแผน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).frame(height: 24)
                    .accessibilityAddTraits(.isHeader)
                Text([range, "\(g.rows.count) ขั้นตอน", g.subCount > 0 ? "\(g.subCount) งานย่อย" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            if view == .gantt { legend.padding(.top, 10) }
            TCCountSegments([.init("Gantt"), .init("S-Curve")],
                            selection: Binding(get: { view == .gantt ? 0 : 1 }, set: { view = $0 == 0 ? .gantt : .curve }), equalWidths: false)
                .fixedSize()
                .accessibilityLabel("มุมมองความคืบหน้า")
        }
    }

    /// `คาดการณ์` dashed and `เกินแผน` red; the board's `◆ เหตุการณ์สำคัญ` has no milestones to point at.
    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])).frame(width: 18, height: 10)
                Text("คาดการณ์")
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.danger).frame(width: 18, height: 10)
                Text("เกินแผน")
            }
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    // MARK: Gantt

    private func ganttGrid(_ g: InstallGantt, nonWorking: Set<Date>) -> some View {
        let axis = InstallAxis(g)
        return VStack(spacing: 0) {
            ganttHeader(axis)
            ForEach(g.rows) { row in
                stepRow(row, axis: axis)
                if isExpanded(row) {
                    ForEach(row.subs) { subRow($0, parent: row, axis: axis) }
                }
            }
        }
        // weekends and holidays hatched, and today's dashed line, behind and over the rows
        .background(alignment: .topLeading) { axisLayer(axis) { x, w, h in nonWorkingHatch(axis, nonWorking, x: x, w: w, h: h) } }
        .overlay(alignment: .topLeading) { axisLayer(axis) { x, w, h in todayLine(axis, x: x, w: w, h: h) } }
    }

    /// A layer over the bars' column only, given where it starts, its width and height.
    private func axisLayer(_ axis: InstallAxis, @ViewBuilder _ content: @escaping (CGFloat, CGFloat, CGFloat) -> some View) -> some View {
        GeometryReader { geo in
            let w = geo.size.width - Self.nameWidth - Self.percentWidth
            content(Self.nameWidth, w, geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private func nonWorkingHatch(_ axis: InstallAxis, _ days: Set<Date>, x: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if axis.unit == .day {
                ForEach(axis.columns.filter { days.contains($0) }, id: \.self) { d in
                    InstallHatch(ink: Theme.inkFaint.opacity(0.25))
                        .frame(width: axis.columnWidth(w), height: max(h - InstallAxis.headerHeight, 0))
                        .offset(x: x + axis.x(d, w), y: InstallAxis.headerHeight)
                }
            }
        }
    }

    private func todayLine(_ axis: InstallAxis, x: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Path { p in
            // the middle of today's day, in a week column too
            let tx = x + (axis.x(axis.today, w) + axis.xEnd(axis.today, w)) / 2
            p.move(to: CGPoint(x: tx, y: InstallAxis.headerHeight - 4))
            p.addLine(to: CGPoint(x: tx, y: h))
        }
        .stroke(Theme.danger, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    /// `ขั้นตอน`, then the months over the days (or weeks), today in a red pill.
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
                    Text(axis.label(d)).font(.sarabunFixed(12, today ? .bold : .regular))
                        .foregroundStyle(today ? Theme.onPrimary : Theme.inkMuted)
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

    private func percentInk(_ status: InstallGantt.Status) -> Color {
        switch status {
        case .done: Theme.successInk
        case .current: Theme.primary
        case .waiting: Theme.inkMuted
        }
    }

    private func stepRow(_ row: InstallGantt.Row, axis: InstallAxis) -> some View {
        let open = isExpanded(row)
        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    if toggled.contains(row.id) { toggled.remove(row.id) } else { toggled.insert(row.id) }
                } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted).frame(width: 30, height: 44).contentShape(Rectangle())
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
                        Text(row.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).frame(height: 21).lineLimit(1)
                        Text("งานย่อย \(row.subs.filter { $0.percent >= 99.95 }.count)/\(row.subs.count)")
                            .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).frame(height: 17)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: Self.nameWidth, alignment: .leading)
            GeometryReader { geo in InstallBars(row: row, axis: axis, width: geo.size.width) }
                .frame(height: 48)
            Text("\(Int(row.percent.rounded()))%").font(.sarabunFixed(18, .bold)).foregroundStyle(percentInk(row.status)).monospacedDigit()
                .frame(width: Self.percentWidth, alignment: .trailing)
        }
        .frame(height: 48)
        .background(row.status == .current ? Theme.primarySoft.opacity(0.35) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { stage = row }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.code) \(row.title) · \(Int(row.percent.rounded()))%" + (row.overrunDays > 0 ? " · เกินแผน \(row.overrunDays) วัน" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "เปิดรายละเอียด") { stage = row }
    }

    /// Green ✓ done, a blue number while it runs, a grey number while it waits.
    private func stepDisc(_ row: InstallGantt.Row) -> some View {
        ZStack {
            switch row.status {
            case .done:
                Circle().fill(Theme.success)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.onPrimary)
            case .current:
                Circle().fill(Theme.primary)
                Text(row.code).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.onPrimary).minimumScaleFactor(0.7)
            case .waiting:
                Circle().fill(Theme.hairline)
                Text(row.code).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted).minimumScaleFactor(0.7)
            }
        }
        .frame(width: 30, height: 30)
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
                .frame(height: 31)
            Text("\(Int(s.percent.rounded()))%").font(.sarabunFixed(15, .bold)).foregroundStyle(s.percent >= 99.95 ? Theme.successInk : Theme.inkMuted)
                .monospacedDigit().frame(width: Self.percentWidth, alignment: .trailing)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: S-curve

    private func curvePanel(_ data: InstallPageData) -> some View {
        HStack(alignment: .top, spacing: 18) {
            if let t = data.tracking { curveSummary(t) }
            if let curve = data.curve, !curve.weeks.isEmpty {
                InstallCurveChart(curve: curve, today: data.gantt?.today ?? .now, forecastEnd: data.tracking?.forecastEnd())
                    .frame(height: 340)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel("S-curve แผนสะสมเทียบงานจริงสะสม")
            } else {
                Text("ยังไม่มีแผน MP").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(.top, 4)
    }

    private func curveSummary(_ t: InstallTracking) -> some View {
        let late = t.slackDays()
        return VStack(alignment: .leading, spacing: 10) {
            summaryBlock("แผนสะสม ณ วันนี้", "\(Int(t.planned.rounded()))%", Theme.inkMuted)
            summaryBlock("งานจริงสะสม", "\(Int(t.actual.rounded()))%", Theme.primary)
            summaryBlock("ต่างจากแผน", (t.variance > 0 ? "+" : "") + "\(t.variance)%",
                         t.schedule == .behind ? Theme.dangerText : Theme.successInk)
            summaryBlock("คาดเสร็จงานติดตั้ง", ThaiFormat.numericDate.string(from: t.forecastEnd()), late < 0 ? Theme.dangerText : Theme.navy,
                         note: late < 0 ? "ช้า \(-late) วัน" : "ตามกำหนด")
        }
        .frame(width: 210, alignment: .leading)
    }

    private func summaryBlock(_ label: String, _ value: String, _ ink: Color, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.sarabunFixed(24, .bold)).foregroundStyle(ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let note { Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.stripFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.track))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - axis

/// The Gantt's time axis: one column a day, or a week (from Sunday, as the MP plan) when the span passes a month.
struct InstallAxis {
    enum Unit { case day, week }

    static let headerHeight: CGFloat = 46

    let start: Date
    let end: Date
    let today: Date
    let unit: Unit
    /// The first day of each column.
    let columns: [Date]

    init(_ g: InstallGantt) {
        let cal = MasterSchedule.calendar
        let span = g.span(calendar: cal) ?? g.today...g.today
        let days = (cal.dateComponents([.day], from: span.lowerBound, to: span.upperBound).day ?? 0) + 1
        unit = days > 31 ? .week : .day
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

    /// The columns that get a label: all of them, or every other past 16.
    var labelled: [Date] {
        let step = columns.count > 16 ? 2 : 1
        return columns.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }

    /// `24 พฤ` a day, `4/10` a week.
    func label(_ d: Date) -> String {
        unit == .day ? "\(MasterSchedule.calendar.component(.day, from: d)) " + Self.weekday.string(from: d) : ThaiFormat.dayMonth.string(from: d)
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = ThaiFormat.locale
        f.dateFormat = "EEEEE"
        return f
    }()
}

/// A step row's bars: the plan in light grey, the actual green (done) or blue (to today), the forecast dashed, and the
/// days past the plan red and hatched with `+n วัน`.
struct InstallBars: View {
    let row: InstallGantt.Row
    let axis: InstallAxis
    let width: CGFloat

    var body: some View {
        let x0 = axis.x(row.start, width), x1 = axis.xEnd(row.end, width)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(Theme.ganttTrack).frame(width: max(x1 - x0, 4), height: 20).offset(x: x0)
            if let a = row.actualStart, let b = row.actualEnd {
                let ax = axis.x(a, width)
                // a running task fills to the middle of today
                let bx = row.status == .current ? (axis.x(b, width) + axis.xEnd(b, width)) / 2 : axis.xEnd(b, width)
                RoundedRectangle(cornerRadius: 5).fill(row.status == .done ? Theme.success : Theme.primary)
                    .frame(width: max(min(bx, x1) - ax, 3), height: 14).offset(x: ax + 0)
            }
            if row.overrunDays > 0, row.status != .done || (row.actualEnd.map { $0 > row.end } ?? false) {
                let ox = x1 + 4, oend = x1 + width * CGFloat(row.overrunDays) / CGFloat(max(axis.dayCount, 1))
                InstallHatch(ink: Theme.danger).frame(width: max(oend - ox, 6), height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3)).offset(x: ox)
                Text("+\(row.overrunDays) วัน").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.dangerText).fixedSize()
                    .offset(x: oend + 6)
            } else if let f = row.forecastEnd, row.status == .current, f > (row.actualEnd ?? row.start) {
                let fx = axis.xEnd(f, width), sx = (axis.x(row.actualEnd ?? row.start, width) + axis.xEnd(row.actualEnd ?? row.start, width)) / 2
                RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: max(fx - sx, 6), height: 18).offset(x: sx)
            }
        }
        .frame(width: width, height: 48, alignment: .leading)
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
        .frame(width: width, height: 31, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Diagonal stripes, for days past the plan and days off.
struct InstallHatch: View {
    let ink: Color

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            ctx.stroke(p, with: .color(ink), lineWidth: 2.5)
        }
    }
}

/// The station's S-curve: cumulative plan (grey dashed), actual (blue, to this week), and the forecast (blue dashed)
/// from today to the forecast end at 100 %. Today's red line with `แผน x%` / `จริง y%` beside it, past the plan's last
/// week too.
struct InstallCurveChart: View {
    let curve: PWAPlan.Curve
    let today: Date
    let forecastEnd: Date?

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 40, right = size.width - 8, top: CGFloat = 8, bottom = size.height - 24
            let first = curve.weeks.first ?? .now
            let lastWeek = max(CGFloat(curve.weeks.count - 1), 1)
            let forecastWeek = forecastEnd.map { CGFloat($0.timeIntervalSince(first) / (7 * 86_400)) } ?? 0
            let todayWeek = CGFloat(today.timeIntervalSince(first) / (7 * 86_400))
            let span = max(lastWeek, forecastWeek, todayWeek)
            func x(_ w: CGFloat) -> CGFloat { left + w / span * (right - left) }
            func y(_ p: Double) -> CGFloat { bottom - CGFloat(min(max(p, 0), 100)) / 100 * (bottom - top) }
            func label(_ s: String, _ c: Color, bold: Bool = false) -> Text { Text(s).font(.sarabunFixed(12, bold ? .bold : .regular)).foregroundColor(c) }
            func line(_ v: [Double]) -> Path {
                var p = Path()
                for (i, value) in v.enumerated() {
                    let pt = CGPoint(x: x(CGFloat(i)), y: y(value))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }
            for p in stride(from: 0.0, through: 100, by: 25) {
                var g = Path()
                g.move(to: CGPoint(x: left, y: y(p))); g.addLine(to: CGPoint(x: right, y: y(p)))
                ctx.stroke(g, with: .color(Theme.hairline), lineWidth: 1)
                ctx.draw(label("\(Int(p))%", Theme.inkFaint), at: CGPoint(x: 0, y: y(p)), anchor: .leading)
            }
            ctx.stroke(line(curve.plan), with: .color(Theme.inkFaint), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            ctx.stroke(line(curve.actual), with: .color(Theme.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            if todayWeek >= 0 {
                let tx = x(min(todayWeek, span))
                // the actual stops at its last week; past it the work stood still until today
                let lastActual = CGFloat(max(curve.actual.count - 1, 0))
                if todayWeek > lastActual, curve.todayIndex == nil {
                    var flat = Path()
                    flat.move(to: CGPoint(x: x(lastActual), y: y(curve.done))); flat.addLine(to: CGPoint(x: tx, y: y(curve.done)))
                    ctx.stroke(flat, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                if forecastWeek > todayWeek, curve.done < 100 {
                    var f = Path()
                    f.move(to: CGPoint(x: tx, y: y(curve.done))); f.addLine(to: CGPoint(x: x(forecastWeek), y: y(100)))
                    ctx.stroke(f, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                var t = Path()
                t.move(to: CGPoint(x: tx, y: top)); t.addLine(to: CGPoint(x: tx, y: bottom))
                ctx.stroke(t, with: .color(Theme.danger), lineWidth: 1.5)
                ctx.draw(label("แผน \(Int(curve.planned.rounded()))%", Theme.inkMuted, bold: true), at: CGPoint(x: tx + 8, y: max(y(curve.planned) - 12, top + 10)), anchor: .leading)
                ctx.draw(label("จริง \(Int(curve.done.rounded()))%", Theme.primary, bold: true), at: CGPoint(x: tx + 8, y: y(curve.done) + 12), anchor: .leading)
            }
            // a month label where each month begins
            let cal = MasterSchedule.calendar
            var m = cal.date(from: cal.dateComponents([.year, .month], from: first)) ?? first
            var placed: CGFloat = -100
            while m <= cal.date(byAdding: .day, value: Int(span * 7), to: first) ?? first {
                let w = max(CGFloat(m.timeIntervalSince(first) / (7 * 86_400)), 0)
                if x(w) - placed > 50 {
                    ctx.draw(label(ThaiFormat.month.string(from: m), Theme.inkMuted), at: CGPoint(x: x(w), y: size.height - 6), anchor: .leading)
                    placed = x(w)
                }
                guard let next = cal.date(byAdding: .month, value: 1, to: m) else { break }
                m = next
            }
        }
    }
}

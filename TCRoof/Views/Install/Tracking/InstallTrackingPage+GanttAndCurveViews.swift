import SwiftUI
import TCRoofUI
import TCRoofCore

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

import SwiftUI
import TCRoofUI
import TCRoofCore

/// `แผน MP`: the project S-curve (plan against actual, weighted by kWp) and a Gantt row per station.
extension PWAPlanPhoneView {
    @ViewBuilder func mpPlan(_ board: PWAPlanBoard) -> some View {
        if board.bars.isEmpty {
            TCEmptyState("ยังไม่มีสถานีที่มีแผน MP", systemImage: "chart.bar.xaxis", description: Text("สร้างแผนจากการ์ดแผนงาน MP ในหน้างาน"))
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            curveCard(board.curve, today: board.today)
            ganttCard(board.bars.filter { $0.matches(search: search) }, today: board.today)
        }
    }

    /// iPad: the heading and the S-curve at the column's width; `padGantt` goes under it beside `กำหนดส่ง`.
    func padPlan(_ board: PWAPlanBoard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("แผน MP").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                Text("Master Plan | \(board.bars.count) สถานี").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            if board.bars.isEmpty {
                TCEmptyState("ยังไม่มีสถานีที่มีแผน MP", systemImage: "chart.bar.xaxis", description: Text("สร้างแผนจากการ์ดแผนงาน MP ในหน้างาน"))
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                curveCard(board.curve, today: board.today)
            }
        }
    }

    func padGantt(_ board: PWAPlanBoard) -> some View {
        ganttCard(board.bars.filter { $0.matches(search: search) }, today: board.today)
    }

    // MARK: S-curve

    private func curveCard(_ curve: PWAPlan.Curve, today: Date) -> some View {
        let week = curve.todayIndex.map { "สัปดาห์ \($0)/\(curve.totalWeeks)" }
            ?? (curve.weeks.first.map { today < $0 } == true ? "ยังไม่เริ่ม" : "ครบ \(curve.totalWeeks) สัปดาห์")
        let behind = curve.behindBy
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("ความก้าวหน้าทั้งโครงการ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Text(week).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                figure("จริง", curve.done, Theme.primary)
                figure("แผน", curve.planned, Theme.navy)
                Spacer(minLength: 4)
                Text(behind > 0 ? "ช้ากว่าแผน \(behind)%" : "ตามแผน").font(.sarabunFixed(13, .bold))
                    .foregroundStyle(behind > 0 ? Theme.dangerText : Theme.successText)
            }
            .accessibilityElement(children: .combine)
            PWAPlanCurveChart(curve: curve, labelSize: pad ? 11 : 9)
                .frame(height: curveHeight)
                .accessibilityElement()
                .accessibilityLabel("S-curve แผนเทียบจริง | จริง \(PWAPlanFormat.percent(curve.done)) แผน \(PWAPlanFormat.percent(curve.planned))")
            curveLegend(today)
        }
        .lineLimit(1)
        .padding(.horizontal, pad ? 16 : 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func figure(_ title: String, _ value: Double, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            Text(PWAPlanFormat.percent(value)).font(.sarabunFixed(20, .bold)).foregroundStyle(color).monospacedDigit()
        }
    }

    private func curveLegend(_ today: Date) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: 14, y: 1)) }
                    .stroke(Theme.inkFaint, style: StrokeStyle(lineWidth: 2, dash: [4, 3])).frame(width: 14, height: 2)
                Text("แผน")
            }
            HStack(spacing: 4) {
                Capsule().fill(Theme.primary).frame(width: 14, height: 3)
                Text("จริง")
            }
            HStack(spacing: 4) {
                Rectangle().fill(Theme.danger).frame(width: 2, height: 10)
                Text(PWAPlanFormat.dayMonth.string(from: today))
            }
        }
        .font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    // MARK: Gantt

    private func ganttCard(_ bars: [PWAPlan.Bar], today: Date) -> some View {
        let axis = PWAPlanAxis(bars: bars, today: today)
        // iPad: the first eight, and a row that shows the rest
        let listed = pad && !ganttAll ? Array(bars.prefix(8)) : bars
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("รายสถานี").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                Text("เรียงตามวันส่งมอบ").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 2)
            // the months sit over the bars: past the name column (90, on iPad 170) and its gap (6), short of the due column (40 + 6)
            GeometryReader { g in
                ForEach(axis.months, id: \.start) { m in
                    Text(PWAPlanFormat.month.string(from: m.start)).font(.sarabunFixed(pad ? 11 : 10)).foregroundStyle(Theme.inkFaint)
                        .fixedSize().offset(x: axis.fraction(m.start) * g.size.width)
                }
            }
            .frame(height: 14)
            .padding(.leading, ganttNameWidth + 6).padding(.trailing, 46)
            .accessibilityHidden(true)
            if bars.isEmpty {
                Text("ไม่พบสถานีที่ค้นหา").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            ForEach(listed) { ganttRow($0, axis: axis) }
            if listed.count < bars.count {
                Button { ganttAll = true } label: {
                    Text("อีก \(bars.count - listed.count) สถานี | เลื่อนดู").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("แสดงอีก \(bars.count - listed.count) สถานี")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private var ganttNameWidth: CGFloat { pad ? 170 : 90 }

    /// The S-curve's height: 268 pt on iPad (FIX-01, docs/ui/pwa-plan-ipad), 120 on iPhone. The chart draws from its
    /// frame, so the plot grows and the labels keep their size.
    private var curveHeight: CGFloat { pad ? 268 : 120 }

    private func ganttRow(_ bar: PWAPlan.Bar, axis: PWAPlanAxis) -> some View {
        let pending = bar.pendingAckDays > 0 ? "รอรับทราบ \(bar.pendingAckDays) วัน" : ""
        let who = [bar.ref, bar.contractor.isEmpty ? bar.team : PWAPlan.contractorTitle(bar.contractor), pending]
            .filter { !$0.isEmpty }.joined(separator: " | ")
        let due = PWAPlanFormat.numeric.string(from: bar.due)
        return Button { open(.schedule, station: bar.id) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(bar.name).font(.sarabunFixed(pad ? 13 : 12, .bold)).foregroundStyle(Theme.navy).frame(height: pad ? 15 : 14)
                    Text(who).font(.sarabunFixed(pad ? 11 : 10)).foregroundStyle(bar.pendingAckDays > 0 ? Theme.pending : Theme.inkMuted)
                        .minimumScaleFactor(0.85).frame(height: pad ? 15 : 13)
                }
                .lineLimit(1)
                .frame(width: ganttNameWidth, alignment: .leading)
                PWAPlanGanttBar(bar: bar, axis: axis).frame(height: 22)
                Text(due).font(.sarabunFixed(11, .bold)).monospacedDigit().foregroundStyle(bar.behind ? Theme.dangerText : Theme.navy)
                    .frame(width: 40, alignment: .trailing)
            }
            // the board's rows are 30 pt; they are 44 here for the touch target
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.fullName) | จริง \(PWAPlanFormat.percent(bar.actual)) แผน \(PWAPlanFormat.percent(bar.planned)) | ส่งมอบ \(due)"
            + (pending.isEmpty ? "" : " | \(pending)"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The Gantt's shared time axis: from the month before today to two months after, longer when a station is due
/// later (six months at most). Bars are clipped to it.
struct PWAPlanAxis {
    let start: Date
    let end: Date
    let today: Date
    /// The first day of each month on the axis.
    let months: [(start: Date, days: Int)]

    init(bars: [PWAPlan.Bar], today: Date) {
        let cal = MasterSchedule.calendar
        let month = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        let start = cal.date(byAdding: .month, value: -1, to: month) ?? month
        let lastDue = bars.map(\.due).max() ?? today
        let dueMonth = cal.date(from: cal.dateComponents([.year, .month], from: lastDue)) ?? lastDue
        let span = cal.dateComponents([.month], from: start, to: dueMonth).month ?? 0
        let count = min(max(span + 1, 4), 6)
        self.start = start
        self.end = cal.date(byAdding: .month, value: count, to: start) ?? start
        self.today = cal.startOfDay(for: today)
        self.months = (0..<count).compactMap { i in
            guard let m = cal.date(byAdding: .month, value: i, to: start), let next = cal.date(byAdding: .month, value: 1, to: m) else { return nil }
            return (m, cal.dateComponents([.day], from: m, to: next).day ?? 30)
        }
    }

    /// 0…1 along the axis.
    func fraction(_ date: Date) -> CGFloat {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return CGFloat(min(max(date.timeIntervalSince(start) / total, 0), 1))
    }
}

/// One Gantt row's bar (`icons/gantt-row.svg`): the track from start to due, the actual fill (red when behind),
/// a navy tick where the plan stands, and the red today line.
struct PWAPlanGanttBar: View {
    let bar: PWAPlan.Bar
    let axis: PWAPlanAxis

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x0 = axis.fraction(bar.start) * w, x1 = axis.fraction(bar.due) * w, span = max(x1 - x0, 0)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.ganttTrack).frame(width: span, height: 8).offset(x: x0, y: 7)
                Capsule().fill(bar.behind ? Theme.danger : Theme.primary)
                    .frame(width: span * min(max(bar.actual, 0), 100) / 100, height: 8).offset(x: x0, y: 7)
                Rectangle().fill(Theme.navySolid).frame(width: 2, height: 14)
                    .offset(x: x0 + span * min(max(bar.planned, 0), 100) / 100, y: 4)
                Rectangle().fill(Theme.danger).frame(width: 1.5, height: 22).offset(x: axis.fraction(axis.today) * w)
            }
        }
    }
}

/// The S-curve: gridlines every 25 %, the plan dashed, the actual solid up to this week, a red line at today, and
/// the months under the axis. 24 pt on the left for the percent labels, 16 pt under the plot for the months.
struct PWAPlanCurveChart: View {
    let curve: PWAPlan.Curve
    /// 9 pt on iPhone; 11 on iPad, where the chart is wider and taller. The margins grow with it.
    var labelSize: CGFloat = 9

    var body: some View {
        Canvas { ctx, size in
            let grow = labelSize / 9
            let left = 24 * grow, right = size.width - 4, top: CGFloat = 4, bottom = size.height - 16 * grow
            let last = CGFloat(max(curve.weeks.count - 1, 1))
            func x(_ week: CGFloat) -> CGFloat { left + week / last * (right - left) }
            func y(_ percent: Double) -> CGFloat { bottom - CGFloat(min(max(percent, 0), 100)) / 100 * (bottom - top) }
            func line(_ values: [Double]) -> Path {
                var p = Path()
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: x(CGFloat(i)), y: y(v))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }
            func label(_ s: String, _ color: Color) -> Text { Text(s).font(.sarabunFixed(labelSize)).foregroundColor(color) }

            for p in stride(from: 0.0, through: 100, by: 25) {
                var grid = Path()
                grid.move(to: CGPoint(x: left, y: y(p)))
                grid.addLine(to: CGPoint(x: right, y: y(p)))
                ctx.stroke(grid, with: .color(Theme.hairline), lineWidth: 1)
                ctx.draw(label("\(Int(p))%", Theme.inkFaint), at: CGPoint(x: 0, y: y(p)), anchor: .leading)
            }
            ctx.stroke(line(curve.plan), with: .color(Theme.inkFaint), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            ctx.stroke(line(curve.actual), with: .color(Theme.primary), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            if let i = curve.todayIndex {
                var today = Path()
                today.move(to: CGPoint(x: x(CGFloat(i)), y: top - 2))
                today.addLine(to: CGPoint(x: x(CGFloat(i)), y: bottom))
                ctx.stroke(today, with: .color(Theme.danger), lineWidth: 1.5)
                // the label flips to the left of the line near the right edge
                let flip = x(CGFloat(i)) > right - 30
                ctx.draw(label("วันนี้", Theme.danger), at: CGPoint(x: x(CGFloat(i)) + (flip ? -4 : 4), y: top + 4), anchor: flip ? .trailing : .leading)
            }
            for m in months { ctx.draw(label(m.title, Theme.inkMuted), at: CGPoint(x: x(m.week), y: size.height - 5 * grow), anchor: .leading) }
        }
    }

    /// The first week's month (the one its Saturday is in) at the axis start, then each month where it begins;
    /// every other one past six.
    private var months: [(title: String, week: CGFloat)] {
        guard let first = curve.weeks.first, let last = curve.weeks.last else { return [] }
        let cal = MasterSchedule.calendar
        let saturday = cal.date(byAdding: .day, value: 6, to: first) ?? first
        var out: [(String, CGFloat)] = [(PWAPlanFormat.month.string(from: saturday), 0)]
        var m = cal.date(from: cal.dateComponents([.year, .month], from: saturday)) ?? first
        while let next = cal.date(byAdding: .month, value: 1, to: m), next <= last {
            let week = CGFloat(next.timeIntervalSince(first) / (7 * 86_400))
            // a month that begins inside the first weeks would print over the first label
            if week >= 2.5 { out.append((PWAPlanFormat.month.string(from: next), week)) }
            m = next
        }
        let step = out.count > 6 ? 2 : 1
        return out.enumerated().filter { $0.offset % step == 0 }.map { ($0.element.0, $0.element.1) }
    }
}

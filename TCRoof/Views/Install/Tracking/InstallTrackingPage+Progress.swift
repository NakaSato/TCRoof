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

import SwiftUI
import TCRoofUI
import TCRoofCore

/// iPhone `ความคืบหน้าเทียบแผน` (docs/ui/install-tracking-iphone §4.2): the iPad's Gantt (`InstallGantt`, `InstallAxis`,
/// `InstallBars`) with a pinned 150 pt column of stages and 30 pt day columns that scroll sideways, opened at today; or
/// the iPad's S-curve. A stage row opens and closes its sub-tasks. The board's weather row and `งวดเบิกเงิน` have no
/// source and are left out.
extension InstallTrackingPage {
    static let phoneNameWidth: CGFloat = 150
    static let phoneSubHeight: CGFloat = 38
    static let phoneMilestoneHeight: CGFloat = 52

    /// A day column is 30 pt; a week column (a span past a month) 44.
    static func phoneColumn(_ axis: InstallAxis) -> CGFloat { axis.unit == .day ? 30 : 44 }

    func phoneProgressCard(_ data: InstallPageData, _ g: InstallGantt) -> some View {
        let span = g.span()
        let range = span.map { "\(ThaiFormat.dayMonth.string(from: $0.lowerBound)) – \(ThaiFormat.numericDate.string(from: $0.upperBound))" } ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("ความคืบหน้าเทียบแผน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                        .lineLimit(1).minimumScaleFactor(0.8).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                    TCCountSegments([.init("Gantt"), .init("S-Curve")],
                                    selection: Binding(get: { view == .gantt ? 0 : 1 }, set: { view = $0 == 0 ? .gantt : .curve }),
                                    equalWidths: false, fontSize: 14)
                        .fixedSize()
                        .accessibilityLabel("มุมมองความคืบหน้า")
                        .accessibilityIdentifier("install.progressView")
                }
                HStack(spacing: 8) {
                    Text(range).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    if let t = data.tracking { forecastChip(t) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if view == .gantt {
                phoneGantt(g, data: data)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ganttFooter(hasMilestones: !(data.plan?.milestones.isEmpty ?? true))
            } else {
                phoneCurve(data)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    /// `คาดส่งมอบ 24/10 ตามกำหนด` green, or red `คาดส่งมอบ 30/10 | ช้า n วัน`.
    private func forecastChip(_ t: InstallTracking) -> some View {
        let slack = t.slackDays(), end = Self.forecastDay(t)
        return toneChip(slack < 0 ? "คาดส่งมอบ \(end) | ช้า \(-slack) วัน" : "คาดส่งมอบ \(end) ตามกำหนด", slack < 0 ? .danger : .ok)
    }

    private func phoneExpanded(_ row: InstallGantt.Row) -> Bool {
        !row.subs.isEmpty && ((row.status == .current) != toggled.contains(row.id))
    }

    private func toggleRow(_ id: String) {
        withAnimation(.snappy) { if toggled.contains(id) { toggled.remove(id) } else { toggled.insert(id) } }
    }

    // MARK: Gantt

    private func phoneGantt(_ g: InstallGantt, data: InstallPageData) -> some View {
        let axis = InstallAxis(g, dayLimit: 31), cw = Self.phoneColumn(axis)
        let width = cw * CGFloat(axis.columns.count)
        let milestones = data.plan?.milestones ?? []
        let todayIndex = axis.columns.firstIndex { axis.unit == .day ? MasterSchedule.calendar.isDate($0, inSameDayAs: axis.today) : axis.contains(axis.today, week: $0) }
        return HStack(alignment: .top, spacing: 0) {
            // the pinned column
            VStack(spacing: 0) {
                Text("ขั้นตอน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    .padding(.leading, 12).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, minHeight: InstallAxis.headerHeight, maxHeight: InstallAxis.headerHeight, alignment: .bottomLeading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
                    .accessibilityHidden(true)
                ForEach(g.rows) { row in
                    stageName(row)
                    if phoneExpanded(row) { ForEach(row.subs) { subName($0, parent: row) } }
                }
                if !milestones.isEmpty {
                    Text("เหตุการณ์สำคัญ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        .padding(.leading, 12)
                        .frame(maxWidth: .infinity, minHeight: Self.phoneMilestoneHeight, maxHeight: Self.phoneMilestoneHeight, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
                        .accessibilityHidden(true)
                }
            }
            .frame(width: Self.phoneNameWidth)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
            // the days
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        dayHeader(axis, cw: cw)
                        ForEach(g.rows) { row in
                            InstallBars(row: row, axis: axis, width: width)
                                .frame(width: width, height: Self.stageHeight)
                                .background(row.status == .current ? Theme.primary.opacity(0.035) : .clear)
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                            if phoneExpanded(row) {
                                ForEach(row.subs) { s in
                                    InstallSubBar(sub: s, parent: row, axis: axis, width: width)
                                        .frame(width: width, height: Self.phoneSubHeight)
                                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1) }
                                }
                            }
                        }
                        if !milestones.isEmpty { milestoneStrip(milestones, axis: axis, width: width, today: g.today) }
                    }
                    .frame(width: width)
                    .background(alignment: .topLeading) {
                        GeometryReader { geo in
                            InstallColumns(axis: axis, nonWorking: data.nonWorking, x: 0, width: width, height: geo.size.height)
                        }
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topLeading) {
                        GeometryReader { geo in
                            let tx = (axis.x(axis.today, width) + axis.xEnd(axis.today, width)) / 2
                            Path { p in p.move(to: CGPoint(x: tx, y: 0)); p.addLine(to: CGPoint(x: tx, y: geo.size.height)) }
                                .stroke(Theme.danger, lineWidth: 1.5)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .scrollIndicators(.hidden)
                // opened at today
                .onAppear { if let i = todayIndex { proxy.scrollTo("col-\(i)", anchor: .center) } }
            }
        }
    }

    /// The weekday over the date; Sundays rose, today a red pill; a week column shows its first day.
    private func dayHeader(_ axis: InstallAxis, cw: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(axis.columns.enumerated()), id: \.offset) { i, d in
                let week = axis.unit == .week
                let today = week ? axis.contains(axis.today, week: d) : MasterSchedule.calendar.isDate(d, inSameDayAs: axis.today)
                let sunday = !week && InstallPlan.isSunday(d)
                VStack(spacing: 2) {
                    if !week { Text(InstallAxis.weekday.string(from: d)).font(.sarabunFixed(11)).foregroundStyle(today ? Theme.dangerText : sunday ? Theme.survey : Theme.inkMuted) }
                    Text(week ? ThaiFormat.dayMonth.string(from: d) : "\(MasterSchedule.calendar.component(.day, from: d))")
                        .font(.sarabunFixed(week ? 11 : 14, .bold)).monospacedDigit()
                        .foregroundStyle(today ? Theme.onPrimary : sunday ? Theme.survey : Theme.navy)
                        .padding(.horizontal, today ? 4 : 0).frame(height: 20)
                        .background { if today { Capsule().fill(Theme.danger) } }
                        .fixedSize()
                }
                .padding(.bottom, 4)
                .frame(width: cw, height: InstallAxis.headerHeight, alignment: .bottom)
                .id("col-\(i)")
            }
        }
        .frame(height: InstallAxis.headerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func stageName(_ row: InstallGantt.Row) -> some View {
        let open = phoneExpanded(row), done = row.subs.filter { $0.percent >= 99.95 }.count
        let pct = "\(Int(row.percent.rounded()))%"
        return Button { if !row.subs.isEmpty { toggleRow(row.id) } } label: {
            HStack(spacing: 8) {
                phoneDisc(row)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(row.subs.isEmpty ? pct : "งานย่อย \(done)/\(row.subs.count) | " + pct)
                        .font(.sarabunFixed(12)).foregroundStyle(row.overrunDays > 0 && row.status != .done ? Theme.dangerText : Theme.inkMuted)
                        .lineLimit(1).minimumScaleFactor(0.75).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10).padding(.trailing, 6)
            .frame(height: Self.stageHeight)
            .background(row.status == .current ? Theme.primary.opacity(0.035) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.code) \(row.title) | \(pct)" + (row.overrunDays > 0 ? " | เกินแผน \(row.overrunDays) วัน" : "")
                            + (row.subs.isEmpty ? "" : open ? " | ซ่อนงานย่อย" : " | แสดงงานย่อย"))
        .accessibilityIdentifier("installStage.\(row.code)")
        .accessibilityAction(named: "เปิดรายละเอียด") { stage = row }
        .contextMenu { Button("รายละเอียดขั้นตอน", systemImage: "info.circle") { stage = row } }
    }

    private func subName(_ s: InstallGantt.Sub, parent: InstallGantt.Row) -> some View {
        let ink: Color = s.percent >= 99.95 ? Theme.success : s.percent > 0 || parent.status == .current ? Theme.primary : Theme.chevron
        return HStack(alignment: .top, spacing: 7) {
            Circle().fill(ink).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.title).font(.sarabunFixed(13)).foregroundStyle(Theme.navy).lineLimit(1)
                Text("\(Int(s.percent.rounded()))%").font(.sarabunFixed(11, .bold)).monospacedDigit()
                    .foregroundStyle(s.percent >= 99.95 ? Theme.successInk : Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 22).padding(.trailing, 6).padding(.top, 3)
        .frame(height: Self.phoneSubHeight, alignment: .top)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func phoneDisc(_ row: InstallGantt.Row) -> some View {
        ZStack {
            switch row.status {
            case .done:
                Circle().fill(Theme.success)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onPrimary)
            case .current:
                Circle().fill(Theme.primary)
                Text(row.code).font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.onPrimary).minimumScaleFactor(0.6)
            case .waiting:
                Circle().fill(Theme.segmentTrack)
                Text(row.code).font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.inkMuted).minimumScaleFactor(0.6)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    /// `เหตุการณ์สำคัญ`: the plan's milestones as diamonds on their days, filled once passed, titled under.
    private func milestoneStrip(_ ms: [InstallPlan.Milestone], axis: InstallAxis, width: CGFloat, today: Date) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(ms) { m in
                let x = (axis.x(m.date, width) + axis.xEnd(m.date, width)) / 2
                VStack(spacing: 2) {
                    MilestoneDiamond(passed: MasterSchedule.calendar.startOfDay(for: m.date) < MasterSchedule.calendar.startOfDay(for: today))
                    Text(m.title).font(.sarabunFixed(10)).foregroundStyle(Theme.inkMuted).lineLimit(1).frame(width: 64)
                }
                .position(x: x, y: Self.phoneMilestoneHeight / 2)
            }
        }
        .frame(width: width, height: Self.phoneMilestoneHeight, alignment: .topLeading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("เหตุการณ์สำคัญ " + ms.map { "\($0.title) \(ThaiFormat.dayMonth.string(from: $0.date))" }.joined(separator: " | "))
    }

    private func ganttFooter(hasMilestones: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Capsule().strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])).frame(width: 16, height: 9)
                    Text("คาดการณ์")
                }
                HStack(spacing: 5) {
                    InstallHatch(ink: Theme.danger).clipShape(Capsule()).frame(width: 16, height: 9)
                    Text("เกินแผน")
                }
                if hasMilestones {
                    HStack(spacing: 4) {
                        Rectangle().fill(Theme.navy).frame(width: 8, height: 8).rotationEffect(.degrees(45))
                        Text("เหตุการณ์สำคัญ")
                    }
                }
            }
            Text("แตะขั้นเพื่อดูงานย่อย | กดค้างเพื่อดูรายละเอียด")
        }
        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityHidden(true)
    }

    // MARK: S-curve

    @ViewBuilder private func phoneCurve(_ data: InstallPageData) -> some View {
        if data.curveDays.contains(where: { $0.actual != nil || $0.planned > 0 }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    curveKey(Theme.inkFaint, "แผนสะสม")
                    curveKey(Theme.primary, "งานจริงสะสม")
                    HStack(spacing: 4) {
                        Rectangle().fill(Theme.danger).frame(width: 2, height: 12)
                        Text("วันนี้").foregroundStyle(Theme.dangerText)
                    }
                }
                .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                .accessibilityHidden(true)
                InstallCurveChart(days: data.curveDays, today: data.gantt?.today ?? .now, forecastEnd: data.tracking?.forecastEnd(),
                                  nonWorking: data.nonWorking, waitLabel: nil, compact: true)
                    .frame(height: 330)
                    .accessibilityElement()
                    .accessibilityLabel("S-curve แผนสะสมเทียบงานจริงสะสมรายวัน")
                    .accessibilityValue(data.tracking.map { "แผน \(Int($0.planned.rounded()))% จริง \(Int($0.actual.rounded()))%" } ?? "")
                    .accessibilityIdentifier("install.curve")
                Text("แท่ง = งานต่อวัน (แผน | จริง) | เส้นแดงที่วันนี้ = ห่างจากแผน")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(16)
        } else {
            Text("ยังไม่มีแผน MP").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func curveKey(_ c: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(c).frame(width: 16, height: 3)
            Text(title)
        }
    }
}

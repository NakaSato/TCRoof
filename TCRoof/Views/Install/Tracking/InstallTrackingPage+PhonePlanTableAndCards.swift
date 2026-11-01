import SwiftUI
import TCRoofUI
import TCRoofCore

extension InstallTrackingPage {
    // MARK: table

    private func showsCrewPhone(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.crew != nil } }
    private func showsLinksPhone(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.after != nil } }
    private func showsBaselinePhone(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.baselineEnd != nil } }

    /// A sideways-scrolling grid with the WBS and name pinned. In edit mode a stage gets `‹ ›` on its start and `− +` on
    /// its days; done stages and the sub-tasks (whose days are the reports' places) are locked.
    func phonePlanTable(_ p: InstallPlan) -> some View {
        let rows: [(InstallPlan.Row, Bool)] = p.stages.flatMap { s in [(s.row, true)] + s.subs.map { ($0, false) } }
        let date = planEditing ? PCol.date + 52 : PCol.date, days = planEditing ? PCol.days + 50 : PCol.days
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                tableHead("WBS | งาน", width: nil, leading: true)
                ForEach(rows, id: \.0.id) { r, stage in
                    HStack(spacing: 6) {
                        Text(r.code).font(.sarabunFixed(12, stage ? .bold : .regular)).foregroundStyle(Theme.inkMuted).frame(width: 30, alignment: .leading)
                        Text(r.title).font(.sarabunFixed(13, stage ? .bold : .regular)).foregroundStyle(Theme.navy).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, stage ? 10 : 18).padding(.trailing, 4)
                    .frame(height: 52)
                    .background(stage ? Theme.phonePage : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(width: PCol.name)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tableHead("เริ่ม", width: date)
                        tableHead("เสร็จ", width: PCol.date)
                        tableHead("วัน", width: days)
                        if showsCrewPhone(p) { tableHead("คน", width: PCol.crew) }
                        if showsLinksPhone(p) { tableHead("ต่อจาก", width: PCol.after) }
                        if showsBaselinePhone(p) { tableHead("Baseline", width: PCol.slip) }
                        tableHead("สถานะ", width: PCol.status)
                    }
                    ForEach(rows, id: \.0.id) { r, stage in
                        tableCells(r, stage: stage, p, dateWidth: date, daysWidth: days)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("plan-table")
    }

    private func tableHead(_ title: String, width: CGFloat?, leading: Bool = false) -> some View {
        Text(title).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
            .padding(.leading, leading ? 10 : 8)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 44, maxHeight: 44, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
            .accessibilityHidden(true)
    }

    private func tableCells(_ r: InstallPlan.Row, stage: Bool, _ p: InstallPlan, dateWidth: CGFloat, daysWidth: CGFloat) -> some View {
        let canEdit = planEditing && stage && editable(r)
        let d = stage ? editedDates(r) : (start: r.start, end: r.end)
        let changed = stage && planDraft[r.id] != nil
        let lock = planEditing && !canEdit
        return HStack(spacing: 0) {
            Group {
                if canEdit {
                    HStack(spacing: 0) {
                        stepButton("chevron.left", "เลื่อนวันเริ่มก่อน \(r.code)") { setDraft(r) { $0.shift -= 1 } }
                        Text(ThaiFormat.dayMonth.string(from: d.start)).frame(maxWidth: .infinity)
                        stepButton("chevron.right", "เลื่อนวันเริ่มหลัง \(r.code)") { setDraft(r) { $0.shift += 1 } }
                    }
                } else {
                    HStack(spacing: 3) {
                        if lock { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.pending) }
                        Text(ThaiFormat.dayMonth.string(from: d.start))
                    }
                    .padding(.leading, 8)
                }
            }
            .frame(width: dateWidth, alignment: .leading)
            .background(changed && draft(r).shift != 0 ? Theme.warningSoft : .clear)
            Text(ThaiFormat.dayMonth.string(from: d.end)).padding(.leading, 8).frame(width: PCol.date, alignment: .leading)
            Group {
                if canEdit {
                    HStack(spacing: 0) {
                        stepButton("minus", "ลดวัน \(r.code)") { setDraft(r) { $0.days -= 1 } }
                        Text("\(draft(r).days)").frame(maxWidth: .infinity)
                        stepButton("plus", "เพิ่มวัน \(r.code)") { setDraft(r) { $0.days += 1 } }
                    }
                } else {
                    Text("\(stage ? draft(r).days : r.days)").padding(.leading, 8)
                }
            }
            .frame(width: daysWidth, alignment: .leading)
            .background(changed && draft(r).days != r.days ? Theme.warningSoft : .clear)
            if showsCrewPhone(p) { Text(r.crew.map(String.init) ?? "–").padding(.leading, 8).frame(width: PCol.crew, alignment: .leading) }
            if showsLinksPhone(p) { Text(r.after ?? "–").padding(.leading, 8).frame(width: PCol.after, alignment: .leading) }
            if showsBaselinePhone(p) { slipLabel(r.slip).padding(.leading, 8).frame(width: PCol.slip, alignment: .leading) }
            planStatus(r.status).padding(.leading, 8).frame(width: PCol.status, alignment: .leading)
        }
        .font(.sarabunFixed(14, stage ? .bold : .regular)).foregroundStyle(Theme.navy).monospacedDigit()
        .frame(height: 52)
        .background(stage ? Theme.phonePage : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 32, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func planStatus(_ s: InstallGantt.Status) -> some View {
        let (title, tone): (String, InstallPageData.Tone) = switch s {
        case .done: ("เสร็จ", .ok)
        case .current: ("กำลังทำ", .info)
        case .waiting: ("ตามแผน", .idle)
        }
        return toneChip(title, tone)
    }

    // MARK: under the plan

    func phoneCrewCard(_ p: InstallPlan) -> some View {
        let days = p.crewDays, cap = p.teamSize, chart: CGFloat = 100
        let top = CGFloat(max(days.map(\.count).max() ?? 1, (cap ?? 0) + 2, 1))
        let over = p.overTeam
        return phoneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("กำลังคนตามแผน").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(cap.map { "เส้นประ = ทีม \($0) คน" } ?? "จากคำขอรายสัปดาห์").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days, id: \.date) { d in
                        VStack(spacing: 2) {
                            Text(d.count > 0 ? "\(d.count)" : "").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).frame(height: 13)
                            RoundedRectangle(cornerRadius: 2).fill(crewColor(d.date, d.count, p)).frame(height: chart * CGFloat(d.count) / top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: chart + 15, alignment: .bottom)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let cap {
                        Path { q in q.move(to: .zero); q.addLine(to: CGPoint(x: 600, y: 0)) }
                            .stroke(Theme.danger, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1).clipped()
                            .offset(y: -chart * CGFloat(cap) / top)
                    }
                }
                if days.count <= 31 {
                    HStack(spacing: 3) {
                        ForEach(days, id: \.date) { d in
                            Text("\(MasterSchedule.calendar.component(.day, from: d.date))").font(.sarabunFixed(11))
                                .foregroundStyle(d.date == p.today ? Theme.dangerText : InstallPlan.isSunday(d.date) ? Theme.survey : Theme.inkMuted)
                                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
                        }
                    }
                }
                if cap != nil {
                    Text(over.isEmpty ? "ไม่มีวันที่เกินกำลังทีม" : "เกินกำลัง " + over.map(ThaiFormat.dayMonth.string(from:)).joined(separator: ", "))
                        .font(.sarabunFixed(13, .bold)).foregroundStyle(over.isEmpty ? Theme.successInk : Theme.dangerText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังคนตามแผนรายวัน " + days.map { "\($0.count)" }.joined(separator: ", ") + " คน")
    }

    private func crewColor(_ d: Date, _ n: Int, _ p: InstallPlan) -> Color {
        if let cap = p.teamSize, n > cap { return Theme.danger }
        return d < p.today ? Theme.success.opacity(0.45) : d == p.today ? Theme.primary : Theme.installPlanned
    }

    func phoneMilestones(_ p: InstallPlan) -> some View {
        phoneCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Milestone").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                ForEach(p.milestones) { m in
                    let left = MasterSchedule.calendar.dateComponents([.day], from: p.today, to: MasterSchedule.calendar.startOfDay(for: m.date)).day ?? 0
                    HStack(spacing: 12) {
                        MilestoneDiamond(passed: left < 0)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                            Text("กำหนด " + ThaiFormat.numericDate.string(from: m.date)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 6)
                        toneChip(left < 0 ? "ผ่านแล้ว" : left == 0 ? "วันนี้" : "อีก \(left) วัน", left < 0 ? .ok : .info)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    func phoneReady(_ r: InstallPlan.Ready) -> some View {
        phoneCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ความพร้อมขั้นถัดไป").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(r.stage).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                ForEach(r.items, id: \.label) { item in checkRow(item.label, ok: item.ok, note: item.note) }
            }
        }
    }
}

import SwiftUI
import TCRoofUI
import TCRoofCore

extension InstallTrackingPage {
    // MARK: right column

    func planSide(_ p: InstallPlan) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if !p.crew.isEmpty { crewPlanCard(p) }
                if !p.milestones.isEmpty { milestonesCard(p) }
                if let r = p.ready { readyCard(r) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func sideCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    private func crewPlanCard(_ p: InstallPlan) -> some View {
        let days = p.crewDays, cap = p.teamSize, chart: CGFloat = 88
        let top = CGFloat(max((days.map(\.count).max() ?? 1), (cap ?? 0) + 2, 1))
        let over = p.overTeam
        return sideCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("กำลังคนตามแผน").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(cap.map { "เส้นประ = ทีม \($0) คน" } ?? "จากคำขอรายสัปดาห์").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(days, id: \.date) { d in
                        VStack(spacing: 2) {
                            Text(d.count > 0 ? "\(d.count)" : "").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).frame(height: 13)
                            RoundedRectangle(cornerRadius: 2).fill(crewInk(d.date, d.count, p))
                                .frame(height: chart * CGFloat(d.count) / top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: chart + 15, alignment: .bottom)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let cap {
                        Path { q in q.move(to: .zero); q.addLine(to: CGPoint(x: 400, y: 0)) }
                            .stroke(Theme.danger, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1).clipped()
                            .offset(y: -chart * CGFloat(cap) / top)
                    }
                }
                if days.count <= 31 {
                    HStack(spacing: 2) {
                        ForEach(days, id: \.date) { d in
                            Text("\(MasterSchedule.calendar.component(.day, from: d.date))").font(.sarabunFixed(11))
                                .foregroundStyle(d.date == p.today ? Theme.dangerText : InstallPlan.isSunday(d.date) ? Theme.survey : Theme.inkMuted)
                                .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
                        }
                    }
                }
                if cap != nil {
                    Text(over.isEmpty ? "ไม่มีวันที่เกินกำลังทีม"
                         : "เกินกำลัง " + over.map(ThaiFormat.dayMonth.string(from:)).joined(separator: ", ") + " | ขยับงานที่มีเวลาเผื่อ หรือเพิ่มคน")
                        .font(.sarabunFixed(13, .bold)).foregroundStyle(over.isEmpty ? Theme.successInk : Theme.dangerText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังคนตามแผนรายวัน " + days.map { "\($0.count)" }.joined(separator: ", ") + " คน")
    }

    private func crewInk(_ d: Date, _ n: Int, _ p: InstallPlan) -> Color {
        if let cap = p.teamSize, n > cap { return Theme.danger }
        return d < p.today ? Theme.success.opacity(0.45) : d == p.today ? Theme.primary : Theme.installPlanned
    }

    private func milestonesCard(_ p: InstallPlan) -> some View {
        sideCard {
            VStack(alignment: .leading, spacing: 8) {
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
                        chip(left < 0 ? "ผ่านแล้ว" : left == 0 ? "วันนี้" : "อีก \(left) วัน", left < 0 ? .ok : .info)
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func readyCard(_ r: InstallPlan.Ready) -> some View {
        sideCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ความพร้อมขั้นถัดไป").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(r.stage).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                ForEach(r.items, id: \.label) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.ok ? "checkmark" : "exclamationmark").font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(item.ok ? Theme.successInk : Theme.warningInk)
                            .frame(width: 28, height: 28).background(item.ok ? Theme.successSoft : Theme.warningSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.label).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                            Text(item.note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A milestone's diamond: green filled when passed, navy outlined when ahead.
struct MilestoneDiamond: View {
    let passed: Bool

    var body: some View {
        Group {
            if passed {
                Rectangle().fill(Theme.success)
            } else {
                Rectangle().strokeBorder(Theme.navy, lineWidth: 2).background(Theme.surface)
            }
        }
        .frame(width: 12, height: 12)
        .rotationEffect(.degrees(45))
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// A stage's 20 pt bar: the plan's track filled navy (green when done) to its percent with a white `n%`, outlined
/// red while it is critical and not done, with its baseline as a thin grey line under it.
struct PlanStageBar: View {
    let row: InstallPlan.Row
    let axis: InstallAxis
    let width: CGFloat

    var body: some View {
        let x0 = axis.x(row.start, width) + 3, x1 = axis.xEnd(row.end, width) - 3, w = max(x1 - x0, 8)
        let share = CGFloat(min(max(row.percent, 0), 100)) / 100
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .leading) {
            Theme.ganttTrack
            (row.status == .done ? Theme.success : Theme.navy).frame(width: w * share)
            // the label needs room: none on a 1-day bar or a narrow week-axis bar
            if row.days > 1, row.percent > 0, w >= 44 {
                Text("\(Int(row.percent.rounded()))%").font(.sarabunFixed(12, .bold))
                    .foregroundStyle(share >= 0.5 ? Theme.onPrimary : Theme.navy).padding(.leading, 6).fixedSize()
            }
        }
        .frame(width: w, height: 20)
        .clipShape(shape)
        .overlay { if row.critical { shape.strokeBorder(Theme.installCritical, lineWidth: 2) } }
        .offset(x: x0)
        .frame(width: width, height: 44, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if let a = row.baselineStart, let b = row.baselineEnd {
                let bx = axis.x(a, width) + 3
                Capsule().fill(Theme.installBaseline).frame(width: max(axis.xEnd(b, width) - 3 - bx, 4), height: 4).offset(x: bx, y: 35)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A sub-task's 10 pt bar by its status, ringed red when critical, with a dotted float tail to its stage's end.
struct PlanSubBar: View {
    let row: InstallPlan.Row
    let stage: InstallPlan.Row
    let axis: InstallAxis
    let width: CGFloat

    var body: some View {
        let x0 = axis.x(row.start, width) + 5, x1 = axis.xEnd(row.end, width) - 5, w = max(x1 - x0, 8)
        let ink = switch row.status { case .done: Theme.success; case .current: Theme.primary; case .waiting: Theme.installPlanned }
        ZStack(alignment: .leading) {
            if (row.float ?? 0) > 0 {
                let tail = axis.xEnd(stage.end, width) - 6
                Path { p in p.move(to: CGPoint(x: x1 + 6, y: 16)); p.addLine(to: CGPoint(x: tail, y: 16)) }
                    .stroke(Theme.installFloat, style: StrokeStyle(lineWidth: 2, dash: [1.5, 2.5]))
            }
            Capsule().fill(ink).frame(width: w, height: 10)
                .overlay { if row.critical { Capsule().stroke(Theme.installCritical, lineWidth: 1.5).padding(-1.5) } }
                .offset(x: x0)
        }
        .frame(width: width, height: 32, alignment: .leading)
        .accessibilityHidden(true)
    }
}

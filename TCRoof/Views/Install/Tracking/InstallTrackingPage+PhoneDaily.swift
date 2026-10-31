import SwiftUI
import TCRoofUI
import TCRoofCore

/// iPhone `รายงานประจำวัน` (docs/ui/install-tracking-iphone §4.3): the iPad's KPIs two by two, the filter with its
/// counts and `PDF รวม`, then one card a day, newest first, each opening that day's `DailyReportScreen`. The engineer,
/// inspector and photo chips are left out, as the board does.
extension InstallTrackingPage {
    func phoneDailyTab(_ d: InstallDailyData) -> some View {
        let rows: [InstallDailyData.Row] = switch dailyFilter {
        case 1: d.rows.filter(rowNeedsWork)
        case 2: d.rows.filter(\.hasProblem)
        default: d.rows
        }
        return VStack(alignment: .leading, spacing: 14) {
            phoneCard(padding: 0) {
                statGrid(kpis(d).prefix(4).map { AnyView(statCell($0.label, $0.value, ink: $0.ink, note: $0.note, valueSize: 22)) })
            }
            HStack(spacing: 8) {
                filterCapsule("ทั้งหมด", d.rows.count, 0)
                filterCapsule("ต้องทำ", d.rows.filter(rowNeedsWork).count, 1)
                filterCapsule("มีปัญหา", d.rows.filter(\.hasProblem).count, 2)
                Spacer(minLength: 0)
                if d.hasReports {
                    Button { shareAllDailies() } label: {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                            .frame(width: 52, height: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderControl))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("PDF รวม")
                }
            }
            if !d.unacknowledged.isEmpty, permissions.can(.dailySign, on: job.access) {
                Button { ackingAllDailies = true } label: {
                    Label("รับทราบทั้งหมด (\(d.unacknowledged.count) วัน)", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                .accessibilityIdentifier("dailyAckAll")
            }
            if rows.isEmpty {
                Text(d.rows.isEmpty ? "ยังไม่ถึงช่วงติดตั้ง" : "ไม่มีรายงานในหมวดนี้").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(rows) { dayCard($0, workEnd: d.workEnd) }
            if let w = d.week {
                Button { phoneTab = .weekly } label: {
                    Label("สร้าง Weekly Report W\(w.number) จากรายงาน \(w.reports) ฉบับ", systemImage: "doc.text").frame(maxWidth: .infinity)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
            }
        }
    }

    private func filterCapsule(_ title: String, _ count: Int, _ index: Int) -> some View {
        let on = dailyFilter == index
        return Button { dailyFilter = index } label: {
            Text("\(title) \(count)").font(.sarabunFixed(15, .bold)).monospacedDigit()
                .foregroundStyle(on ? Theme.onPrimary : Theme.navy)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(on ? Theme.navy : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Theme.borderSubtle))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func dayCard(_ r: InstallDailyData.Row, workEnd: String) -> some View {
        let urgent = r.state == .today
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(Self.dayLabel(r.date).split(separator: " ").first.map(String.init) ?? "").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    Text("\(RoutineReport.calendar.component(.day, from: r.date))").font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                }
                .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.work).font(.sarabunFixed(16, .bold)).foregroundStyle(r.state == .missing ? Theme.dangerText : Theme.navy).lineLimit(2)
                            Text(subline(r, workEnd: workEnd)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        dayChip(r)
                    }
                    if let p = r.planned, let a = r.actual { progressLine(actual: a, planned: p) }
                    if r.hasProblem {
                        Text(r.problem).font(.sarabunFixed(13)).foregroundStyle(Theme.warningInk).lineLimit(2)
                    }
                }
            }
            dayButton(r)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(urgent ? Theme.dangerSoft.opacity(0.45) : Theme.surface, in: frame)
        .overlay(frame.strokeBorder(urgent ? Theme.danger.opacity(0.35) : Theme.borderSubtle))
        .cardShadow()
        .accessibilityElement(children: .contain)
    }

    private func subline(_ r: InstallDailyData.Row, workEnd: String) -> String {
        switch r.state {
        case .today: return "วันทำงาน | ส่งก่อน \(workEnd)"
        // the title already says there's no report
        case .missing: return "วันทำงาน"
        default:
            let weather = r.rainHours > 0 ? "ฝน \(r.rainHours) ชม." : r.weather?.title
            return [r.crew.map { "\($0) คน" }, weather, r.state == .draft ? "ยังไม่ลงนาม" : nil].compactMap { $0 }.joined(separator: " | ")
        }
    }

    private func dayChip(_ r: InstallDailyData.Row) -> some View {
        let (title, tone): (String, InstallPageData.Tone) = switch r.state {
        case .today: ("ยังไม่ส่ง", .danger)
        case .missing: ("ขาดส่ง", .danger)
        case .draft: ("ร่าง", .warn)
        case .signed: r.isPendingAck ? ("รอรับทราบ", .warn) : ("ส่งแล้ว", .ok)
        case .stopped: r.isPendingAck ? ("หยุด • รอรับทราบ", .warn) : ("หยุดงาน", .idle)
        }
        return toneChip(title, tone)
    }

    /// The cumulative % with the plan's tick on the bar and how far ahead or behind it is.
    private func progressLine(actual a: Double, planned p: Double) -> some View {
        let diff = Int((a - p).rounded())
        return HStack(spacing: 8) {
            Text("\(Int(a.rounded()))%").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).monospacedDigit().frame(width: 40, alignment: .leading)
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track).frame(height: 7)
                    Capsule().fill(diff < 0 ? Theme.danger : Theme.success).frame(width: w * min(max(a / 100, 0), 1), height: 7)
                    Rectangle().fill(Theme.navy).frame(width: 2, height: 14).offset(x: max(w * min(max(p / 100, 0), 1) - 1, 0))
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            toneChip(diff == 0 ? "ตามแผน" : diff > 0 ? "+\(diff) เร็วกว่า" : "\(diff) ช้ากว่า", diff < 0 ? .danger : .ok)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("สะสม \(Int(a.rounded())) เปอร์เซ็นต์ แผน \(Int(p.rounded())) เปอร์เซ็นต์")
    }

    private func dayButton(_ r: InstallDailyData.Row) -> some View {
        let canApprove = r.isPendingAck && permissions.can(.dailySign, on: job.access)
        let (title, prominent): (String, Bool) = switch r.state {
        case .today: ("ทำรายงานวันนี้", true)
        case .draft: ("ทำต่อ | ส่ง", true)
        case .missing: ("ทำรายงาน", false)
        case .signed, .stopped: canApprove ? ("ตรวจ & รับทราบ", true) : ("เปิดรายงาน", false)
        }
        return Button { route = .day(r.date) } label: { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(TCButtonStyle(prominent ? .primary : .secondary, size: .card, fullWidth: true))
            .accessibilityLabel(title + " " + Self.dayLabel(r.date))
    }
}

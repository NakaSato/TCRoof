#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// The iPad's station rows of the `งานติดตั้ง` and `บำรุงรักษา` overviews (docs/ui/pwa-solar-survey-ipad-v3 FIX-01): a full
/// card with a 44 pt ring, the bar, the figures, a 34 pt row for what is going on, and a footer. An install row also
/// has the `งานขออนุญาต` block when the station's MP plan has permit tasks. The iPhone keeps its compact rows.
extension SurveyHomeView {
    // MARK: งานติดตั้ง

    func padInstallRow(_ s: InstallStationSummary) -> some View {
        let pace = InstallOverview.pace(s, threshold: threshold)
        let ring = pace == .behind ? Theme.danger : pace == .ahead ? Theme.success : Theme.primary
        return VStack(alignment: .leading, spacing: 8) {
            padRowTop(mp: s.mpNumber, chip: paceChip(s).map { TCToneChip($0.0, tone: $0.1) }, name: s.name,
                      detail: [s.kWp > 0 ? "\(number(s.kWp)) kWp" : "", s.contractor].filter { !$0.isEmpty }.joined(separator: " · "),
                      ring: TCPlanRing(actual: s.actual / 100, plan: s.plan.map { $0 / 100 }, tint: ring, small: true))
            TCPlanBar(actual: s.actual / 100, plan: s.plan.map { $0 / 100 }, tint: pace == .behind ? Theme.danger : Theme.primary)
                .padding(.vertical, -3)
            installFigures(s, pace)
            if let permits = s.permits, !permits.isEmpty { permitBlock(permits) }
            if !s.currentTask.isEmpty {
                padNoteRow(label: "ขั้นตอนตอนนี้", text: s.currentTask, fill: Theme.progressBox, ink: Theme.navy, arrow: Theme.primary)
            }
            padRowFooter(s.dueDate.map { "ส่งมอบ " + dayMonth($0) }) {
                if let sent = s.reportSentToday { TCToneChip(sent ? "รายงานวันนี้ ✓" : "ยังไม่ส่งรายงาน", tone: sent ? .green : .orange) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `จริง 38% / แผน 50%`, and how far from the plan in the pace's colour.
    private func installFigures(_ s: InstallStationSummary, _ pace: InstallOverview.Pace?) -> some View {
        HStack(spacing: 6) {
            (Text("จริง ") + Text("\(Int(s.actual.rounded()))%").bold().foregroundStyle(Theme.navy)
             + Text(s.plan.map { " / แผน \(Int($0.rounded()))%" } ?? ""))
                .font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            Spacer(minLength: 6)
            if let pace, let v = s.variance {
                let (text, ink): (String, Color) = switch pace {
                case .behind: ("ช้ากว่าแผน \(-v)%", Theme.dangerText)
                case .ahead: ("เร็วกว่าแผน \(v)%", Theme.successText)
                case .onPlan: ("ตามแผน", Theme.primary)
                }
                Text(text).font(.sarabunFixed(12.5, .bold)).foregroundStyle(ink)
            }
        }
        .lineLimit(1)
    }

    /// `งานขออนุญาต 2/4`, a note on the right, and a chip per permit the plan has.
    private func permitBlock(_ permits: [InstallPermit]) -> some View {
        let done = permits.filter { $0.state == .done }.count
        let overdue = permits.contains { $0.state == .overdue }, all = done == permits.count
        let countInk = all ? Theme.successText : overdue ? Theme.dangerText : Theme.navy
        let noteInk = all ? Theme.successText : overdue ? Theme.dangerText
            : permits.contains { $0.state == .pending } ? Theme.warningText : Theme.primary
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("งานขออนุญาต").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize()
                Text("\(done)/\(permits.count)").font(.sarabunFixed(13, .bold)).foregroundStyle(countInk).monospacedDigit().fixedSize()
                Spacer(minLength: 6)
                Text(InstallOverview.permitNote(permits)).font(.sarabunFixed(12, .bold)).foregroundStyle(noteInk).lineLimit(1)
            }
            HStack(spacing: 6) { ForEach(permits, id: \.authority) { permitChip($0) } }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(overdue ? Theme.photoEmptyFill : Theme.permitFill, in: shape)
        .overlay(shape.strokeBorder(overdue ? Theme.permitOverdueLine : Theme.track))
    }

    private func permitChip(_ p: InstallPermit) -> some View {
        let (symbol, fill, ink, state): (String, Color, Color, String) = switch p.state {
        case .done: ("checkmark", Theme.successSoft, Theme.successText, "ได้แล้ว")
        case .submitted: ("hourglass", Theme.primarySoft, Theme.primary, "ยื่นแล้ว รอผล")
        case .pending: ("circle", Theme.warningTint, Theme.warningText, "ยังไม่ยื่น")
        case .overdue: ("exclamationmark", Theme.dangerSoft, Theme.dangerText, "เกินกำหนด")
        }
        return HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .heavy))
            Text(p.authority.title).font(.sarabunFixed(11.5, .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 26)
        .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.authority.title) \(state)")
    }

    // MARK: บำรุงรักษา

    func padMaintenanceRow(_ s: MaintenanceStationSummary) -> some View {
        let status: (String, TCFeedTone?, Color) = switch s.status {
        case .normal: ("ปกติ", .green, Theme.success)
        case .alarm: ("แจ้งเตือน", .red, Theme.danger)
        case .offline: ("ออฟไลน์", nil, Theme.chevron)
        }
        let note: (Color, Color) = switch s.status {
        case .alarm: (Theme.dangerSoft, Theme.dangerText)
        case .offline: (Theme.hairline, Theme.inkMuted)
        case .normal: (Theme.progressBox, Theme.navy)
        }
        let pr = "PR \(s.status == .offline ? "—" : number(s.pr, digits: 0))%"
        return VStack(alignment: .leading, spacing: 8) {
            padRowTop(mp: s.mpNumber, chip: TCToneChip(status.0, tone: status.1), name: s.name,
                      detail: [s.kWp > 0 ? "\(number(s.kWp)) kWp" : "", pr].filter { !$0.isEmpty }.joined(separator: " · "),
                      ring: TCPlanRing(actual: s.yield, tint: status.2, small: true))
            // no plan tick here: the bar gives back the 3 pt it keeps for one on each side
            TCPlanBar(actual: s.yield, tint: status.2).padding(.vertical, -3)
            (Text("วันนี้ ") + Text(number(s.energy, digits: 0)).bold().foregroundStyle(Theme.navy)
             + Text(" / คาด \(number(s.expected, digits: 0)) kWh"))
                .font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).monospacedDigit().lineLimit(1)
            if !s.note.isEmpty { padNoteRow(label: nil, text: s.note, fill: note.0, ink: note.1, arrow: note.1) }
            padRowFooter(s.nextPM.map { "PM ถัดไป " + dayMonth($0) }) {
                if s.openRepairs > 0 {
                    TCToneChip("แจ้งซ่อม \(s.openRepairs) งาน", tone: .orange)
                } else {
                    // fainter than the grey `ออฟไลน์` chip
                    Text("ไม่มีงานซ่อม").font(.sarabunFixed(11, .bold)).lineLimit(1).fixedSize()
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.horizontal, 8).frame(height: 18)
                        .background(Theme.hairline, in: Capsule())
                }
            }
        }
    }

    // MARK: parts

    /// `MP n` and a chip, the name, a detail line, and the ring on the right.
    private func padRowTop(mp: Int?, chip: TCToneChip?, name: String, detail: String, ring: TCPlanRing) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if let mp { Text("MP \(mp)").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted) }
                    if let chip { chip }
                }
                Text(name).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ring
        }
    }

    /// The 34 pt row under the figures: the task under way, or a maintenance station's note.
    private func padNoteRow(label: String?, text: String, fill: Color, ink: Color, arrow: Color) -> some View {
        HStack(spacing: 6) {
            if let label { Text(label).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize() }
            Text(text).font(.sarabunFixed(14, .bold)).foregroundStyle(ink).lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(arrow).accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Under a divider: a date with a calendar glyph, and a chip on the right.
    private func padRowFooter(_ date: String?, @ViewBuilder chip: () -> some View) -> some View {
        HStack(spacing: 6) {
            if let date {
                Image(systemName: "calendar").font(.system(size: 13, weight: .medium))
                Text(date).font(.sarabunFixed(13)).lineLimit(1)
            }
            Spacer(minLength: 6)
            chip()
        }
        .foregroundStyle(Theme.inkMuted)
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }
}
#endif

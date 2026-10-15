import SwiftUI
import TCRoofUI
import TCRoofCore

/// A task's sheet over the install tracking page (docs/ui/install-tracking-ipad §B, `states/03`): its days and status,
/// the overrun box with its cause chips when it runs late, its places as the checklist, and the daily reports' photos tagged to it.
/// Progress is booked in the daily report (`RoutineReport.feed`), so the button opens today's report instead of
/// marking the task done here, which the next report would undo.
struct InstallStageSheet: View {
    let row: InstallGantt.Row
    let count: Int
    let index: Int
    let photos: [Data]
    /// The picked late cause, kept in the MP actual (`MasterSchedule.Actual.lateCauses`); tapping it again clears it.
    let cause: MasterSchedule.LateCause?
    let setCause: (MasterSchedule.LateCause?) -> Void
    let close: () -> Void
    let openDaily: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            head
            if row.overrunDays > 0 && row.status != .done { lateBox }
            if !row.subs.isEmpty { checklist }
            footer
        }
        .padding(24)
        .frame(width: 870)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.navySolid.opacity(0.18), radius: 24, y: 8)
    }

    private var days: String {
        let cal = MasterSchedule.calendar
        let n = (cal.dateComponents([.day], from: row.start, to: row.end).day ?? 0) + 1
        let range = row.start == row.end ? ThaiFormat.numericDate.string(from: row.start)
            : "\(ThaiFormat.dayMonth.string(from: row.start))–\(ThaiFormat.numericDate.string(from: row.end))"
        return "ขั้นที่ \(index)/\(count) · \(range) · \(n) วัน"
    }

    private var head: some View {
        let (title, fill, ink): (String, Color, Color) = switch row.status {
        case .done: ("เสร็จแล้ว", Theme.successSoft, Theme.successInk)
        case .current: ("กำลังทำ", Theme.primarySoft, Theme.primary)
        case .waiting: ("รอดำเนินการ", Theme.hairline, Theme.inkMuted)
        }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(days).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                Text(row.title).font(.sarabunFixed(24, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Text(title).font(.sarabunFixed(12, .bold)).foregroundStyle(ink)
                .padding(.horizontal, 10).frame(height: 24).background(fill, in: Capsule()).padding(.top, 6)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 48, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
    }

    private var lateBox: some View {
        HStack(spacing: 10) {
            Text("คาดว่าเกินแผน \(row.overrunDays) วัน · สาเหตุ").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.dangerText)
                .fixedSize()
            Spacer(minLength: 4)
            ForEach(MasterSchedule.LateCause.allCases, id: \.self) { c in
                let on = cause == c
                Button { setCause(on ? nil : c) } label: {
                    Text(c.title).font(.sarabunFixed(14, .bold)).foregroundStyle(on ? Theme.onPrimary : Theme.dangerText)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(on ? Theme.danger : Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.danger.opacity(on ? 0 : 0.45)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("สาเหตุ " + c.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.danger.opacity(0.35)))
    }

    private var checklist: some View {
        let done = row.subs.filter { $0.percent >= 99.95 }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("รายการตรวจ \(done)/\(row.subs.count)").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                ForEach(row.subs) { checkItem($0) }
            }
        }
    }

    private func checkItem(_ s: InstallGantt.Sub) -> some View {
        let on = s.percent >= 99.95
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(on ? Theme.primary : Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Theme.primary : Theme.pending, lineWidth: 2))
                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.onPrimary) }
            }
            .frame(width: 26, height: 26)
            Text(s.title).font(.sarabunFixed(16)).foregroundStyle(Theme.navy).lineLimit(1)
            Spacer(minLength: 4)
            if !on && s.percent > 0 {
                Text("\(Int(s.percent.rounded()))%").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.pending).monospacedDigit()
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 52)
        .background(on ? Theme.primarySoft.opacity(0.5) : Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.track : Theme.pending.opacity(0.35)))
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? "เสร็จแล้ว" : "\(Int(s.percent.rounded()))%")
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if !photos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("รูปถ่ายหน้างาน").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                        Text("\(photos.count) รูป").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    }
                    HStack(spacing: 8) {
                        ForEach(Array(photos.prefix(6).enumerated()), id: \.offset) { _, d in
                            if let img = UIImage(data: d) {
                                Image(uiImage: img).resizable().scaledToFill().frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if row.status != .done {
                Button(action: openDaily) {
                    Label("บันทึกในรายงานประจำวัน", systemImage: "square.and.pencil")
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
                .fixedSize()
            }
        }
    }
}

import SwiftUI
import TCRoofUI
import TCRoofCore

/// `งานย่อยที่เสร็จวันนี้` under a daily report line whose MP task has WBS rows (CHA-71): a check chip per sub-task not
/// ticked yet. The reporter picks the ones finished today, with the line's photos as evidence; they wait for the team
/// (`รอยืนยัน`) until it confirms them in the stage's update sheet or acknowledges the report. A pick the team sent
/// back shows its reason, and a tap picks it again.
struct DailyWBSPicks: View {
    let items: [MasterSchedule.WorkItem]
    let ticks: [String: MasterSchedule.WBSTick]
    @Binding var line: RoutineReport.ProgressLine
    var readOnly = false

    /// The task's rows that take a tick, less those already ticked; a pick stays shown even once ticked elsewhere.
    static func choices(_ items: [MasterSchedule.WorkItem], task: MasterSchedule.Task?) -> [MasterSchedule.WorkItem] {
        guard let task else { return [] }
        let parents = items.parentCodes
        return items.items(for: task).filter { !parents.contains($0.code) && !$0.notForThisStation }
    }

    var body: some View {
        let rows = Self.choices(items, task: line.task).filter { ticks[$0.code] == nil || line.wbsDone?.contains($0.code) == true }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("งานย่อยที่เสร็จวันนี้").font(.sarabun(13, .bold)).foregroundStyle(Theme.navy)
                    Text("รูปของงานนี้เป็นหลักฐาน | ทีมยืนยันแล้วจึงนับเข้าแผน").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(rows) { chip($0) } }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("daily.wbsPicks")
        }
    }

    private func chip(_ item: MasterSchedule.WorkItem) -> some View {
        let picked = line.wbsDone?.contains(item.code) == true
        let reason = line.wbsReturned?[item.code]
        let ticked = ticks[item.code] != nil
        let on = picked && reason == nil
        let ink: Color = reason != nil ? Theme.dangerText : on ? Theme.onPrimary : Theme.navy
        let fill: Color = reason != nil ? Theme.dangerSoft : on ? (ticked ? Theme.success : Theme.primary) : Theme.surface
        return Button {
            line.toggleWBSDone(item.code)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : reason != nil ? "arrow.uturn.backward.square" : "square")
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(item.code) \(item.title.trimmingCharacters(in: .whitespaces))").font(.sarabun(13, .bold)).lineLimit(1)
                    if let reason {
                        Text("ส่งกลับ: " + reason).font(.sarabun(11)).lineLimit(1)
                    } else if on {
                        Text(ticked ? "ทีมยืนยันแล้ว" : "รอยืนยัน").font(.sarabun(11)).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? .clear : Theme.borderSubtle))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(readOnly || ticked)
        .accessibilityLabel("\(item.code) \(item.title.trimmingCharacters(in: .whitespaces))")
        .accessibilityValue(reason.map { "ส่งกลับ " + $0 } ?? (on ? (ticked ? "ทีมยืนยันแล้ว" : "รอยืนยัน") : "ยังไม่เลือก"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("daily.wbs.\(item.code)")
    }
}

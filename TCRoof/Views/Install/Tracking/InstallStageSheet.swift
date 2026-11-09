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
    /// The latest change to this task confirmed through the project assistant.
    var confirmation: MasterSchedule.Actual.Confirmation? = nil
    let close: () -> Void
    let openDaily: () -> Void
    /// The task's WBS sub-tasks from the plan file, the other case's rows left out; empty for a plan without them.
    var wbs: [MasterSchedule.WorkItem] = []
    var ticks: [String: MasterSchedule.WBSTick] = [:]
    var canTick = false
    var canTakeBack: (MasterSchedule.WBSTick) -> Bool = { _ in false }
    var canEditWBS = false
    var currentUserEmail = ""
    var toggleWBS: (MasterSchedule.WorkItem) -> Void = { _ in }
    var setDocument: (MasterSchedule.WorkItem, String) -> Void = { _, _ in }
    var updateWBSTick: (MasterSchedule.WorkItem, MasterSchedule.WBSTick?) -> Void = { _, _ in }
    var updateWBSItem: (MasterSchedule.WorkItem) -> Void = { _ in }
    /// The daily reports' picks of this task waiting for the team (`Job.wbsPending`, CHA-71).
    var pending: [RoutineReport.WBSPick] = []
    /// The first photo of a pick's line: its thumbnail.
    var pickPhoto: (RoutineReport.WBSPick) -> Data? = { _ in nil }
    var contractors: Set<String> = []
    /// `ยืนยัน` / `ส่งกลับ`: the team's; a contractor sees the list without them.
    var canConfirm = false
    var confirmWBS: (RoutineReport.WBSPick) -> Void = { _ in }
    var returnWBS: (RoutineReport.WBSPick, String) -> Void = { _, _ in }
    /// `เปิดรายงานประจำวัน <d>`: the pick's report.
    var openReport: (RoutineReport.WBSPick) -> Void = { _ in }
    /// `ดูในแผน`: the MP plan; nil hides it.
    var openPlan: (() -> Void)? = nil
    /// The task's weight in the plan and what is booked of it, in points; nil without a plan.
    var weight: Double? = nil
    var booked: Double? = nil
    @State private var returning: RoutineReport.WBSPick?
    @State private var returnReason = ""
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The WBS update layout (CHA-71): the sub-tasks on the left, what waits from the daily reports on the right.
    private var wide: Bool { sizeClass == .regular && !wbs.isEmpty }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                head
                if !wbs.isEmpty, weight != nil { progressLine.padding(.top, 12) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let confirmation { MPAssistantMark(confirmation: confirmation) }
                        if row.overrunDays > 0 && row.status != .done { lateBox }
                        if !row.subs.isEmpty { checklist }
                        if !wbs.isEmpty {
                            if wide {
                                HStack(alignment: .top, spacing: 16) {
                                    wbsCard
                                    pendingCard.frame(width: 340)
                                }
                            } else {
                                wbsCard
                                if !pending.isEmpty { pendingCard }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                footer.padding(.top, 16)
            }
            .padding(24)
            .frame(maxWidth: wide ? 1100 : 870)
            .frame(maxHeight: max(geometry.size.height - 48, 320))
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.navySolid.opacity(0.18), radius: 24, y: 8)
            // the phone's width less its margins
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var days: String {
        let cal = MasterSchedule.calendar
        let n = (cal.dateComponents([.day], from: row.start, to: row.end).day ?? 0) + 1
        let range = row.start == row.end ? ThaiFormat.numericDate.string(from: row.start)
            : "\(ThaiFormat.dayMonth.string(from: row.start))–\(ThaiFormat.numericDate.string(from: row.end))"
        var parts = ["ขั้นที่ \(index)/\(count)", range, "\(n) วัน"]
        if let weight { parts.append("น้ำหนัก " + WBSChecklist.weight(weight)) }
        if let role = taskRole { parts.append(role) }
        return parts.joined(separator: " | ")
    }

    /// Who the task's sub-tasks name, when they agree (`วศ.`, `ผรม.`).
    private var taskRole: String? {
        let roles = Set(wbs.compactMap { $0.responsible?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return roles.count == 1 ? roles.first : nil
    }

    private var head: some View {
        let (title, fill, ink): (String, Color, Color) = switch row.status {
        case .done: ("เสร็จแล้ว", Theme.successSoft, Theme.successInk)
        case .current: ("กำลังทำ", Theme.primarySoft, Theme.primary)
        case .waiting: ("รอดำเนินการ", Theme.hairline, Theme.inkMuted)
        }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(days).font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                Text(row.title).font(.sarabun(24, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Text(title).font(.sarabun(12, .bold)).foregroundStyle(ink)
                .padding(.horizontal, 10).frame(height: 24).background(fill, in: Capsule()).padding(.top, 6)
            if let openPlan {
                Button("ดูในแผน", action: openPlan)
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                    .fixedSize()
                    .accessibilityIdentifier("stage.openPlan")
            }
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

    /// The task's % and `<booked>% / <weight>%`.
    private var progressLine: some View {
        let w = weight ?? 0, b = min(booked ?? 0, w)
        let share = w > 0 ? b / w : row.percent / 100
        return HStack(spacing: 12) {
            Text("\(Int((share * 100).rounded()))%").font(.sarabun(20, .bold).monospacedDigit()).foregroundStyle(Theme.navy)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.success).frame(width: g.size.width * max(0, min(share, 1)))
                }
            }
            .frame(height: 8)
            Text("\(WBSChecklist.weight(b)) / \(WBSChecklist.weight(w))").font(.sarabun(13, .bold).monospacedDigit())
                .foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ความคืบหน้า \(Int((share * 100).rounded())) เปอร์เซ็นต์ นับแล้ว \(WBSChecklist.weight(b)) จาก \(WBSChecklist.weight(w))")
    }

    /// `งานย่อย WBS`: the rows with their source chips.
    private var wbsCard: some View {
        WBSChecklist(items: wbs, ticks: ticks, canTick: canTick, canTakeBack: canTakeBack,
                     canEdit: canEditWBS, currentUserEmail: currentUserEmail,
                     toggle: toggleWBS, setDocument: setDocument,
                     updateTick: updateWBSTick, updateItem: updateWBSItem,
                     pending: Dictionary(pending.map { ($0.code, $0) }) { a, _ in a }, contractors: contractors,
                     canConfirm: canConfirm, confirm: confirmWBS)
            .padding(wide ? 14 : 0)
            .background(wide ? Theme.phonePage : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// `รอยืนยัน`: the daily reports' picks waiting, with `ส่งกลับ` and `ยืนยัน` for the team.
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("รอยืนยัน").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("\(pending.count) รายการ").font(.sarabun(13, .bold)).foregroundStyle(pending.isEmpty ? Theme.inkMuted : Theme.warningText)
            }
            if pending.isEmpty {
                Text("ไม่มีงานย่อยที่รอยืนยันจากรายงานประจำวัน").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
            ForEach(pending) { pickRow($0) }
            Text(canConfirm
                 ? "งานย่อยจากรายงานประจำวันนับเข้าแผนเมื่อทีมยืนยัน | ลงนามรับทราบรายงานของวันนั้นยืนยันทุกรายการในรายงาน"
                 : "งานย่อยที่แจ้งในรายงานประจำวันนับเข้าแผนเมื่อทีมยืนยัน")
                .font(.sarabun(12)).foregroundStyle(Theme.navy)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .alert("ส่งกลับให้แก้", isPresented: Binding(get: { returning != nil }, set: { if !$0 { returning = nil } }),
               presenting: returning) { pick in
            TextField("เหตุผล เช่น รูปไม่ชัด", text: $returnReason)
            Button("ส่งกลับ") { returnWBS(pick, returnReason); returning = nil }
            Button("ยกเลิก", role: .cancel) { returning = nil }
        } message: { pick in
            Text("\(pick.code) กลับไปให้ผู้รายงานแก้ในรายงานประจำวัน")
        }
    }

    private func pickRow(_ pick: RoutineReport.WBSPick) -> some View {
        let item = wbs.first { $0.code == pick.code }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let d = pickPhoto(pick), !d.isEmpty {
                        PhotoImage(data: d, maxPixel: 160)
                    } else {
                        Image(systemName: "photo").foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.hairline)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pick.code).font(.sarabun(13, .bold).monospacedDigit()).foregroundStyle(Theme.primary)
                        Text(item?.title.trimmingCharacters(in: .whitespaces) ?? "").font(.sarabun(14)).foregroundStyle(Theme.navy)
                            .lineLimit(2)
                    }
                    Text(WBSChecklist.pickLine(pick)).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                    Button("เปิดรายงานประจำวัน \(ThaiFormat.dayMonth.string(from: pick.day))") { openReport(pick) }
                        .font(.sarabun(12, .bold)).foregroundStyle(Theme.primary)
                        .frame(minHeight: 44, alignment: .leading)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wbs.pending.open.\(pick.code)")
                }
            }
            if canConfirm {
                HStack(spacing: 8) {
                    Button("ส่งกลับ") { returnReason = ""; returning = pick }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                        .accessibilityIdentifier("wbs.pending.return.\(pick.code)")
                    Button("ยืนยัน") { confirmWBS(pick) }
                        .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                        .accessibilityIdentifier("wbs.pending.confirm.\(pick.code)")
                }
            }
        }
        .padding(10)
        .background(Theme.warningSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wbs.pending.\(pick.code)")
    }

    /// One row on iPad; on a phone the cause chips go under the text, two by two when one row of them is too wide.
    private var lateBox: some View {
        let label = Text("คาดว่าเกินแผน \(row.overrunDays) วัน | สาเหตุ").font(.sarabun(16, .bold)).foregroundStyle(Theme.dangerText)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                label.fixedSize()
                Spacer(minLength: 4)
                causeChips
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                HStack(spacing: 8) { causeChips }
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) { causeChips }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.danger.opacity(0.35)))
    }

    @ViewBuilder private var causeChips: some View {
        ForEach(MasterSchedule.LateCause.allCases, id: \.self) { c in
            let on = cause == c
            Button { setCause(on ? nil : c) } label: {
                Text(c.title).font(.sarabun(14, .bold)).foregroundStyle(on ? Theme.onPrimary : Theme.dangerText)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 44)
                    .background(on ? Theme.danger : Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.danger.opacity(on ? 0 : 0.45)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("สาเหตุ " + c.title)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    private var checklist: some View {
        let done = row.subs.filter { $0.percent >= 99.95 }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("รายการตรวจ \(done)/\(row.subs.count)").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
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
            Text(s.title).font(.sarabun(16)).foregroundStyle(Theme.navy).lineLimit(1)
            Spacer(minLength: 4)
            if !on && s.percent > 0 {
                Text("\(Int(s.percent.rounded()))%").font(.sarabun(13, .bold)).foregroundStyle(Theme.pending).monospacedDigit()
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
                        Text("รูปถ่ายหน้างาน").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                        Text("\(photos.count) รูป").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    }
                    HStack(spacing: 8) {
                        ForEach(Array(photos.prefix(6).enumerated()), id: \.offset) { _, d in
                            if !d.isEmpty {
                                PhotoImage(data: d, maxPixel: 200).frame(width: 64, height: 64)
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

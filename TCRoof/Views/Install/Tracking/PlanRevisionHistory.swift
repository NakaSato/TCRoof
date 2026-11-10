import SwiftUI
import TCRoofCore
import TCRoofUI

/// The plan header's `REV 02` chip (CHA-79): a tap opens the plan's revisions, each approved baseline with who approved
/// it, when, why, its change request and its install end against the one before.
struct PlanRevisionButton: View {
    let input: MasterSchedule.Input
    let replans: Int
    var ink: Color = Theme.primary
    var fill: Color = Theme.primarySoft
    @State private var open = false

    var body: some View {
        let label = MasterSchedule.revisionLabel(input.revisionNumber(replans: replans))
        Button { open = true } label: {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 11, weight: .bold))
            }
            .font(.sarabun(13, .bold)).foregroundStyle(ink)
            .padding(.horizontal, 10).frame(height: 24).background(fill, in: Capsule())
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("แผน \(label), ดูประวัติการแก้แผน")
        .accessibilityIdentifier("plan.revisions")
        .sheet(isPresented: $open) {
            PlanRevisionHistory(input: input, replans: replans)
                .presentationDetents([.medium, .large])
        }
    }
}

/// `ประวัติแผน`: the revisions newest first. A station re-planned before revisions were recorded lists what it has and
/// says the rest starts with its next re-plan.
struct PlanRevisionHistory: View {
    let input: MasterSchedule.Input
    let replans: Int
    @Environment(\.dismiss) private var dismiss

    private var revisions: [MasterSchedule.Revision] { (input.revisions ?? []).reversed() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if revisions.isEmpty { legacyNote }
                    ForEach(revisions) { card($0) }
                }
                .padding(16)
            }
            .background(Theme.phonePage)
            .navigationTitle("ประวัติแผน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
    }

    private var legacyNote: some View {
        Text(replans > 0
             ? "แผนนี้แก้มาแล้ว \(replans) ครั้งก่อนเริ่มบันทึกประวัติ | ผู้อนุมัติและเหตุผลจะบันทึกตั้งแต่การแก้แผนครั้งถัดไป"
             : "ยังไม่มีการแก้แผน | แผนปัจจุบันคือ REV 00")
            .font(.sarabun(15)).foregroundStyle(Theme.inkMuted)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The install end's move from the revision before it: `+12 วัน`, `−3 วัน`; nil for REV 00 or without dates.
    private func shift(_ r: MasterSchedule.Revision) -> Int? {
        guard let i = input.revisions?.firstIndex(of: r), i > 0,
              let end = r.installEnd, let before = input.revisions?[i - 1].installEnd else { return nil }
        return MasterSchedule.calendar.dateComponents([.day], from: before, to: end).day
    }

    private func card(_ r: MasterSchedule.Revision) -> some View {
        let current = r.number == input.revisions?.last?.number
        let who = r.by.map { TeamDirectory.shared.person($0)?.label ?? $0 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(r.label).font(.sarabun(15, .bold)).foregroundStyle(current ? Theme.onPrimary : Theme.primary)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(current ? Theme.primary : Theme.primarySoft, in: Capsule())
                Text(current ? "แผนปัจจุบัน" : r.number == 0 ? "แผนตั้งต้น" : "แผนเดิม")
                    .font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
                if let end = r.installEnd {
                    Text("จบติดตั้ง " + ThaiFormat.numericDate.string(from: end))
                        .font(.sarabun(13, .semibold)).foregroundStyle(Theme.navy).monospacedDigit()
                }
            }
            if let at = r.at {
                line("อนุมัติ", ThaiFormat.numericDate.string(from: at) + (who.map { " โดย \($0)" } ?? ""))
            }
            if !r.reason.isEmpty { line("เหตุผล", r.reason) }
            if let cr = r.changeRequest { line("ใบขอเปลี่ยนแปลง", cr) }
            if let d = shift(r), d != 0 {
                Text(d > 0 ? "จบช้ากว่าฉบับก่อน \(d) วัน" : "จบเร็วกว่าฉบับก่อน \(-d) วัน")
                    .font(.sarabun(13, .semibold)).foregroundStyle(d > 0 ? Theme.dangerText : Theme.successInk)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(current ? Theme.primary.opacity(0.4) : Theme.borderSubtle))
        .accessibilityElement(children: .combine)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).frame(width: 96, alignment: .leading)
            Text(value).font(.sarabun(15)).foregroundStyle(Theme.inkStrong)
        }
    }
}

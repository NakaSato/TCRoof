import SwiftUI
import TCRoofUI
import TCRoofCore

/// A task's WBS sub-tasks in its sheet (docs/specs/project-plan-wbs.md, step 2): each row's evidence and owner, ticked
/// done by the team or the job's contractor. A tick books the row's weight into the plan (`Job.wbsTicks`), so the
/// task's % follows; a document number can go with it. A row with steps under it (2.5.1 and the Inverter station's
/// steps) is a heading: its steps are ticked, indented under it.
struct WBSChecklist: View {
    let items: [MasterSchedule.WorkItem]
    let ticks: [String: MasterSchedule.WBSTick]
    let canTick: Bool
    let canTakeBack: (MasterSchedule.WBSTick) -> Bool
    let toggle: (MasterSchedule.WorkItem) -> Void
    let setDocument: (MasterSchedule.WorkItem, String) -> Void
    @State private var documentFor: MasterSchedule.WorkItem?
    @State private var document = ""
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let parents = items.parentCodes
        let tickable = items.filter { !parents.contains($0.code) }
        let done = tickable.filter { ticks[$0.code] != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("งานย่อย WBS \(done)/\(tickable.count)").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("ติ๊กแล้วนับเข้าแผน MP ตามน้ำหนัก").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            rows(parents)
        }
        .alert("เลขที่เอกสาร", isPresented: Binding(get: { documentFor != nil }, set: { if !$0 { documentFor = nil } }),
               presenting: documentFor) { item in
            TextField("เช่น MOM-001", text: $document)
            Button("บันทึก") { setDocument(item, document); documentFor = nil }
            Button("ยกเลิก", role: .cancel) { documentFor = nil }
        } message: { item in
            Text(item.evidence ?? item.title)
        }
    }

    private func rows(_ parents: Set<String>) -> some View {
        let level = items.map(\.level).min() ?? 2
        // a step's indent: narrower on a phone, where the row's text has little room
        let indent: CGFloat = sizeClass == .compact ? 12 : 24
        return VStack(spacing: 8) {
            ForEach(items) { item in
                Group {
                    if parents.contains(item.code) { heading(item) } else { row(item) }
                }
                .padding(.leading, CGFloat(max(item.level - level, 0)) * indent)
            }
        }
    }

    /// A row its steps add up to: no box, its weight, and the station's type when the file names it.
    private func heading(_ item: MasterSchedule.WorkItem) -> some View {
        let style = item.note?.components(separatedBy: " | ").first { $0.hasPrefix("รูปแบบ:") }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.code).font(.sarabunFixed(13, .bold).monospacedDigit()).foregroundStyle(Theme.primary)
                    Text(item.title.trimmingCharacters(in: .whitespaces)).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let style {
                    Text(style).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                Text("ติ๊กตามขั้นงานด้านล่าง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 4)
            Text(Self.weight(item.weight)).font(.sarabunFixed(13, .bold).monospacedDigit()).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wbs.\(item.code)")
    }

    private func row(_ item: MasterSchedule.WorkItem) -> some View {
        let tick = ticks[item.code]
        let enabled = tick.map(canTakeBack) ?? canTick
        return HStack(alignment: .top, spacing: 12) {
            Button { toggle(item) } label: {
                box(on: tick != nil).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(item.title.trimmingCharacters(in: .whitespaces))
            .accessibilityValue(tick == nil ? "ยังไม่เสร็จ" : "เสร็จแล้ว")
            .accessibilityIdentifier("wbs.\(item.code)")
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.code).font(.sarabunFixed(13, .bold).monospacedDigit()).foregroundStyle(Theme.primary)
                    Text(item.title.trimmingCharacters(in: .whitespaces)).font(.sarabunFixed(15)).foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let evidence = item.evidence {
                    Text("หลักฐาน: \(evidence)").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tick { Text(tickLine(tick)).font(.sarabunFixed(12)).foregroundStyle(Theme.successInk) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.weight > 0 ? Self.weight(item.weight) : "ไม่นับ").font(.sarabunFixed(13, .bold).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                if let who = item.responsible { Text(who).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tick != nil ? Theme.successSoft.opacity(0.45) : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
        .contextMenu {
            if tick != nil && enabled {
                Button("ใส่เลขที่เอกสาร", systemImage: "doc.text") {
                    document = tick?.document ?? ""
                    documentFor = item
                }
            }
        }
    }

    /// `0.25%`, `1.5%`, `5%`: a step's share can be under a tenth.
    static func weight(_ x: Double) -> String {
        x.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX"))) + "%"
    }

    private func box(on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(on ? Theme.success : Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Theme.success : Theme.pending, lineWidth: 2))
            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.onPrimary) }
        }
        .frame(width: 26, height: 26)
    }

    /// `เสร็จ 7/12/69 | สมชาย | MOM-001`
    private func tickLine(_ t: MasterSchedule.WBSTick) -> String {
        let who = TeamDirectory.shared.person(t.by)?.label ?? t.by
        return ["เสร็จ " + ThaiFormat.numericDate.string(from: t.at), who, t.document ?? ""].filter { !$0.isEmpty }.joined(separator: " | ")
    }
}

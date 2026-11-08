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
    var canEdit = false
    var currentUserEmail = ""
    let toggle: (MasterSchedule.WorkItem) -> Void
    let setDocument: (MasterSchedule.WorkItem, String) -> Void
    var updateTick: (MasterSchedule.WorkItem, MasterSchedule.WBSTick?) -> Void = { _, _ in }
    var updateItem: (MasterSchedule.WorkItem) -> Void = { _ in }
    @State private var documentFor: MasterSchedule.WorkItem?
    @State private var document = ""

    private enum ActiveSheet: Identifiable {
        case edit(MasterSchedule.WorkItem)
        case updateTick(MasterSchedule.WorkItem)

        var id: String {
            switch self {
            case .edit(let item): return "edit-\(item.code)"
            case .updateTick(let item): return "update-\(item.code)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let parents = items.parentCodes
        let tickable = items.filter { !parents.contains($0.code) }
        let done = tickable.filter { ticks[$0.code] != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("งานย่อย WBS \(done)/\(tickable.count)").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("ติ๊กแล้วนับเข้าแผน MP ตามน้ำหนัก").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit(let item):
                WBSItemEditSheet(item: item, onSave: updateItem)
            case .updateTick(let item):
                WBSTickUpdateSheet(item: item,
                                   tick: ticks[item.code],
                                   canTick: canTick,
                                   canTakeBack: ticks[item.code].map(canTakeBack) ?? canTick,
                                   currentUserEmail: currentUserEmail) { newTick in
                    updateTick(item, newTick)
                }
            }
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
                    Text(item.code).font(.sarabun(13, .bold).monospacedDigit()).foregroundStyle(Theme.primary)
                    Text(item.title.trimmingCharacters(in: .whitespaces)).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let style {
                    Text(style).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                Text("ติ๊กตามขั้นงานด้านล่าง").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 4)
            Text(Self.weight(item.weight)).font(.sarabun(13, .bold).monospacedDigit()).foregroundStyle(Theme.muted)
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

            Button {
                activeSheet = .updateTick(item)
            } label: {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.code).font(.sarabun(13, .bold).monospacedDigit()).foregroundStyle(Theme.primary)
                            Text(item.title.trimmingCharacters(in: .whitespaces)).font(.sarabun(15)).foregroundStyle(Theme.navy)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let evidence = item.evidence {
                            Text("หลักฐาน: \(evidence)").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let tick { Text(tickLine(tick)).font(.sarabun(12)).foregroundStyle(Theme.successInk) }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(item.weight > 0 ? Self.weight(item.weight) : "ไม่นับ").font(.sarabun(13, .bold).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        if let who = item.responsible { Text(who).font(.sarabun(12)).foregroundStyle(Theme.inkMuted) }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("อัปเดตงานย่อย WBS \(item.code) \(item.title.trimmingCharacters(in: .whitespaces))")
            .accessibilityIdentifier("wbs.row.\(item.code)")

            if canEdit {
                Button { activeSheet = .edit(item) } label: {
                    Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("แก้ไขงานย่อย WBS \(item.code)")
                .accessibilityIdentifier("wbs.edit.\(item.code)")
            } else if enabled {
                Button { activeSheet = .updateTick(item) } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("อัปเดตงานย่อย WBS \(item.code)")
                .accessibilityIdentifier("wbs.update.\(item.code)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tick != nil ? Theme.successSoft.opacity(0.45) : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
        .contextMenu {
            Button("อัปเดตงานย่อย WBS", systemImage: "square.and.pencil") {
                activeSheet = .updateTick(item)
            }
            if tick != nil && enabled {
                Button("ใส่เลขที่เอกสาร", systemImage: "doc.text") {
                    document = tick?.document ?? ""
                    documentFor = item
                }
            }
            if canEdit {
                Button("แก้ไขงานย่อย WBS", systemImage: "pencil") {
                    activeSheet = .edit(item)
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

/// Sheet for internal team / manager (`mp.setup`) to update/edit a WBS work item.
struct WBSItemEditSheet: View {
    let item: MasterSchedule.WorkItem
    let onSave: (MasterSchedule.WorkItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var weight: String
    @State private var responsible: String
    @State private var evidence: String
    @State private var hasDates: Bool
    @State private var baselineStart: Date
    @State private var baselineEnd: Date

    init(item: MasterSchedule.WorkItem, onSave: @escaping (MasterSchedule.WorkItem) -> Void) {
        self.item = item
        self.onSave = onSave
        let cal = MasterSchedule.calendar
        let start = item.baselineStart ?? cal.startOfDay(for: .now)
        _title = State(initialValue: item.title.trimmingCharacters(in: .whitespaces))
        _weight = State(initialValue: item.weight == item.weight.rounded() ? String(Int(item.weight)) : String(item.weight))
        _responsible = State(initialValue: item.responsible ?? "")
        _evidence = State(initialValue: item.evidence ?? "")
        _hasDates = State(initialValue: item.baselineStart != nil && item.baselineEnd != nil)
        _baselineStart = State(initialValue: start)
        _baselineEnd = State(initialValue: max(item.baselineEnd ?? start, start))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("งานย่อย \(item.code)") {
                    LabeledContent("ชื่องาน") {
                        TextField("ชื่องานย่อย", text: $title).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("wbsEdit.title")
                    }
                    LabeledContent("น้ำหนัก (%)") {
                        TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("wbsEdit.weight")
                    }
                    LabeledContent("ผู้รับผิดชอบ") {
                        TextField("เช่น วศ., ผรม.", text: $responsible).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("wbsEdit.responsible")
                    }
                    LabeledContent("หลักฐาน") {
                        TextField("หลักฐาน / เลขที่เอกสาร", text: $evidence).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("wbsEdit.evidence")
                    }
                }
                Section("กำหนดวันตามแผน (Baseline)") {
                    Toggle("มีกำหนดวัน", isOn: $hasDates)
                    if hasDates {
                        DatePicker("วันเริ่ม", selection: $baselineStart, displayedComponents: .date)
                            .onChange(of: baselineStart) { _, s in if baselineEnd < s { baselineEnd = s } }
                        DatePicker("วันเสร็จ", selection: $baselineEnd, in: baselineStart..., displayedComponents: .date)
                    }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("แก้ไข WBS \(item.code)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                        .accessibilityIdentifier("wbsEdit.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        var updated = item
                        let indent = item.title.prefix { $0 == " " }
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedTitle.isEmpty { updated.title = String(indent) + trimmedTitle }
                        updated.weight = max(Double(weight.replacingOccurrences(of: ",", with: ".")) ?? item.weight, 0)
                        let r = responsible.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.responsible = r.isEmpty ? nil : r
                        let e = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.evidence = e.isEmpty ? nil : e
                        let cal = MasterSchedule.calendar
                        updated.baselineStart = hasDates ? cal.startOfDay(for: baselineStart) : nil
                        updated.baselineEnd = hasDates ? cal.startOfDay(for: max(baselineEnd, baselineStart)) : nil
                        onSave(updated)
                        dismiss()
                    }
                    .accessibilityIdentifier("wbsEdit.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Sheet for updating a WBS sub-task's completion status, completion date, and evidence / document number.
/// Accessible to contractors (external users) on their assigned jobs and internal team members.
struct WBSTickUpdateSheet: View {
    let item: MasterSchedule.WorkItem
    let tick: MasterSchedule.WBSTick?
    let canTick: Bool
    let canTakeBack: Bool
    let currentUserEmail: String
    let onSave: (MasterSchedule.WBSTick?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isDone: Bool
    @State private var completedAt: Date
    @State private var document: String

    init(item: MasterSchedule.WorkItem,
         tick: MasterSchedule.WBSTick?,
         canTick: Bool,
         canTakeBack: Bool,
         currentUserEmail: String,
         onSave: @escaping (MasterSchedule.WBSTick?) -> Void) {
        self.item = item
        self.tick = tick
        self.canTick = canTick
        self.canTakeBack = canTakeBack
        self.currentUserEmail = currentUserEmail
        self.onSave = onSave
        let cal = MasterSchedule.calendar
        let done = tick != nil || canTick
        _isDone = State(initialValue: done)
        _completedAt = State(initialValue: tick?.at ?? cal.startOfDay(for: .now))
        _document = State(initialValue: tick?.document ?? "")
    }

    private var mayModify: Bool {
        if tick != nil {
            return canTakeBack
        } else {
            return canTick
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("รายละเอียดงานย่อย WBS") {
                    LabeledContent("รหัสงาน", value: item.code)
                    LabeledContent("งาน") {
                        Text(item.title.trimmingCharacters(in: .whitespaces))
                            .multilineTextAlignment(.trailing)
                    }
                    if item.weight > 0 {
                        LabeledContent("น้ำหนัก", value: WBSChecklist.weight(item.weight))
                    }
                    if let responsible = item.responsible {
                        LabeledContent("ผู้รับผิดชอบ", value: responsible)
                    }
                    if let evidence = item.evidence {
                        LabeledContent("หลักฐานที่ต้องใช้") {
                            Text(evidence).multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("สถานะการดำเนินงาน") {
                    Toggle("ดำเนินการเสร็จแล้ว", isOn: $isDone)
                        .disabled(!mayModify)
                        .accessibilityIdentifier("wbsTick.isDone")

                    if isDone {
                        DatePicker("วันที่เสร็จ", selection: $completedAt, displayedComponents: .date)
                            .disabled(!mayModify)
                            .accessibilityIdentifier("wbsTick.date")

                        LabeledContent("เลขที่เอกสาร") {
                            TextField("เช่น MOM-001 (ถ้ามี)", text: $document)
                                .multilineTextAlignment(.trailing)
                                .disabled(!mayModify)
                                .accessibilityIdentifier("wbsTick.document")
                        }
                    }
                    if !mayModify {
                        Text(tick != nil ? "รายการนี้บันทึกโดยบุคคลอื่น คุณไม่มีสิทธิ์แก้ไข" : "คุณไม่มีสิทธิ์บันทึกรายการนี้")
                            .font(.sarabun(12))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }

                if let tick {
                    Section("ประวัติการบันทึก") {
                        let who = TeamDirectory.shared.person(tick.by)?.label ?? tick.by
                        LabeledContent("ผู้บันทึก", value: who)
                        LabeledContent("วันที่บันทึก", value: ThaiFormat.numericDate.string(from: tick.at))
                        if let doc = tick.document, !doc.isEmpty {
                            LabeledContent("เลขที่เอกสาร", value: doc)
                        }
                    }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("อัปเดต WBS \(item.code)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                        .accessibilityIdentifier("wbsTick.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        let cal = MasterSchedule.calendar
                        if isDone {
                            let trimmedDoc = document.trimmingCharacters(in: .whitespacesAndNewlines)
                            let doc = trimmedDoc.isEmpty ? nil : trimmedDoc
                            let by = currentUserEmail.isEmpty ? (tick?.by ?? "unknown") : currentUserEmail
                            let newTick = MasterSchedule.WBSTick(by: by, at: cal.startOfDay(for: completedAt), document: doc)
                            onSave(newTick)
                        } else {
                            onSave(nil)
                        }
                        dismiss()
                    }
                    .disabled(!mayModify)
                    .accessibilityIdentifier("wbsTick.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

import SwiftUI
import TCRoofUI
import TCRoofCore

/// A task's WBS sub-tasks in its sheet (docs/specs/project-plan-wbs.md, step 2; CHA-71): each row's evidence and owner,
/// ticked done by the team. A tick books the row's weight into the plan (`Job.wbsTicks`), so the task's % follows; a
/// document number can go with it. Every row says where its tick came from (`ทีมติ๊ก`, `รายงานประจำวัน`, `Google
/// Sheet`), or that a daily report's pick waits for the team (`รอยืนยัน · รายงานประจำวัน`, a dashed orange box: a tap
/// confirms it). A contractor sees the boxes read only. A row with steps under it (2.5.1 and the Inverter station's
/// steps) is a heading: its steps are ticked, indented under it. A row the WBS Dictionary gives credit steps (`ยื่น 50% →
/// ได้รับ 100%`), or documents to prove it, opens its sheet instead of ticking at once (CHA-84); a step under 100 shows
/// its percent and doesn't count as done.
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
    /// The daily reports' picks waiting for the team, by code (`Job.wbsPending`).
    var pending: [String: RoutineReport.WBSPick] = [:]
    /// The job's external people, for older ticks made by a contractor.
    var contractors: Set<String> = []
    var canConfirm = false
    var confirm: (RoutineReport.WBSPick) -> Void = { _ in }
    /// What the job's ICL sheets and station papers say of the rows (`Job.wbsRecords`).
    var records = MasterSchedule.WBSDictionary.Records()
    private let dictionary = MasterSchedule.WBSDictionary.bundled
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
        let done = tickable.filter { ticks[$0.code]?.isDone == true }.count
        let waiting = tickable.filter { ticks[$0.code] == nil && pending[$0.code] != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("งานย่อย WBS \(done)/\(tickable.count)").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                if waiting > 0 {
                    Text("● รอยืนยัน \(waiting)").font(.sarabun(13, .bold)).foregroundStyle(Theme.warningText)
                        .accessibilityIdentifier("wbs.pendingCount")
                }
                Spacer()
                Text(canTick ? "ติ๊กแล้วนับเข้าแผน MP ตามน้ำหนัก" : "ทีมงานเป็นผู้ติ๊ก | แจ้งงานที่เสร็จในรายงานประจำวัน")
                    .font(.sarabun(12)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.trailing)
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
                                   records: records,
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
        let pick = tick == nil ? pending[item.code] : nil
        let enabled = tick.map(canTakeBack) ?? (pick != nil ? canConfirm : canTick)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if let pick { confirm(pick) } else if tick == nil && needsSheet(item) { activeSheet = .updateTick(item) } else { toggle(item) }
            } label: {
                box(on: tick != nil, waiting: pick != nil, partial: tick.map { !$0.isDone } ?? false)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(item.title.trimmingCharacters(in: .whitespaces))
            .accessibilityValue(tick.map { $0.isDone ? "เสร็จแล้ว" : "นับแล้ว " + MasterSchedule.WBSDictionary.percentText($0.percent ?? 0) }
                                ?? (pick != nil ? "รอยืนยัน" : "ยังไม่เสร็จ"))
            .accessibilityHint(pick != nil && enabled ? "แตะเพื่อยืนยัน" : "")
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
                        sourceLine(item.code, tick: tick, pick: pick)
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
        .background(tick != nil ? Theme.successSoft.opacity(0.45) : pick != nil ? Theme.warningSoft.opacity(0.5) : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    /// A tick needs its sheet: the row has credit steps, or 100 % needs a document no record gives.
    private func needsSheet(_ item: MasterSchedule.WorkItem) -> Bool {
        dictionary.percents(item.code) != [100] || dictionary.problem(item, percent: 100, document: nil, records: records) != nil
    }

    /// `0.25%`, `1.5%`, `5%`: a step's share can be under a tenth.
    static func weight(_ x: Double) -> String {
        x.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX"))) + "%"
    }

    /// Ticked: green with a check; a credit step under 100: green outline, half filled; a daily report's pick waiting:
    /// dashed orange with `?`; else empty.
    private func box(on: Bool, waiting: Bool = false, partial: Bool = false) -> some View {
        let on = on && !partial
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(on ? Theme.success : waiting ? Theme.warningSoft : partial ? Theme.successSoft : Theme.surface)
            if waiting {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                Text("?").font(.sarabun(15, .bold)).foregroundStyle(Theme.warningText)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on || partial ? Theme.success : Theme.pending, lineWidth: 2)
            }
            if partial { Image(systemName: "circle.lefthalf.filled").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.success) }
            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.onPrimary) }
        }
        .frame(width: 26, height: 26)
    }

    /// The row's source chip and who / when: `ทีมติ๊ก` green, `รายงานประจำวัน` / `Google Sheet` blue,
    /// `รอยืนยัน · รายงานประจำวัน` orange, `ยังไม่เสร็จ` grey.
    private func sourceLine(_ code: String, tick: MasterSchedule.WBSTick?, pick: RoutineReport.WBSPick?) -> some View {
        let shown: (label: String, tone: TCFeedTone?, line: String)
        if let tick {
            shown = Self.source(tick, contractors: contractors)
        } else if let pick {
            shown = ("รอยืนยัน · รายงานประจำวัน", .orange, Self.pickLine(pick))
        } else {
            shown = ("ยังไม่เสร็จ", nil, "")
        }
        return HStack(spacing: 6) {
            TCToneChip(shown.label, tone: shown.tone)
            if let p = tick?.percent {
                TCToneChip(stepLabel(code, p), tone: .orange)
            }
            if !shown.line.isEmpty {
                Text(shown.line).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `ยื่น 50%`: a step under 100.
    private func stepLabel(_ code: String, _ p: Double) -> String {
        let pct = MasterSchedule.WBSDictionary.percentText(p)
        return dictionary.entry(code)?.step(p).map { "\($0.label) \(pct)" } ?? pct
    }

    /// The chip, its tone and the who / when line of a tick: `7/12/69 | สมชาย | MOM-001`; a daily report's pick names
    /// its reporter and who confirmed it.
    static func source(_ t: MasterSchedule.WBSTick, contractors: Set<String>) -> (label: String, tone: TCFeedTone?, line: String) {
        let origin = t.origin(contractors: contractors)
        let who = TeamDirectory.shared.person(t.by)?.label ?? t.by
        let day = ThaiFormat.numericDate.string(from: t.at)
        let tone: TCFeedTone?
        switch origin {
        case .team: tone = .green
        case .daily, .sheet, .file: tone = .blue
        case .contractor: tone = nil
        }
        let parts: [String] = origin == .daily
            ? [day, t.reportedBy ?? "", "ยืนยันโดย " + who, t.document ?? ""]
            : [day, who, t.document ?? ""]
        return (origin.label, tone, parts.filter { !$0.isEmpty }.joined(separator: " | "))
    }

    /// `รายงาน 7/12/69 | ช่างเอ | 3 รูป`
    static func pickLine(_ p: RoutineReport.WBSPick) -> String {
        ["รายงาน " + ThaiFormat.numericDate.string(from: p.day), p.reporter, p.photos > 0 ? "\(p.photos) รูป" : "ไม่มีรูป"]
            .filter { !$0.isEmpty }.joined(separator: " | ")
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
/// The team's (`mp.wbs_tick`); a contractor opens it read only. It shows the WBS Dictionary's done criteria and rules
/// of credit (CHA-84), offers the row's credit steps in place of done / not done, and asks for a document number before
/// 100 % when the dictionary lists documents, unless an app record (signed ICL sheets, approved station papers) gives it.
struct WBSTickUpdateSheet: View {
    let item: MasterSchedule.WorkItem
    let tick: MasterSchedule.WBSTick?
    var records = MasterSchedule.WBSDictionary.Records()
    let canTick: Bool
    let canTakeBack: Bool
    let currentUserEmail: String
    let onSave: (MasterSchedule.WBSTick?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isDone: Bool
    @State private var completedAt: Date
    @State private var document: String
    /// The credit step: 100 is done.
    @State private var percent: Double
    private let dictionary = MasterSchedule.WBSDictionary.bundled

    init(item: MasterSchedule.WorkItem,
         tick: MasterSchedule.WBSTick?,
         records: MasterSchedule.WBSDictionary.Records = .init(),
         canTick: Bool,
         canTakeBack: Bool,
         currentUserEmail: String,
         onSave: @escaping (MasterSchedule.WBSTick?) -> Void) {
        self.item = item
        self.tick = tick
        self.records = records
        self.canTick = canTick
        self.canTakeBack = canTakeBack
        self.currentUserEmail = currentUserEmail
        self.onSave = onSave
        let cal = MasterSchedule.calendar
        let done = tick != nil || canTick
        _isDone = State(initialValue: done)
        _completedAt = State(initialValue: tick?.at ?? cal.startOfDay(for: .now))
        _document = State(initialValue: tick?.document ?? "")
        // a tick's own step, else what the app's records give, else the row's first step
        let dict = MasterSchedule.WBSDictionary.bundled
        let start = tick.map { $0.percent ?? 100 } ?? dict.credit(item, records: records)?.percent ?? dict.percents(item.code).first ?? 100
        _percent = State(initialValue: start)
    }

    private var entry: MasterSchedule.WBSDictionary.Entry? { dictionary.entry(item.code) }
    private var problem: String? {
        isDone ? dictionary.problem(item, percent: percent, document: document, records: records) : nil
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

                if let entry, entry.done != nil || entry.credit != nil {
                    Section {
                        if let done = entry.done {
                            Text(done).font(.sarabun(14)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("wbsTick.doneCriteria")
                        }
                        if let credit = entry.credit { LabeledContent("Rules of credit") { Text(credit).multilineTextAlignment(.trailing) } }
                        if let docs = entry.evidence { LabeledContent("หลักฐาน (เอกสาร)") { Text(docs.joined(separator: ", ")).multilineTextAlignment(.trailing) } }
                        if let record = entry.record { LabeledContent("บันทึกในแอป") { Text(record).multilineTextAlignment(.trailing) } }
                        if let c = dictionary.credit(item, records: records) {
                            LabeledContent("ตามบันทึกในแอป", value: "\(c.label) | \(MasterSchedule.WBSDictionary.percentText(c.percent))")
                        }
                    } header: {
                        Text("เกณฑ์เสร็จ (WBS Dictionary)")
                    }
                }

                Section("สถานะการดำเนินงาน") {
                    Toggle(entry?.steps == nil ? "ดำเนินการเสร็จแล้ว" : "นับความคืบหน้า", isOn: $isDone)
                        .disabled(!mayModify)
                        .accessibilityIdentifier("wbsTick.isDone")

                    if isDone, let steps = entry?.steps {
                        Picker("ขั้น", selection: $percent) {
                            ForEach(steps, id: \.percent) { s in
                                Text("\(s.label) \(MasterSchedule.WBSDictionary.percentText(s.percent))").tag(s.percent)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!mayModify)
                        .accessibilityIdentifier("wbsTick.step")
                    }

                    if isDone {
                        DatePicker(percent < 100 ? "วันที่ถึงขั้นนี้" : "วันที่เสร็จ", selection: $completedAt, displayedComponents: .date)
                            .disabled(!mayModify)
                            .accessibilityIdentifier("wbsTick.date")

                        LabeledContent("เลขที่เอกสาร") {
                            TextField("เช่น MOM-001 (ถ้ามี)", text: $document)
                                .multilineTextAlignment(.trailing)
                                .disabled(!mayModify)
                                .accessibilityIdentifier("wbsTick.document")
                        }
                    }
                    if let problem, mayModify {
                        Text(problem).font(.sarabun(13)).foregroundStyle(Theme.danger)
                            .accessibilityIdentifier("wbsTick.problem")
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
                        LabeledContent("ที่มา", value: tick.origin().label)
                        if let reporter = tick.reportedBy { LabeledContent("ผู้รายงาน", value: reporter) }
                        LabeledContent(tick.source == .daily ? "ผู้ยืนยัน" : "ผู้บันทึก", value: who)
                        LabeledContent("วันที่บันทึก", value: ThaiFormat.numericDate.string(from: tick.at))
                        if let p = tick.percent { LabeledContent("ขั้นที่นับแล้ว", value: MasterSchedule.WBSDictionary.percentText(p)) }
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
                            // an edited tick keeps who made it and where it came from; a new one is the team's
                            var newTick = tick ?? MasterSchedule.WBSTick(by: by, at: completedAt, source: .team)
                            let day = cal.startOfDay(for: completedAt)
                            if newTick.undated == true, cal.startOfDay(for: newTick.at) != day { newTick.undated = nil }
                            newTick.at = day
                            newTick.document = doc
                            newTick.percent = percent < 100 ? percent : nil
                            onSave(newTick)
                        } else {
                            onSave(nil)
                        }
                        dismiss()
                    }
                    .disabled(!mayModify || problem != nil)
                    .accessibilityIdentifier("wbsTick.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

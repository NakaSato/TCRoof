import SwiftUI
import TCRoofUI
import TCRoofCore

extension Job {
    /// What the ERC flow reads from the job: the day the MP plan's installation tasks were all finished, the site's
    /// holidays as the days that don't count as working days, and the flow the station's size gives (under 200 kVA, or
    /// 200 and over: `StationDocs.Context.over200kVA`).
    var ercContext: ERCFlow.Context {
        let tasks = MasterSchedule.Task.allCases.filter { $0.part == .construction }
        let finished = tasks.compactMap { scheduleActual.finished[$0.rawValue] }
        let done = finished.count == tasks.count ? finished.max().map(ERCFlow.day) : nil
        return ERCFlow.Context(installDone: done, holidays: Set(routineSettings.holidays),
                               variant: .init(over200kVA: stationContext.over200kVA))
    }
}

/// ลำดับ กกพ. of a station: the steps of its exemption flow by section (seven under 200 kVA, twelve from 200), whose
/// turn each is and when a time limit ends (`ERCFlow`). The team records the day a step happened; a "not passed"
/// answer sends the request round again. A record keeps the flow it was started in (`ERCFlow.Record.variant(_:)`).
struct ERCFlowRows: View {
    @Bindable var job: Job
    let library: StationDocs.Library
    /// Opens a submission's papers (steps 3 and 7).
    let openPackage: (StationDocs.Package) -> Void

    @State private var recording: ERCFlow.Step?

    private var record: ERCFlow.Record { job.stationDocs.erc ?? ERCFlow.Record() }
    private var ctx: ERCFlow.Context { job.ercContext }
    private var variant: ERCFlow.Variant { record.variant(ctx) }

    var body: some View {
        let states = ERCFlow.states(record, ctx), variant = variant
        Group {
            PadSection { summary(states) }
            ForEach(variant.sections, id: \.self) { section in
                PadSection(section.title(in: variant)) {
                    ForEach(variant.steps.filter { $0.section == section }) { step in
                        row(step, states[step] ?? .blocked)
                        if states[step] == .open, let package = package(step) {
                            Button { openPackage(package) } label: {
                                Label("ดูเอกสารชุด\(package.title)", systemImage: "folder").font(.sarabun(15, relativeTo: .subheadline))
                            }
                            .frame(minHeight: touchMin)
                            .accessibilityIdentifier("erc.papers." + package.rawValue)
                        }
                    }
                    if section == .connect, variant == .from200 { wantsPK2Picker }
                }
            }
            history
        }
        .sheet(item: $recording) { step in
            ERCStepSheet(step: step) { day, result, note in
                update { $0.add(step, day: day, result: result, note: note) }
            }
        }
    }

    /// Every change first keeps the flow the record follows now, so it stays in it if the station's size moves.
    private func update(_ change: (inout ERCFlow.Record) -> Void) {
        var station = job.stationDocs
        var r = station.erc ?? ERCFlow.Record()
        r.pin(ctx)
        change(&r)
        station.erc = r
        job.stationDocs = station
    }

    // MARK: Summary

    private func summary(_ states: [ERCFlow.Step: ERCFlow.State]) -> some View {
        let now = ERCFlow.current(record, ctx)
        let ours = now.filter { states[$0] == .open }
        let theirs = now.filter { states[$0] != .open }
        return VStack(alignment: .leading, spacing: 4) {
            Text(now.isEmpty ? "ครบทุกขั้นแล้ว" : ours.isEmpty ? "รอหน่วยงานอื่น" : "ถึงคิวทีมเรา: " + ours.map(label).joined(separator: " | "))
                .font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
            if !theirs.isEmpty {
                Text("รออยู่: " + theirs.map { "\(label($0)) (\($0.party.title))" }.joined(separator: " | "))
                    .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            Text(variant.title + " | วันทำการไม่นับเสาร์ อาทิตย์ และวันหยุดของหน้างาน")
                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            if variant == .under200 {
                Text("การไฟฟ้าส่งข้อมูลให้สำนักงาน กกพ. เองหลังตรวจผ่าน ทีมเราไม่ต้องยื่นแจ้งยกเว้นหรือ พค.2")
                    .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            flowMismatch
        }
    }

    private static func sizeText(_ v: ERCFlow.Variant) -> String { v == .under200 ? "ต่ำกว่า 200 kVA" : "200 kVA ขึ้นไป" }

    /// The record was started in the other size's flow than the station has now: it stays there, and the team can
    /// move it where nothing recorded would be hidden.
    @ViewBuilder private var flowMismatch: some View {
        if !record.events.isEmpty, variant != ctx.variant {
            Text("บันทึกไว้ตามลำดับ\(Self.sizeText(variant)) | ขนาดสถานีตอนนี้\(Self.sizeText(ctx.variant))")
                .font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.pending)
            if record.canSwitch(to: ctx.variant) {
                Button {
                    update { $0.variant = ctx.variant }
                } label: {
                    Label("เปลี่ยนเป็นลำดับ\(Self.sizeText(ctx.variant))", systemImage: "arrow.triangle.swap")
                        .font(.sarabun(15, relativeTo: .subheadline)).frame(minHeight: touchMin)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                .accessibilityIdentifier("erc.switchFlow")
            }
        }
    }

    private func label(_ step: ERCFlow.Step) -> String {
        step.number(in: variant).map { "ข้อ \($0)" } ?? "ติดตั้ง"
    }

    // MARK: Rows

    private func row(_ step: ERCFlow.Step, _ state: ERCFlow.State) -> some View {
        let canRecord: Bool = { switch state { case .open, .waiting: true; default: false } }()
        return Button { recording = step } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(step.number(in: variant).map(String.init) ?? "–")
                    .font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.inkMuted)
                    .frame(width: 28, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title).font(.sarabun(15, .semibold, relativeTo: .subheadline)).multilineTextAlignment(.leading)
                        .foregroundStyle(state == .blocked || state == .notNeeded ? Theme.inkMuted : Theme.navy)
                    let d = detail(step, state)
                    if !d.isEmpty {
                        Text(d).font(.sarabun(12, relativeTo: .caption)).multilineTextAlignment(.leading)
                            .foregroundStyle(isOverdue(step, state) ? Theme.dangerText : Theme.inkMuted)
                    }
                }
                Spacer()
                chip(step, state)
            }
            .frame(minHeight: touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canRecord)   // not .disabled: a finished step keeps its colours
        .accessibilityIdentifier("erc." + step.rawValue)
    }

    private func thai(_ day: String) -> String { ERCFlow.date(day).map(RoutineReport.thaiDate) ?? day }

    private func left(_ step: ERCFlow.Step, _ state: ERCFlow.State) -> Int? {
        guard case .waiting(_, let due?) = state else { return nil }
        return ERCFlow.daysLeft(step, due: due, ctx)
    }

    private func isOverdue(_ step: ERCFlow.Step, _ state: ERCFlow.State) -> Bool { (left(step, state) ?? 0) < 0 }

    private func detail(_ step: ERCFlow.Step, _ state: ERCFlow.State) -> String {
        let failed = record.failedRounds(step)
        let rounds = failed > 0 ? " | ไม่ผ่านมาแล้ว \(failed) รอบ" : ""
        switch state {
        case .done(let day): return thai(day) + rounds
        case .open: return "แตะเพื่อบันทึกวัน" + papers(step)
        case .waiting(let since, let due):
            var s = "รอตั้งแต่ \(thai(since))"
            if let due, let n = left(step, state) {
                let unit = step.limit?.working == true ? "วันทำการ" : "วัน"
                s += " | ครบกำหนด \(thai(due)) " + (n >= 0 ? "(เหลือ \(n) \(unit))" : "(เกินกำหนด \(-n) \(unit))")
            }
            return s + rounds
        case .blocked: return ""
        case .notNeeded: return step == .pk2ToUtility ? "การไฟฟ้าไม่ได้ขอ" : "ไม่ได้บันทึกวัน"
        }
    }

    /// The submission behind a request of ours.
    private func package(_ step: ERCFlow.Step) -> StationDocs.Package? {
        step == .pk2Request ? .pk2 : step == .inspectionRequest ? .gridConnection : nil
    }

    /// How far the papers of the submission behind a request are.
    private func papers(_ step: ERCFlow.Step) -> String {
        guard let package = package(step) else { return "" }
        let p = StationDocs.progress(package, station: job.stationDocs, library: library, job.stationContext)
        return " | เอกสารชุด\(package.title)พร้อม \(p.ready)/\(p.total)"
    }

    @ViewBuilder private func chip(_ step: ERCFlow.Step, _ state: ERCFlow.State) -> some View {
        switch state {
        case .done: TCStatusChip("เสร็จ", fill: Theme.okSoft, text: Theme.okText)
        case .open: TCStatusChip("ทีมเรา", fill: Theme.warningSoft, text: Theme.pending)
        case .waiting:
            if isOverdue(step, state) { TCStatusChip("รอ" + step.party.title, fill: Theme.dangerSoft, text: Theme.dangerText) }
            else { TCStatusChip("รอ" + step.party.title, fill: Theme.primarySoft, text: Theme.navy) }
        case .blocked: TCStatusChip("ยังไม่ถึง", fill: Theme.segmentTrack, text: Theme.inkMuted)
        case .notNeeded: TCStatusChip("ไม่ใช้", fill: Theme.segmentTrack, text: Theme.inkMuted)
        }
    }

    private var wantsPK2Picker: some View {
        PadPicker("การไฟฟ้าขอ พค.2 ก่อนขนานไฟ", selection: Binding(
            get: { record.utilityWantsPK2.map { $0 ? 1 : 0 } ?? -1 },
            set: { v in update { $0.utilityWantsPK2 = v < 0 ? nil : v == 1 } })) {
            Text("ยังไม่รู้").tag(-1)
            Text("ขอ").tag(1)
            Text("ไม่ขอ").tag(0)
        }
    }

    // MARK: History

    @ViewBuilder private var history: some View {
        if !record.events.isEmpty {
            PadSection("ประวัติ") {
                ForEach(Array(record.events.enumerated().reversed()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(thai(e.day)) | \(e.step.title)" + (e.result == .failed ? " | ไม่ผ่าน" : e.result == .passed ? " | ผ่าน" : ""))
                            .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(e.result == .failed ? Theme.dangerText : Theme.navy)
                        if !e.note.isEmpty { Text(e.note).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted) }
                    }
                    .frame(minHeight: touchMin, alignment: .leading)
                }
                Button("ลบรายการล่าสุด", role: .destructive) { update { $0.events.removeLast() } }
                    .foregroundStyle(Theme.danger).frame(minHeight: touchMin)
            }
        }
    }
}

/// The day a step happened, the utility's answer where it has one, and a note.
struct ERCStepSheet: View {
    let step: ERCFlow.Step
    let save: (String, ERCFlow.Result?, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var day = Date.now
    @State private var result = ERCFlow.Result.passed
    @State private var note = ""

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection {
                    Text(step.title).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    LabeledContent("ฝ่ายที่ทำ", value: step.party.title)
                    DatePicker("วันที่", selection: $day, in: ...Date.now, displayedComponents: .date)
                    if step.hasResult {
                        PadPicker("ผล", selection: $result) {
                            Text("ผ่าน").tag(ERCFlow.Result.passed)
                            Text("ไม่ผ่าน").tag(ERCFlow.Result.failed)
                        }
                    }
                    TextField("หมายเหตุ เช่น เลขที่หนังสือ เงื่อนไขที่ได้รับ", text: $note, axis: .vertical)
                } footer: {
                    if step.hasResult { Text("ไม่ผ่าน = แก้แล้วต้องยื่นใหม่ ระยะเวลาเริ่มนับใหม่จากวันที่ยื่นรอบถัดไป") }
                }
            }
            .navigationTitle("บันทึกขั้นตอน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") { save(ERCFlow.day(day), step.hasResult ? result : nil, note); dismiss() }
                }
            }
        }
    }
}

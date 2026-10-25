import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ExcelExport

/// `เริ่มจากแม่แบบ` (ตั้งค่าแผน): a case of the team's install templates (`MPTemplates`), by site type, กันย้อน and inverter
/// size, moved to the station's kickoff. It goes on the job as an import of that file would (`MPWorkbookFlow.install`):
/// the plan replaces the job's, booked progress stays under the new weights, and the moved file becomes the station's
/// plan workbook for export.
struct MPTemplateSheet: View {
    @Bindable var job: Job
    /// The kickoff and size the setup sheet has so far.
    let input: MasterSchedule.Input
    /// The job's new plan, for the setup sheet to go on from.
    let applied: (MasterSchedule.Input) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var cases: [MPTemplates.Case] = []
    @State private var site = ""
    @State private var backfeed = "HV"
    @State private var over200kVA: Bool
    @State private var kickoff: Date
    @State private var working = false
    @State private var failure: String?

    init(job: Job, input: MasterSchedule.Input, applied: @escaping (MasterSchedule.Input) -> Void) {
        self.job = job; self.input = input; self.applied = applied
        _over200kVA = State(initialValue: input.over200kVA)
        _kickoff = State(initialValue: MasterSchedule.calendar.startOfDay(for: input.kickoff))
    }

    private var sites: [String] { cases.reduce(into: []) { if !$0.contains($1.site) { $0.append($1.site) } } }
    private var picked: MPTemplates.Case? {
        cases.first { $0.site == site && $0.backfeed == backfeed && $0.over200kVA == over200kVA }
    }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection("แม่แบบ") {
                    LabeledContent("ประเภทหน้างาน") {
                        Picker("ประเภทหน้างาน", selection: $site) {
                            ForEach(sites, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("mpTemplate.site")
                    }
                    Picker("กันย้อน", selection: $backfeed) {
                        Text("HV").tag("HV")
                        Text("LV").tag("LV")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("mpTemplate.backfeed")
                    Picker("Inverter", selection: $over200kVA) {
                        Text("ต่ำกว่า 200 kVA").tag(false)
                        Text("ตั้งแต่ 200 kVA").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("mpTemplate.inverter")
                    DatePicker("Kick off", selection: $kickoff, displayedComponents: .date)
                } footer: {
                    Text("ทุกงานเลื่อนตามวัน Kick off ระยะเวลาและน้ำหนักตามแม่แบบ แก้ต่อได้ในตั้งค่าแผนหรือในไฟล์ Excel")
                }
                PadSection("แผนที่จะได้") {
                    if let c = picked {
                        LabeledContent(c.id, value: c.title)
                            .accessibilityIdentifier("mpTemplate.case")
                    } else {
                        Text(cases.isEmpty ? "กำลังอ่านแม่แบบ…" : "ไม่มีแม่แบบของกรณีนี้").foregroundStyle(Theme.inkMuted)
                    }
                } footer: {
                    if job.scheduleInput != nil {
                        Text("แทนแผน MP เดิมของสถานีนี้ ความก้าวหน้าที่บันทึกไว้คงอยู่ตามน้ำหนักใหม่")
                    }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("เริ่มจากแม่แบบ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("ใช้แม่แบบ", action: apply).disabled(picked == nil)
                            .accessibilityIdentifier("mpTemplate.apply")
                    }
                }
            }
            .alert("ใช้แม่แบบไม่ได้", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("ตกลง", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
            .task { await load() }
        }
    }

    private func load() async {
        cases = await Task.detached { MPTemplates.cases() }.value
        if !sites.contains(site) { site = sites.first ?? "" }
    }

    private func apply() {
        guard let c = picked else { return }
        working = true
        let kickoff = kickoff
        Task {
            defer { working = false }
            do {
                let r = try await Task.detached { try MPTemplates.plan(c, kickoff: kickoff) }.value
                MPWorkbookFlow.install(r.imported, data: r.data, name: "แผนงาน MP \(job.stationName) (แม่แบบ \(c.id)).xlsx", on: job)
                try? context.save()
                if let new = job.scheduleInput { applied(new) }
                dismiss()
            } catch {
                failure = (error as? MPWorkbook.Failure)?.message ?? error.localizedDescription
            }
        }
    }
}

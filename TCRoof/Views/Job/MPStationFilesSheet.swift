import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ExcelExport

/// เพิ่มสถานีจากไฟล์แผน: the 102 PWA stations' own plan files (`MPTemplates.cases`, `Project_Plan_TCRoof/2_…`) that no
/// station in the app is yet (`MPTemplates.missing`), each made a งาน PWA job with its own plan: the file kept as the
/// station's plan file, its dates and progress, and its project facts (the station code `P3-001` among them, which the
/// Master Plan sheet pairs it by). Sync takes the new jobs to Firestore like any other.
struct MPStationFilesSheet: View {
    /// The app's jobs, to leave out the stations it has.
    let jobs: [Job]
    /// Called with the stations added and the codes of the files that couldn't be read.
    let done: (_ added: Int, _ failed: [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var missing: [MPTemplates.Case] = []
    @State private var present = 0
    @State private var picked = Set<String>()
    @State private var loaded = false
    /// While adding: how many are done.
    @State private var progress: Int?
    @State private var failures: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    if !missing.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(missing) { c in
                                row(c)
                                if c.id != missing.last?.id { Divider().padding(.leading, 16) }
                            }
                        }
                        .cardStyle(padding: 0)
                    }
                }
                .padding(isPhone ? 16 : 24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.pageGradient.ignoresSafeArea())
            .navigationTitle("เพิ่มสถานีจากไฟล์แผน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }.disabled(progress != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม \(picked.count) สถานี", action: add)
                        .disabled(picked.isEmpty || progress != nil)
                        .accessibilityIdentifier("stationFiles.add")
                }
            }
            .interactiveDismissDisabled(progress != nil)
        }
        .task { load() }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress {
                Text("กำลังเพิ่ม \(progress) / \(picked.count) สถานี")
                    .font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                ProgressView(value: Double(progress), total: Double(max(picked.count, 1))).tint(Theme.primary)
            } else if !loaded {
                ProgressView()
            } else {
                Text(missing.isEmpty ? "ทุกสถานีมีในแอปแล้ว" : "ยังไม่มีในแอป \(missing.count) สถานี | เลือก \(picked.count)")
                    .font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .accessibilityIdentifier("stationFiles.summary")
                Text("แต่ละสถานีเป็นงาน PWA ใหม่ ใช้ไฟล์แผนของสถานีเอง วันและความคืบหน้าตามไฟล์ ข้อมูลโครงการตามไฟล์ (รหัสสถานี สาขา วิศวกร ผรม.) "
                     + "และซิงก์ขึ้น Firebase ให้ทุกเครื่องของทีม | มีในแอปแล้ว \(present) สถานี")
                    .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                if !missing.isEmpty {
                    HStack(spacing: 16) {
                        Button("เลือกทั้งหมด") { picked = Set(missing.map(\.id)) }
                            .accessibilityIdentifier("stationFiles.all")
                        Button("ไม่เลือก") { picked = [] }
                            .accessibilityIdentifier("stationFiles.none")
                    }
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                    .frame(minHeight: touchMin)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func row(_ c: MPTemplates.Case) -> some View {
        let on = picked.contains(c.id)
        return Button {
            if on { picked.remove(c.id) } else { picked.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.sarabun(20, relativeTo: .title3)).foregroundStyle(on ? Theme.primary : Theme.inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.id)  \(c.name)").font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text([c.branch, c.kWp.map { "\($0.formatted()) kWp" } ?? "", "กันย้อน \(c.backfeed)"]
                        .filter { !$0.isEmpty }.joined(separator: " | "))
                        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: touchMin, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(progress != nil)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("stationFiles.row")
    }

    private func load() {
        guard !loaded else { return }
        let all = MPTemplates.cases()
        let existing = jobs.map { j in
            MPTemplates.Existing(name: j.stationName, codes: [j.code, j.stationDocs.code ?? ""].joined(separator: " "),
                                 kWp: j.capacityKW > 0 ? j.capacityKW : nil)
        }
        missing = MPTemplates.missing(existing, among: all)
        present = all.count - missing.count
        picked = Set(missing.map(\.id))
        loaded = true
    }

    /// Each picked station in turn: its file read off the main thread, then a new job given its plan and facts
    /// (`MPWorkbookFlow.install`, as `เริ่มจากแม่แบบ` does with the station's own file). Saved every ten.
    private func add() {
        let todo = missing.filter { picked.contains($0.id) }
        progress = 0
        failures = []
        Task {
            var codes = Set((try? context.fetch(FetchDescriptor<Job>()))?.map(\.code) ?? [])
            var added = 0
            for c in todo {
                do {
                    let r = try await Task.detached { try MPTemplates.plan(c, kickoff: nil) }.value
                    var code = SampleData.newJobCode()
                    while codes.contains(code) { code = SampleData.newJobCode() }
                    codes.insert(code)
                    let job = Job(code: code, projectName: c.name, customerName: c.branch.isEmpty ? c.name : c.branch,
                                  province: "", capacityKW: c.kWp ?? 0, team: .t1, status: .confirmed,
                                  surveyDate: Job.unscheduled, installStart: Job.unscheduled, installDays: 1)
                    job.kind = .pwa
                    context.insert(job)
                    // the station's own file: every fact it has fills the new job, the station code with them
                    MPWorkbookFlow.install(r.imported, data: r.data, name: c.url.lastPathComponent, on: job,
                                           setup: ProjectSetup.defaultFields(job.setupChanges(r.imported.setup)))
                    added += 1
                    if added % 10 == 0 { try? context.save() }
                } catch {
                    failures.append(c.id)
                }
                progress = (progress ?? 0) + 1
            }
            try? context.save()
            progress = nil
            dismiss()
            done(added, failures)
        }
    }
}

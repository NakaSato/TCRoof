import SwiftUI
import TCRoofUI
import TCRoofCore
import SurveyUI

/// Ties the NO.224 survey reports (SurveyKit files, synced as `pwaSurveys`) to TCRoof jobs through `Job.syncID`.
extension Job {
    /// Old records made before cloud sync have no id; give them one so a report can point at them.
    @discardableResult func ensureSyncID() -> String {
        if let id = syncID { return id }
        let id = UUID().uuidString
        syncID = id
        return id
    }

    /// Customer details already typed in TCRoof, for the report's cover page.
    var surveyPrefill: SurveyModel.Prefill {
        SurveyModel.Prefill(projectName: projectName, coordinator: customerName, phone: phone,
                            address: [address, province].filter { !$0.isEmpty }.joined(separator: " "),
                            capacityKW: capacityKW, date: surveyDate)
    }

    /// "TC-0012 · สถานีสูบน้ำบ้านนา"
    var linkLabel: String { projectName.isEmpty ? code : "\(code) · \(projectName)" }
}

/// A report to open, for `navigationDestination(item:)`.
struct OpenSurveyReport: Identifiable, Hashable { let id: UUID }

/// Short line for a report in TCRoof lists: "NO.215 · 28/9/2569 · 64%".
func surveyReportSummary(_ r: TCRoofCore.Job) -> String {
    let parts = ["NO.\(r.docNo.isEmpty ? "—" : r.docNo)", r.values.text("date").isEmpty ? nil : ISODate.thai(r.values.text("date")),
                 "กรอกแล้ว \(r.completion.percent)%"]
    return parts.compactMap { $0 }.joined(separator: " · ")
}

/// Job detail card: the job's NO.224 reports, a new one pre-filled from the job, or an existing one linked to it.
struct PWASurveyCard: View {
    @Bindable var job: Job
    @State private var model = SurveyModel.shared
    @State private var pickTemplate = false
    @State private var open: OpenSurveyReport?
    @AppStorage("userName") private var userName = ""

    private var linked: [TCRoofCore.Job] { job.syncID.map { model.jobs(linkedTo: $0) } ?? [] }
    /// Reports not tied to any job on this device (never linked, or their job was deleted).
    private var unlinked: [TCRoofCore.Job] {
        model.jobs.filter { r in r.jobSyncID.map { model.linkedJobLabel?($0) == nil } ?? true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("แบบสำรวจ กปภ. NO.224").font(.headline).foregroundStyle(Theme.navy)
                Spacer()
                if !unlinked.isEmpty {
                    Menu {
                        Section("ผูกแบบสำรวจที่มีอยู่กับงานนี้") {
                            ForEach(unlinked) { r in
                                Button("\(r.projectName.isEmpty ? "(ไม่มีชื่อโครงการ)" : r.projectName) — \(surveyReportSummary(r))") { link(r) }
                            }
                        }
                    } label: { Label("ผูกแบบที่มีอยู่", systemImage: "link") }
                    .font(.subheadline.weight(.semibold))
                }
                Button { pickTemplate = true } label: { Label("สร้างแบบ กปภ.", systemImage: "plus") }
                    .font(.subheadline.weight(.semibold))
            }
            if linked.isEmpty {
                Text("สร้างแบบสำรวจ NO.224 จากงานนี้ ข้อมูลลูกค้า ที่อยู่ และขนาดระบบจะกรอกให้อัตโนมัติ")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(linked) { r in
                NavigationLink { SurveyReportEditor(jobID: r.id) } label: {
                    HStack {
                        Image(systemName: "doc.text.image").foregroundStyle(Theme.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.projectName.isEmpty ? "แบบสำรวจ กปภ." : r.projectName)
                            Text(surveyReportSummary(r)).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.navy)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { model.link(r.id, to: nil) } label: { Label("ยกเลิกการผูกกับงานนี้", systemImage: "link.badge.plus") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(isPresented: $pickTemplate) {
            SurveyTemplatePicker { t in
                let engineer = model.settings.engineer.isEmpty ? userName : model.settings.engineer
                let r = model.create(t, engineer: engineer, linkedTo: job.ensureSyncID(), prefill: job.surveyPrefill)
                pickTemplate = false
                open = OpenSurveyReport(id: r.id)
            }
        }
        .navigationDestination(item: $open) { SurveyReportEditor(jobID: $0.id) }
        .onAppear { model.reload() }
        #if DEBUG
        // `-pwaLinkDemo YES` creates a linked report on first appear, for simulator checks of the prefill
        .task {
            guard UserDefaults.standard.bool(forKey: "pwaLinkDemo"), linked.isEmpty else { return }
            _ = model.create(JobTemplate.all[0], engineer: userName, linkedTo: job.ensureSyncID(), prefill: job.surveyPrefill)
        }
        #endif
    }

    private func link(_ r: TCRoofCore.Job) {
        model.link(r.id, to: job.ensureSyncID(), prefill: job.surveyPrefill)
    }
}

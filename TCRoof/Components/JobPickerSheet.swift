import SwiftUI
import TCRoofUI
import SwiftData

struct JobPickerSheet: View {
    let title: String
    let onPick: (Job) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var search = ""
    @FocusState private var searching: Bool

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PhoneSearchField(text: $search, focused: $searching, prompt: "ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ")
                PadSection {
                    ForEach(jobs.filter { $0.matches(search) }) { row($0) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
            }
        }
    }

    private func row(_ job: Job) -> some View {
        Button {
            onPick(job)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.code).bold()
                    TeamTag(team: job.team)
                    Spacer()
                    TCStatusChip(job.status.title, fill: job.status.color.opacity(0.12), text: job.status.color)
                }
                Text(job.projectName).font(.sarabun(15, relativeTo: .subheadline))
                Text("\(job.province) | ติดตั้ง \(job.shown(job.installStart, none: "ยังไม่กำหนด"))")
                    .font(.sarabun(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.navy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

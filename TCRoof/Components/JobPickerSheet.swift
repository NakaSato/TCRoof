import SwiftUI
import TCRoofUI
import SwiftData

struct JobPickerSheet: View {
    let title: String
    let onPick: (Job) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(jobs.filter { $0.matches(search) }) { job in
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
                        Text(job.projectName).font(.subheadline)
                        Text("\(job.province) · ติดตั้ง \(job.installStart.thaiLong)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.navy)
                }
            }
            .searchable(text: $search, prompt: "ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
            }
        }
    }
}

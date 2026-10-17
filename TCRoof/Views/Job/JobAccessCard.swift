import SwiftUI
import TCRoofUI
import TCRoofCore

/// Who works on the job beyond the team (docs/reference/roles/user-roles.json): the external engineers and
/// contractors assigned to it, who see and fill only their jobs, and the internal engineer supervising it
/// (ผู้ควบคุมงาน), who may sign its final acceptance. Shown to the members who may assign (`job.assign_external`).
struct JobAccessCard: View {
    @Bindable var job: Job
    @Environment(\.permissions) private var permissions
    @Environment(\.modelContext) private var context
    @State private var newEmail = ""
    @State private var supervisor = ""

    var body: some View {
        if permissions.can(.assignExternal, on: job.access) { card }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ผู้รับเหมา / วิศวกรภายนอก").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            Text("บัญชี Google ที่เห็นและทำงานนี้ได้: รายงานประจำวัน ทดสอบ IEC แนบไฟล์หน้างาน · ไม่เห็นเบอร์และที่อยู่ลูกค้า")
                .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            if job.externals.isEmpty {
                Text("ยังไม่ได้มอบหมาย").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            ForEach(job.externals, id: \.self) { email in
                HStack {
                    Label(email, systemImage: "person.crop.circle").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                    Spacer()
                    Button(role: .destructive) { remove(email) } label: { Image(systemName: "xmark.circle.fill") }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("เอา \(email) ออก")
                }
            }
            HStack(spacing: 12) {
                TCTextField("อีเมล เช่น foreman@contractor.co.th", text: $newEmail, keyboard: .emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit(add)
                Button("มอบหมาย", action: add)
                    .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                    .disabled(!Self.isEmail(newEmail))
            }
            Divider()
            TCFieldLabel("ผู้ควบคุมงาน (ลงนามตรวจรับงานขั้นสุดท้ายได้)")
            TCTextField("อีเมลวิศวกรของเรา", text: $supervisor, keyboard: .emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit(saveSupervisor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .onAppear { supervisor = job.supervisorEmail ?? "" }
        .onChange(of: supervisor) { _, v in if v.isEmpty || Self.isEmail(v) { saveSupervisor() } }
    }

    static func isEmail(_ s: String) -> Bool {
        let parts = Permissions.normalized(s).split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    private func add() {
        guard Self.isEmail(newEmail) else { return }
        job.externals.append(newEmail)
        newEmail = ""
        try? context.save()
    }

    private func remove(_ email: String) {
        job.externals.removeAll { $0 == email }
        try? context.save()
    }

    private func saveSupervisor() {
        let v = Permissions.normalized(supervisor)
        let next: String? = v.isEmpty ? nil : v
        guard job.supervisorEmail != next else { return }
        job.supervisorEmail = next
        try? context.save()
    }
}

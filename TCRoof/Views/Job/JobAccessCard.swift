import SwiftUI
import TCRoofUI
import TCRoofCore

/// Who works on the job (docs/reference/roles/user-roles.json): our team members on it (`job.assign_team`), whose job
/// it is in `งานของฉัน` and who hear its news first; the external engineers and contractors assigned to it, who see
/// and fill only their jobs; and the internal engineer supervising it (ผู้ควบคุมงาน), who may sign its final
/// acceptance. Each part is shown to the members who may assign it.
struct JobAccessCard: View {
    @Bindable var job: Job
    @Environment(\.permissions) private var permissions
    @Environment(\.modelContext) private var context
    @State private var newEmail = ""
    @State private var newMember = ""
    @State private var supervisor = ""
    private var directory = TeamDirectory.shared

    var body: some View {
        let team = permissions.can(.assignTeam, on: job.access), externals = permissions.can(.assignExternal, on: job.access)
        if team || externals {
            VStack(alignment: .leading, spacing: 12) {
                if team { teamPart }
                if team && externals { Divider() }
                if externals { externalPart }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .onAppear { supervisor = job.supervisorEmail ?? "" }
            .onChange(of: supervisor) { _, v in if v.isEmpty || Self.isEmail(v) { saveSupervisor() } }
        }
    }

    /// Our team members on the job: it shows in their `งานของฉัน`, and its news reaches them (and the supervisor) rather
    /// than the whole team. It opens nothing: the team sees every job.
    private var teamPart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ทีมงานของเรา").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            Text("งานนี้อยู่ใน งานของฉัน ของคนในทีมงาน · แจ้งเตือนรายงานและผลทดสอบของงานนี้ไปถึงทีมงานและผู้ควบคุมงาน ไม่ใช่ทั้งทีม")
                .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            if job.teamMembers.isEmpty {
                Text("ยังไม่ได้กำหนด · แจ้งเตือนไปถึงทุกคนในทีม").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            ForEach(job.teamMembers, id: \.self) { email in
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(directory.person(email)?.label ?? email).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                            if let p = directory.person(email), !p.name.isEmpty {
                                Text(email).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                            } else if !directory.people.isEmpty, directory.person(email) == nil {
                                // not in the team directory: a slip, a personal address, or someone not on the team
                                Text("ไม่อยู่ในรายชื่อทีม").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.warningText)
                            }
                        }
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(Theme.navy)
                    }
                    Spacer()
                    Button(role: .destructive) { removeMember(email) } label: { Image(systemName: "xmark.circle.fill") }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("เอา \(email) ออกจากทีมงาน")
                }
            }
            let choices = directory.people.filter { !job.teamMembers.contains($0.email) }
            if !choices.isEmpty {
                Menu {
                    ForEach(choices) { p in
                        Button(p.name.isEmpty ? p.email : "\(p.name) · \(p.email)") { addMember(p.email) }
                    }
                } label: {
                    Label("เลือกจากรายชื่อทีม", systemImage: "person.badge.plus")
                        .font(.sarabun(17, .semibold, relativeTo: .body))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                .accessibilityIdentifier("jobAccess.teamPicker")
            }
            HStack(spacing: 12) {
                TCTextField("หรือพิมพ์อีเมล เช่น somchai@tcroof.co.th", text: $newMember, keyboard: .emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit(addMember)
                    .accessibilityIdentifier("jobAccess.teamEmail")
                Button("เพิ่มในทีม", action: addMember)
                    .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                    .disabled(!Self.isEmail(newMember))
            }
        }
    }

    private var externalPart: some View {
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

    private func addMember() {
        guard Self.isEmail(newMember) else { return }
        addMember(newMember)
        newMember = ""
    }

    private func addMember(_ email: String) {
        job.teamMembers.append(email)
        try? context.save()
    }

    private func removeMember(_ email: String) {
        job.teamMembers.removeAll { $0 == email }
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

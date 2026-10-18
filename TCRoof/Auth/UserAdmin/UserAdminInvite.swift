import SwiftUI
import TCRoofCore
import TCRoofUI

/// `เพิ่มผู้ใช้ด้วยอีเมล` (`states/06`): an email with its role, and the jobs of an external person. It adds a pending
/// row; `บันทึกและซิงก์` writes `members/<email>`. The board's `ทีม` chips are left out: a member has no team field.
struct InviteSheet: View {
    let store: UserAdminStore
    /// The email added, or nil when cancelled.
    var done: (String?) -> Void

    @State private var email = InviteSheet.debugEmail
    @State private var name = ""
    /// Picked by hand; else suggested from the email's domain.
    @State private var pickedRole: UserRole?
    @State private var jobs: [String] = []

    /// `-userAdminInviteEmail <email>` (DEBUG) opens the sheet with an email typed.
    private static var debugEmail: String {
        #if DEBUG
        UserDefaults.standard.string(forKey: "userAdminInviteEmail") ?? ""
        #else
        ""
        #endif
    }

    private var valid: String? { MemberDirectory.validEmail(email) }
    private var duplicate: Bool { valid.map(store.isListed) ?? false }
    private var companyDomain: Bool {
        guard let valid, let domain = store.companyDomain, !domain.isEmpty else { return false }
        return valid.hasSuffix("@" + domain)
    }
    private var role: UserRole { pickedRole ?? (valid == nil || companyDomain ? .internalTeam : .external) }
    private var ok: Bool { valid != nil && !duplicate }

    var body: some View {
        ZStack {
            Theme.navySolid.opacity(0.45).ignoresSafeArea().onTapGesture { done(nil) }
            VStack(spacing: 0) {
                head
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        emailField
                        if role != .external { nameField }
                        roleField
                        if role == .external { jobsField }
                        note
                    }
                    .padding(.horizontal, 22).padding(.vertical, 18)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                buttons
            }
            .frame(width: 560)
            .frame(maxHeight: 860)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Theme.navySolid.opacity(0.35), radius: 30, y: 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("เพิ่มผู้ใช้ด้วยอีเมล")
        }
    }

    private var head: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 40, height: 40).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text("เพิ่มผู้ใช้ด้วยอีเมล").font(.sarabun(18, .bold)).foregroundStyle(Theme.navy)
                Text("สร้าง members/<email> · เข้าแอปด้วย Google ของอีเมลนี้เท่านั้น").font(.sarabun(12.5)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button { done(nil) } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 44, height: 44).background(Theme.stripeLight, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
    }

    private var emailMessage: (String, Color) {
        if email.isEmpty { return ("ใช้อีเมลบัญชี Google ที่จะใช้เข้าแอป", Theme.inkMuted) }
        if valid == nil { return ("รูปแบบอีเมลไม่ถูกต้อง", Theme.dangerText) }
        if duplicate { return ("อีเมลนี้อยู่ในรายชื่อแล้ว", Theme.dangerText) }
        return (companyDomain ? "✓ โดเมนบริษัท · แนะนำ ทีมภายใน" : "✓ โดเมนภายนอก · แนะนำ วิศวกรภายนอก / ผู้รับเหมา", Theme.successText)
    }

    private var emailField: some View {
        let (msg, color) = emailMessage
        let bad = !email.isEmpty && !ok
        return VStack(alignment: .leading, spacing: 6) {
            (Text("อีเมล ") + Text("*").foregroundColor(Theme.dangerText)).font(.sarabun(13, .bold)).foregroundStyle(Theme.projectTabInk)
            TextField("name@company.com", text: $email)
                .font(.sarabun(15)).foregroundStyle(Theme.navy)
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 14).frame(minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(bad ? Theme.dangerText : ok ? Theme.success : Theme.borderSubtle, lineWidth: email.isEmpty ? 1 : 2))
                .accessibilityLabel("อีเมล")
                .accessibilityIdentifier("userAdmin.inviteEmail")
            Text(msg).font(.sarabun(12.5, .semibold)).foregroundStyle(color)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("ชื่อที่แสดง ") + Text("ไม่บังคับ · ใช้ในรายชื่อทีม").font(.sarabun(13)).foregroundColor(Theme.muted))
                .font(.sarabun(13, .bold)).foregroundStyle(Theme.projectTabInk)
            TextField("ชื่อ นามสกุล", text: $name)
                .font(.sarabun(15)).foregroundStyle(Theme.navy)
                .padding(.horizontal, 14).frame(minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.borderSubtle))
                .accessibilityLabel("ชื่อที่แสดง")
        }
    }

    private var roleField: some View {
        let xs = Capability.allCases.map { $0.access(role, overrides: store.overrides) }
        let line = "ทำได้ \(xs.filter { $0 == .allow }.count) · มีเงื่อนไข \(xs.filter { $0 == .conditional }.count) · ดู \(xs.filter { $0 == .view }.count) จาก \(xs.count) สิทธิ์ · Maintainer ตั้งจากหน้านี้ไม่ได้"
        return VStack(alignment: .leading, spacing: 6) {
            Text("บทบาท").font(.sarabun(13, .bold)).foregroundStyle(Theme.projectTabInk)
            AdminSegments(items: UserRole.allCases.map {
                .init(id: $0, title: $0 == .external ? "ภายนอก" : $0.label, detail: $0.english, tint: UserAdminStyle.ink($0))
            }, selected: role, height: 52, radius: 11) { pickedRole = $0 }
            Text(line).font(.sarabun(12.5)).foregroundStyle(Theme.inkMuted)
        }
    }

    private var jobsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("งานที่มอบหมาย ") + Text("ภายนอกเห็นเฉพาะงานที่เลือก · เพิ่มภายหลังได้").font(.sarabun(13)).foregroundColor(Theme.muted))
                .font(.sarabun(13, .bold)).foregroundStyle(Theme.projectTabInk)
            if store.jobChoices.isEmpty {
                Text("ยังไม่มีงานให้มอบหมาย").font(.sarabun(13)).foregroundStyle(Theme.muted)
            }
            FlowLayout(spacing: 8) {
                ForEach(store.jobChoices) { j in
                    let on = jobs.contains(j.id)
                    Button { if on { jobs.removeAll { $0 == j.id } } else { jobs.append(j.id) } } label: {
                        Text((on ? "✓ " : "+ ") + j.label).font(.sarabun(13, .semibold))
                            .foregroundStyle(on ? Theme.warningText : Theme.inkMuted)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(on ? Theme.warningTint : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("i").font(.sarabun(12, .heavy)).foregroundStyle(Theme.warningText)
                .frame(width: 22, height: 22).background(Theme.warningTint, in: Circle())
            Text("เข้าแอปได้หลังกด ") + Text("บันทึกและซิงก์").bold() + Text(" แล้วส่งคำเชิญจากหน้าต่างที่ขึ้นมา · ลบออกได้ก่อนบันทึก")
        }
        .font(.sarabun(12.5)).foregroundStyle(Theme.projectTabInk)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.stripFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.track))
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("ยกเลิก") { done(nil) }.buttonStyle(TCButtonStyle(.secondary))
            Button("เพิ่มในรายชื่อ") {
                guard let valid, ok else { return }
                store.add(.init(email: valid, name: role == .external ? "" : name.trimmingCharacters(in: .whitespaces),
                                role: role, jobs: role == .external ? jobs : []))
                done(valid)
            }
            .buttonStyle(TCButtonStyle(.primary))
            .disabled(!ok)
            .accessibilityIdentifier("userAdmin.inviteAdd")
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }
}

import SwiftUI
import Observation
import FirebaseFirestore
import TCRoofCore
import TCRoofUI

/// The member list of firestore.rules (`members/<email>`), for a manager (`users.manage`): only these accounts sign
/// in. A manager adds people with a role, changes it, or removes them, never themselves (the rules refuse it), and
/// sends the invite through Mail, LINE or any app of the share sheet.
@MainActor
@Observable
final class MemberDirectory {
    struct Member: Identifiable, Equatable {
        var email: String
        var role: UserRole
        var invitedBy: String?
        var invitedAt: Date?
        /// Written here, not yet confirmed by the server.
        var pending = false
        var id: String { email }
    }

    private(set) var members: [Member] = []
    private(set) var loaded = false
    /// The last refusal or failure, for the page's banner.
    var error: String?
    /// `config/app.installLink`, set in the Firebase console: where the invited person gets the app.
    private(set) var installLink: String?

    @ObservationIgnored private var registration: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    func start() {
        guard registration == nil else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "membersDemo") { return seedDemo() }
        #endif
        registration = db.collection("members").addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.error = Self.message(error); return }
                self.members = (snapshot?.documents ?? []).map { doc in
                    Member(email: doc.documentID, role: UserRole(field: doc.get("role") as? String),
                           invitedBy: doc.get("invitedBy") as? String,
                           invitedAt: (doc.get("invitedAt") as? Timestamp)?.dateValue(),
                           pending: doc.metadata.hasPendingWrites)
                }
                self.loaded = true
            }
        }
        db.document("config/app").getDocument { [weak self] snapshot, _ in
            MainActor.assumeIsolated { self?.installLink = (snapshot?.get("installLink") as? String).flatMap { $0.isEmpty ? nil : $0 } }
        }
    }

    func stop() {
        registration?.remove()
        registration = nil
    }

    /// A Google account's email, lowercased, or nil when it can't be one.
    static func validEmail(_ text: String) -> String? {
        let email = Permissions.normalized(text)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !email.contains(where: \.isWhitespace), !email.contains("/") else { return nil }
        return email
    }

    /// Adds the account with its role. Firestore keeps the write offline and sends it later.
    func invite(_ email: String, role: UserRole, by me: String) {
        error = nil
        db.document("members/\(email)").setData(["role": role.rawValue, "invitedBy": me, "invitedAt": FieldValue.serverTimestamp()]) { [weak self] e in
            MainActor.assumeIsolated { if let e { self?.error = Self.message(e) } }
        }
        listInDirectory(email, role: role)
    }

    /// The team directory (`TeamDirectory`) follows the list: a team member or manager is in it, an external member
    /// isn't. Written after the member's own document, which the rules check.
    private func listInDirectory(_ email: String, role: UserRole?) {
        let doc = db.document("\(TeamDirectory.collection)/\(email)")
        let done: (Error?) -> Void = { e in if let e { print("MemberDirectory: directory: \(e.localizedDescription)") } }
        if let role, role != .external { doc.setData(TeamDirectory.entry(email: email, name: nil), merge: true, completion: done) }
        else { doc.delete(completion: done) }
    }

    func setRole(_ role: UserRole, of email: String) {
        error = nil
        db.document("members/\(email)").updateData(["role": role.rawValue]) { [weak self] e in
            MainActor.assumeIsolated { if let e { self?.error = Self.message(e) } }
        }
        listInDirectory(email, role: role)
    }

    /// Takes the account off the list: it can't sign in again, and the app signs it out at its next sync.
    func remove(_ email: String) {
        error = nil
        db.document("members/\(email)").delete { [weak self] e in
            MainActor.assumeIsolated { if let e { self?.error = Self.message(e) } }
        }
        listInDirectory(email, role: nil)
    }

    /// The message sent with the share sheet.
    func inviteText(_ email: String, role: UserRole) -> String {
        var lines = ["คุณได้รับเชิญให้ใช้แอป TCRoof ในบทบาท \(role.label)",
                     "เข้าสู่ระบบด้วยบัญชี Google: \(email)"]
        if let installLink { lines.append("ติดตั้งแอป: \(installLink)") }
        return lines.joined(separator: "\n")
    }

    private static func message(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == FirestoreErrorDomain, e.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "บัญชีนี้ไม่มีสิทธิ์จัดการสมาชิก (เฉพาะผู้จัดการ และแก้บัญชีของตัวเองไม่ได้)"
        }
        return error.localizedDescription
    }

    #if DEBUG
    /// `-membersDemo YES`: an example list, nothing written.
    private func seedDemo() {
        let now = Date()
        members = [
            Member(email: "demo@survey.co.th", role: .manager),
            Member(email: "somchai.tc@gmail.com", role: .internalTeam, invitedBy: "demo@survey.co.th", invitedAt: now.addingTimeInterval(-86_400 * 12)),
            Member(email: "wanida.eng@gmail.com", role: .internalTeam, invitedBy: "demo@survey.co.th", invitedAt: now.addingTimeInterval(-86_400 * 3)),
            Member(email: "foreman@contractor.co.th", role: .external, invitedBy: "demo@survey.co.th", invitedAt: now.addingTimeInterval(-3_600), pending: true),
        ]
        installLink = "https://testflight.apple.com/join/XXXXXX"
        loaded = true
    }
    #endif
}

/// Settings › สมาชิกทีม: invite by Google account and role, then the list by role.
struct MembersView: View {
    @Environment(\.permissions) private var permissions
    @Environment(\.homeInk) private var ink
    @State private var directory = MemberDirectory()
    @State private var email = ""
    @State private var roleLabel = UserRole.internalTeam.shortLabel
    /// The account just added, offered the share sheet.
    @State private var invited: (email: String, role: UserRole)?
    @State private var removing: MemberDirectory.Member?

    private var role: UserRole { UserRole.allCases.first { $0.shortLabel == roleLabel } ?? .internalTeam }
    private var typedEmail: String? { MemberDirectory.validEmail(email) }
    private var alreadyListed: Bool { typedEmail.map { e in directory.members.contains { $0.email == e } } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error = directory.error {
                    TCAlertCard(title: "ทำรายการไม่สำเร็จ", message: error, actions: []).padding(.top, 12)
                }
                inviteCard
                memberSections
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .font(.sarabun(16))
        .background(Theme.phonePage)
        .navigationTitle("สมาชิกทีม")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { directory.start() }
        .onDisappear { directory.stop() }
        .confirmationDialog("ลบ \(removing?.email ?? "") ออกจากทีม?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("ลบออกจากทีม", role: .destructive) {
                if let removing { directory.remove(removing.email) }
                removing = nil
            }
            Button("ยกเลิก", role: .cancel) { removing = nil }
        } message: {
            Text("บัญชีนี้จะเข้าสู่ระบบไม่ได้อีก และแอปในเครื่องของเขาจะออกจากระบบเมื่อซิงค์ครั้งถัดไป")
        }
    }

    private var inviteCard: some View {
        section("เชิญสมาชิกใหม่") {
            VStack(alignment: .leading, spacing: 12) {
                TCFieldLabel("บัญชี Google (Gmail)")
                TCTextField("name@gmail.com", text: $email, keyboard: .emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .submitLabel(.done)
                TCFieldLabel("บทบาท")
                TCSegmented(UserRole.allCases.map(\.shortLabel), selection: $roleLabel)
                Text(role.detail).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(ink.muted)
                if alreadyListed {
                    Text("บัญชีนี้อยู่ในทีมแล้ว").font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.danger)
                }
                Button("เพิ่มเข้าทีม") {
                    guard let mail = typedEmail else { return }
                    directory.invite(mail, role: role, by: permissions.email)
                    invited = (mail, role)
                    email = ""
                }
                .buttonStyle(TCButtonStyle(.primary, fullWidth: true))
                .disabled(typedEmail == nil || alreadyListed)
                if let invited {
                    Divider()
                    Text("เพิ่ม \(invited.email) แล้ว ส่งคำเชิญให้เขาเข้าสู่ระบบด้วยบัญชีนี้")
                        .font(.sarabun(14, relativeTo: .callout)).foregroundStyle(Theme.navy)
                    ShareLink(item: directory.inviteText(invited.email, role: invited.role)) {
                        Label("ส่งคำเชิญ (Mail, LINE …)", systemImage: "paperplane")
                    }
                    .buttonStyle(TCButtonStyle(.secondary, fullWidth: true))
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var memberSections: some View {
        if !directory.loaded {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
        } else {
            ForEach(UserRole.allCases, id: \.self) { role in
                let people = directory.members.filter { $0.role == role }.sorted { $0.email < $1.email }
                if !people.isEmpty {
                    section("\(role.label) · \(people.count)") {
                        ForEach(Array(people.enumerated()), id: \.element.id) { i, member in
                            if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                            memberRow(member)
                        }
                    }
                }
            }
        }
    }

    private func memberRow(_ member: MemberDirectory.Member) -> some View {
        let me = member.email == permissions.email
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(member.email + (me ? " (คุณ)" : "")).font(.sarabun(15.5, .bold)).foregroundStyle(Theme.navy)
                    .lineLimit(1).truncationMode(.middle)
                if let line = subtitle(member) {
                    Text(line).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(ink.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !me {
                Menu {
                    Picker("บทบาท", selection: Binding(get: { member.role }, set: { directory.setRole($0, of: member.email) })) {
                        ForEach(UserRole.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    ShareLink(item: directory.inviteText(member.email, role: member.role)) {
                        Label("ส่งคำเชิญอีกครั้ง", systemImage: "paperplane")
                    }
                    Button("ลบออกจากทีม", systemImage: "person.badge.minus", role: .destructive) { removing = member }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(Theme.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("จัดการ \(member.email)")
            }
        }
        .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func subtitle(_ member: MemberDirectory.Member) -> String? {
        if member.pending { return "รอส่งขึ้นระบบ" }
        guard let at = member.invitedAt else { return nil }
        let by = member.invitedBy.map { " โดย " + ($0.split(separator: "@").first.map(String.init) ?? $0) } ?? ""
        return "เชิญเมื่อ " + ThaiFormat.short.string(from: at) + by
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabun(12.5, .bold, relativeTo: .caption)).foregroundStyle(ink.muted)
                .padding(.leading, 4).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ink.border))
        }
        .padding(.top, 18)
    }
}

private extension UserRole {
    /// The segmented control's label.
    var shortLabel: String {
        switch self {
        case .manager: "ผู้จัดการ"
        case .internalTeam: "ทีมภายใน"
        case .external: "ภายนอก"
        case .maintainer: "Maintainer"
        }
    }

    var detail: String {
        switch self {
        case .manager: "ทำได้ทุกอย่าง รวมทั้งเชิญและลบสมาชิก"
        case .internalTeam: "วิศวกรและแอดมินของบริษัท เห็นทุกงาน"
        case .external: "วิศวกรภายนอก / ผู้รับเหมา เห็นเฉพาะงานที่ได้รับมอบหมาย"
        case .maintainer: "นักพัฒนาแอป ทำได้ทุกอย่าง · ตั้งจาก Firebase console เท่านั้น"
        }
    }
}

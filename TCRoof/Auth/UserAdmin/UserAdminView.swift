import SwiftUI
import SwiftData
import TCRoofCore
import TCRoofUI

/// Settings › นักพัฒนา › จัดการผู้ใช้และสิทธิ์ (docs/ui/user-admin-ipad, iPad regular width; iPhone gets the same view
/// pushed). A Maintainer's page (`users.admin`) behind the developer key: the member list with roles and suspension,
/// the role overrides and the audit log. Every change waits in the pending bar until `บันทึกและซิงก์`.
struct UserAdminView: View {
    enum Tab: String { case users, roles, log }

    @Environment(\.permissions) var permissions
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) var context
    @Query(sort: \Job.installStart) var jobs: [Job]

    @State var store: UserAdminStore
    @State var tab: Tab = .users
    @State var roleFilter: UserRole?
    @State var search = ""
    @State var selected: String?
    /// The member whose role is being edited (after the key).
    @State var roleEditing: String?
    @State var matrixEditing = false
    @State var onlyChanged = false
    @State var openGroups: Set<String> = ["jobs_plan"]
    @State var keyAsk: DevKeyPurpose?
    @State var inviting = false
    @State var toast: String?
    @State var confirmLeave = false
    /// Invites just saved, offered the share sheet.
    @State var sent: [UserAdminStore.Invite] = []
    @State var now = Date.now

    init(demo: Bool = UserAdminView.demoFlag) {
        _store = State(initialValue: UserAdminStore(demo: demo))
    }

    static var demoFlag: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "userAdminDemo")
        #else
        false
        #endif
    }

    /// The signed-in account; the demo's own row is the board's Maintainer.
    var me: String { store.demo ? "wit.chanthawat@gmail.com" : permissions.email }

    var body: some View {
        Group {
            if permissions.can(.usersAdmin) || store.demo { page } else { noAccess }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: appear)
        .onDisappear { store.stop(); store.lock() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { lock() } }
        .onChange(of: jobs.count) { fillJobs() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
                if store.unlockedAt != nil, !store.isUnlocked { lock() }
            }
        }
    }

    private var page: some View {
        ZStack {
            Theme.phonePage.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                tabBar
                content
            }
            if store.pendingCount > 0 { pendingBar }
            if !store.isUnlocked {
                DevKeyLockScreen(store: store, onBack: leave)
                    .transition(.opacity)
            }
            if let keyAsk { keySheet(keyAsk) }
            if inviting { InviteSheet(store: store, done: { inviting = false; if let e = $0 { added(e) } }) }
            if !sent.isEmpty { sentSheet }
        }
        .tcToast($toast)
        .confirmationDialog("มีการแก้ไขที่ยังไม่บันทึก", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("ทิ้งการแก้ไข \(store.pendingCount) รายการ", role: .destructive) { store.discard(); close() }
            Button("กลับไปบันทึก", role: .cancel) {}
        } message: {
            Text("ออกจากหน้านี้แล้วการแก้ไขที่ยังไม่บันทึกจะหายไป")
        }
    }

    private var noAccess: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.system(size: 40)).foregroundStyle(Theme.inkMuted)
            Text("เฉพาะ Maintainer").font(.sarabun(20, .bold)).foregroundStyle(Theme.navy)
            Text("หน้านี้เปิดได้เฉพาะบัญชีที่มีสิทธิ์ users.admin").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
            Button("กลับ") { close() }.buttonStyle(TCButtonStyle(.secondary, size: .card))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.phonePage)
    }

    // MARK: header and tabs

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: leave) {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.onPrimary.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("กลับไปตั้งค่า")
            VStack(alignment: .leading, spacing: 0) {
                Text("จัดการผู้ใช้และสิทธิ์").font(.sarabun(24, .bold))
                Text("โหมดนักพัฒนา · \(UserRole.allCases.count) บทบาท · members/<email>.role").font(.sarabun(14)).opacity(0.9)
            }
            .foregroundStyle(Theme.onPrimary)
            .lineLimit(1)
            Spacer(minLength: 8)
            unlockPill
            Button(action: lock) {
                Label("ล็อกหน้านี้", systemImage: "lock").font(.sarabun(14, .bold)).foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.onPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.onPrimary.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("userAdmin.lock")
        }
        .padding(.horizontal, 40).padding(.vertical, 18)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    private var unlockPill: some View {
        let left = Int(store.remaining(at: now).rounded(.up))
        return Label("ปลดล็อกเหลือ \(String(format: "%d:%02d", left / 60, left % 60)) นาที", systemImage: "clock")
            .font(.sarabun(13, .bold)).foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(Theme.onPrimary.opacity(0.16), in: Capsule())
            .monospacedDigit()
    }

    private var tabBar: some View {
        HStack(spacing: 12) {
            AdminSegments(items: [
                .init(id: Tab.users, title: "ผู้ใช้", count: store.shown.count),
                .init(id: Tab.roles, title: "บทบาทและสิทธิ์", count: UserRole.allCases.count),
                .init(id: Tab.log, title: "ประวัติการแก้ไข", count: store.log.count),
            ], selected: tab) { tab = $0 }
            .frame(width: 560)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle().fill(store.offline ? Theme.warning : Theme.success).frame(width: 8, height: 8)
                Text(syncLine).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, 40).padding(.top, 16)
    }

    private var syncLine: String {
        guard let at = store.lastSync else { return store.offline ? "ออฟไลน์ · ข้อมูลในเครื่อง" : "กำลังซิงก์…" }
        return (store.offline ? "ออฟไลน์ · " : "") + "ซิงก์ล่าสุด " + ThaiFormat.numericDate.string(from: at) + " " + ThaiFormat.time.string(from: at)
    }

    @ViewBuilder
    private var content: some View {
        let bottom: CGFloat = store.pendingCount > 0 ? 96 : 24
        Group {
            switch tab {
            case .users: usersTab
            case .roles: rolesTab
            case .log: logTab
            }
        }
        .padding(.horizontal, 40).padding(.top, 14).padding(.bottom, bottom)
        .frame(maxHeight: .infinity)
    }

    // MARK: pending bar

    private var pendingBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Circle().fill(Theme.pendingYellow).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text("แก้ไข \(store.pendingCount) รายการ · ยังไม่บันทึก").font(.sarabun(14, .bold))
                        .accessibilityIdentifier("userAdmin.pending")
                    Text("บันทึกแล้วจะซิงก์ members/<email>.role ให้ทุกเครื่อง").font(.sarabun(12)).opacity(0.8)
                }
                .foregroundStyle(Theme.onPrimary)
                Button { store.discard(); roleEditing = nil } label: {
                    Text("ยกเลิกทั้งหมด").font(.sarabun(14, .bold)).foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.onPrimary.opacity(0.35)))
                }
                .buttonStyle(.plain)
                Button(action: save) {
                    Text("บันทึกและซิงก์").font(.sarabun(14, .heavy)).foregroundStyle(Theme.onSun)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.pendingYellow, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
            .background(Theme.navySolid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.navySolid.opacity(0.35), radius: 16, y: 12)
            .padding(.bottom, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("การเปลี่ยนแปลงที่ยังไม่บันทึก")
    }

    // MARK: key sheet, invites sent

    private func keySheet(_ purpose: DevKeyPurpose) -> some View {
        let subject: String = if case .role(let email) = purpose { store.shown.first { $0.email == email }?.label ?? email } else { "" }
        return DevKeySheet(store: store, purpose: purpose, subject: subject) { ok in
            keyAsk = nil
            guard ok else { return }
            switch purpose {
            case .role(let email): roleEditing = email
            case .invite: inviting = true
            case .matrix: matrixEditing = true
            }
        }
    }

    private var sentSheet: some View {
        ZStack {
            Theme.navySolid.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("ส่งคำเชิญ").font(.sarabun(18, .bold)).foregroundStyle(Theme.navy)
                Text("บันทึกแล้ว · ส่งคำเชิญให้เขาเข้าสู่ระบบด้วยบัญชี Google นี้").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                ForEach(sent) { inv in
                    ShareLink(item: store.inviteText(inv)) {
                        Label("ส่งคำเชิญ \(inv.email)", systemImage: "paperplane")
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                }
                Button("เสร็จ") { sent = [] }.buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
            }
            .padding(22)
            .frame(width: 460)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: actions

    func ask(_ purpose: DevKeyPurpose) { keyAsk = purpose }

    func lock() {
        store.lock()
        roleEditing = nil
        matrixEditing = false
        keyAsk = nil
        inviting = false
    }

    private func leave() {
        if store.pendingCount > 0 { confirmLeave = true } else { close() }
    }

    private func close() {
        lock()
        dismiss()
    }

    private func added(_ email: String) {
        roleFilter = nil
        selected = email
        toast = "เพิ่ม \(email) แล้ว · กดบันทึกและซิงก์เพื่อส่งคำเชิญ"
    }

    private func save() {
        let n = store.pendingCount
        roleEditing = nil
        guard let saved = store.save(by: me, assign: assign) else { return }
        toast = "บันทึกแล้ว · ซิงก์ members/<email>.role · \(n) รายการ"
        if !store.demo { sent = saved.invites }
    }

    /// An external invite's jobs: the email joins each job's `externals`, which sync sends with the job.
    private func assign(_ ids: [String], _ email: String) {
        for job in jobs where ids.contains(job.syncID ?? "") { job.externals.append(email) }
        try? context.save()
    }

    private func appear() {
        store.companyDomain = permissions.email.split(separator: "@").last.map(String.init)
        fillJobs()
        store.start()
        #if DEBUG
        applyDebugFlags()
        #endif
    }

    /// Each member's jobs, from `Job.externals`, `teamMembers` and `supervisorEmail`.
    private func fillJobs() {
        guard !store.demo else { return }
        var by: [String: [String]] = [:]
        for job in jobs {
            let label = job.linkLabel
            for e in job.externals { by[e, default: []].append(label) }
            for e in job.teamMembers { by[e, default: []].append(label) }
            if let s = job.supervisorEmail.map(Permissions.normalized), !s.isEmpty { by[s, default: []].append("ผู้ควบคุมงาน " + label) }
        }
        store.jobsByEmail = by
        store.jobChoices = jobs.filter { $0.status != .completed && $0.syncID != nil }
            .map { UserAdminStore.JobRef(id: $0.syncID!, label: $0.linkLabel) }
    }

    #if DEBUG
    /// `-userAdminTab`, `-userAdminUser`, `-userAdminSheet`, `-userAdminEdit`, `-userAdminStage` (CLAUDE.md).
    private func applyDebugFlags() {
        let d = UserDefaults.standard
        if let t = d.string(forKey: "userAdminTab").flatMap(Tab.init) { tab = t }
        if let u = d.string(forKey: "userAdminUser") { selected = u }
        switch d.string(forKey: "userAdminEdit") {
        case "role": roleEditing = selectedMember?.email
        case "matrix": matrixEditing = true; tab = .roles
        default: break
        }
        switch d.string(forKey: "userAdminSheet") {
        case "invite": inviting = true
        case "key": if let e = selectedMember?.email { keyAsk = .role(e) }
        default: break
        }
        guard store.demo, let stage = d.string(forKey: "userAdminStage") else { return }
        // the board's pending states, written into the demo only
        switch stage {
        case "role": if let e = selectedMember?.email { roleEditing = e; store.setRole(.internalTeam, of: e) }
        case "suspend": if let e = selectedMember?.email { store.toggleSuspension(of: e) }
        case "invite":
            store.add(.init(email: "kanya@contractor-e.co.th", name: "", role: .external, jobs: ["MP 171 สามโคก"]))
            selected = "kanya@contractor-e.co.th"
        case "cell":
            tab = .roles; matrixEditing = true
            store.cycle(.internalTeam, .toolsRegister); store.cycle(.external, .feedAckFix)
        default: break
        }
    }
    #endif
}

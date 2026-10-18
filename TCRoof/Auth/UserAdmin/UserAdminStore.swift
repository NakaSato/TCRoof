import Foundation
import Observation
import FirebaseFirestore
import TCRoofCore

/// จัดการผู้ใช้และสิทธิ์ (docs/ui/user-admin-ipad): the member list with suspension, the developer key, the role
/// overrides and the audit log, for a Maintainer (`users.admin`). Every change waits in `pending` until `save`, which
/// writes them in one Firestore batch with an audit entry each. The key gates the page; firestore.rules decide.
@MainActor
@Observable
final class UserAdminStore {
    struct Member: Identifiable, Equatable {
        var email: String
        var role: UserRole
        var name: String?
        var suspended = false
        var suspendedAt: Date?
        var invitedBy: String?
        var invitedAt: Date?
        /// Written on this device, not yet confirmed by the server.
        var pending = false
        /// Added in this page and not saved yet.
        var unsaved = false
        var id: String { email }
        var label: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? email }
    }

    struct AuditEntry: Identifiable, Equatable {
        var id: String
        var at: Date?
        var by: String
        var kind: AuditKind
        var title: String
        var detail: String
    }

    struct Invite: Identifiable, Equatable {
        var email: String
        var name: String
        var role: UserRole
        /// The jobs (syncIDs) it is assigned to, for an external member.
        var jobs: [String]
        var id: String { email }
    }

    /// A job an external member can be given, and its label.
    struct JobRef: Identifiable, Equatable {
        var id: String
        var label: String
    }

    enum KeyState: Equatable { case loading, ready, missing, expired, unreadable }
    enum KeyCheck: Equatable { case ok, wrong(left: Int), locked, unavailable }

    // MARK: the server's data

    private(set) var members: [Member] = []
    private(set) var loaded = false
    private(set) var log: [AuditEntry] = []
    private(set) var lastSync: Date?
    private(set) var offline = false
    private(set) var savedOverrides = RoleOverrides()
    private(set) var keyState = KeyState.loading
    private var devKey: DevKey?
    /// The last refusal, for the banner.
    var error: String?
    /// `config/app.installLink`, for the invite text.
    private(set) var installLink: String?

    /// Each member's jobs: an external member's assigned jobs, a team member's jobs that name them.
    var jobsByEmail: [String: [String]] = [:]
    /// The jobs an invite can assign.
    var jobChoices: [JobRef] = []
    /// The signed-in account's domain: an email there is suggested as the team.
    var companyDomain: String?

    // MARK: pending changes

    var roleChanges: [String: UserRole] = [:]
    var suspensions: [String: Bool] = [:]
    var invites: [Invite] = []
    var overrides = RoleOverrides()

    var pendingCount: Int {
        invites.count + roleChanges.count + suspensions.count + changedCells.count
    }

    /// The matrix cells changed and not saved.
    var changedCells: [(UserRole, Capability)] {
        var out: [(UserRole, Capability)] = []
        for c in Capability.allCases {
            for r in UserRole.allCases where overrides[r, c] != savedOverrides[r, c] { out.append((r, c)) }
        }
        return out
    }

    // MARK: the key gate

    private(set) var unlockedAt: Date?
    private(set) var attempts = DevKeyAttempts()
    let demo: Bool

    private static let attemptsKey = "userAdmin.keyAttempts"
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    private var db: Firestore { Firestore.firestore() }

    init(demo: Bool = false) {
        self.demo = demo
        if let data = UserDefaults.standard.data(forKey: Self.attemptsKey),
           let a = try? JSONDecoder().decode(DevKeyAttempts.self, from: data) { attempts = a }
    }

    // MARK: listening

    func start() {
        guard listeners.isEmpty, !loaded else { return }
        #if DEBUG
        if demo { return seedDemo() }
        #endif
        listeners.append(db.collection("members").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.error = Self.message(error); return }
                guard let snap else { return }
                self.members = snap.documents.map { d in
                    Member(email: d.documentID, role: UserRole(field: d.get("role") as? String),
                           name: TeamDirectory.shared.person(d.documentID)?.name,
                           suspended: d.get("suspended") as? Bool == true,
                           suspendedAt: (d.get("suspendedAt") as? Timestamp)?.dateValue(),
                           invitedBy: d.get("invitedBy") as? String,
                           invitedAt: (d.get("invitedAt") as? Timestamp)?.dateValue(),
                           pending: d.metadata.hasPendingWrites)
                }
                self.offline = snap.metadata.isFromCache
                if !snap.metadata.isFromCache { self.lastSync = .now }
                self.loaded = true
            }
        })
        listeners.append(db.collection("auditLog").order(by: "at", descending: true).limit(to: 200).addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                self?.log = (snap?.documents ?? []).compactMap { d in
                    guard let kind = (d.get("kind") as? String).flatMap(AuditKind.init) else { return nil }
                    return AuditEntry(id: d.documentID, at: (d.get("at") as? Timestamp)?.dateValue(), by: d.get("by") as? String ?? "",
                                      kind: kind, title: d.get("title") as? String ?? "", detail: d.get("detail") as? String ?? "")
                }
            }
        })
        listeners.append(db.document("config/roleOverrides").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                let o = RoleOverrides(document: snap.data() ?? [:])
                // a cell edited here stays as edited; the others follow the server
                let edited = Set(self.changedCells.map { RoleOverrides.key($0.0, $0.1) })
                var next = o
                for (r, c) in Capability.allCases.flatMap({ c in UserRole.allCases.map { ($0, c) } })
                where edited.contains(RoleOverrides.key(r, c)) { next[r, c] = self.overrides[r, c] }
                self.savedOverrides = o
                self.overrides = next
            }
        })
        db.document("config/app").getDocument { [weak self] snap, _ in
            MainActor.assumeIsolated { self?.installLink = (snap?.get("installLink") as? String).flatMap { $0.isEmpty ? nil : $0 } }
        }
        loadKey()
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    /// Reads `config/devKey` (the Maintainer's only).
    func loadKey() {
        #if DEBUG
        if demo { return }
        #endif
        keyState = .loading
        db.document("config/devKey").getDocument { [weak self] snap, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard error == nil, let snap else { self.keyState = .unreadable; return }
                guard snap.exists else { self.keyState = .missing; return }
                let key = DevKey(hash: snap.get("hash") as? String, salt: snap.get("salt") as? String,
                                 iterations: (snap.get("iterations") as? NSNumber)?.intValue,
                                 expiresAt: (snap.get("expiresAt") as? Timestamp)?.dateValue(),
                                 setBy: snap.get("setBy") as? String, setAt: (snap.get("setAt") as? Timestamp)?.dateValue())
                self.devKey = key
                self.keyState = key == nil ? .missing : key!.isExpired() ? .expired : .ready
            }
        }
    }

    // MARK: the key

    var isUnlocked: Bool { unlockedAt.map { Date.now.timeIntervalSince($0) < DevKey.unlockWindow } ?? false }

    func remaining(at now: Date) -> TimeInterval {
        guard let unlockedAt else { return 0 }
        return max(0, DevKey.unlockWindow - now.timeIntervalSince(unlockedAt))
    }

    /// Checks 6 digits against the key. `unlock` opens the page (the lock screen); otherwise it only confirms.
    func check(_ digits: String, unlock: Bool) -> KeyCheck {
        if attempts.isLocked() { return .locked }
        guard let devKey, keyState == .ready, !devKey.isExpired() else { return .unavailable }
        if devKey.matches(digits) {
            attempts.reset()
            keepAttempts()
            if unlock { unlockedAt = .now }
            return .ok
        }
        attempts.fail()
        keepAttempts()
        return attempts.isLocked() ? .locked : .wrong(left: attempts.left)
    }

    var padLocked: Bool { attempts.isLocked() }

    func lock() { unlockedAt = nil }

    private func keepAttempts() {
        guard !demo else { return }
        if let data = try? JSONEncoder().encode(attempts) { UserDefaults.standard.set(data, forKey: Self.attemptsKey) }
    }

    // MARK: reading

    /// The list as it will be after saving: invites added, roles and suspensions changed.
    var shown: [Member] {
        var list = members.map { m -> Member in
            var m = m
            if let r = roleChanges[m.email] { m.role = r }
            if let s = suspensions[m.email] { m.suspended = s }
            return m
        }
        list += invites.map { Member(email: $0.email, role: $0.role, name: $0.name.isEmpty ? nil : $0.name, unsaved: true) }
        // the Maintainer first, then managers, the team and external people, each in the list's order
        let order: [UserRole: Int] = [.maintainer: 0, .manager: 1, .internalTeam: 2, .external: 3]
        return list.enumerated().sorted { (order[$0.element.role]!, $0.offset) < (order[$1.element.role]!, $1.offset) }.map(\.element)
    }

    func savedRole(_ email: String) -> UserRole? {
        members.first { $0.email == email }?.role ?? invites.first { $0.email == email }?.role
    }

    func isListed(_ email: String) -> Bool { shown.contains { $0.email == email } }

    // MARK: changing (pending until saved)

    func setRole(_ role: UserRole, of email: String) {
        guard role != .maintainer else { return }
        if let i = invites.firstIndex(where: { $0.email == email }) { invites[i].role = role; return }
        roleChanges[email] = members.first { $0.email == email }?.role == role ? nil : role
    }

    func undoRole(of email: String) { roleChanges[email] = nil }

    func toggleSuspension(of email: String) {
        if let i = invites.firstIndex(where: { $0.email == email }) { invites.remove(at: i); return }
        guard let saved = members.first(where: { $0.email == email }) else { return }
        let now = suspensions[email] ?? saved.suspended
        suspensions[email] = !now == saved.suspended ? nil : !now
    }

    func add(_ invite: Invite) { invites.append(invite) }

    func cycle(_ role: UserRole, _ capability: Capability) {
        let now = capability.access(role, overrides: overrides)
        let next = now.next
        overrides[role, capability] = next == capability.access(role) ? nil : next
    }

    func discard() {
        roleChanges = [:]
        suspensions = [:]
        invites = []
        overrides = savedOverrides
    }

    // MARK: saving

    /// What was saved, for the share sheet of the invites.
    struct Saved { var invites: [Invite]; var overrides: RoleOverrides? }

    /// Writes every pending change in one batch with an audit entry each, then the team directory and the jobs of
    /// external invites (`assign` sets `Job.externals`). Firestore keeps the batch offline and sends it later.
    func save(by me: String, assign: ([String], String) -> Void) -> Saved? {
        guard pendingCount > 0 else { return nil }
        error = nil
        let saved = Saved(invites: invites, overrides: changedCells.isEmpty ? nil : overrides)
        let audits = auditEntries()
        if !demo {
            let batch = db.batch()
            for inv in invites {
                batch.setData(["role": inv.role.rawValue, "invitedBy": me, "invitedAt": FieldValue.serverTimestamp()],
                              forDocument: db.document("members/\(inv.email)"))
            }
            for (email, role) in roleChanges {
                batch.updateData(["role": role.rawValue], forDocument: db.document("members/\(email)"))
            }
            for (email, on) in suspensions {
                let fields: [String: Any] = on
                    ? ["suspended": true, "suspendedBy": me, "suspendedAt": FieldValue.serverTimestamp()]
                    : ["suspended": FieldValue.delete(), "suspendedBy": FieldValue.delete(), "suspendedAt": FieldValue.delete()]
                batch.updateData(fields, forDocument: db.document("members/\(email)"))
            }
            if !changedCells.isEmpty { batch.setData(overrides.document, forDocument: db.document("config/roleOverrides")) }
            for a in audits {
                batch.setData(["at": FieldValue.serverTimestamp(), "by": me, "kind": a.kind.rawValue, "title": a.title, "detail": a.detail],
                              forDocument: db.collection("auditLog").document())
            }
            let invited = invites, roles = roleChanges
            batch.commit { [weak self] e in
                MainActor.assumeIsolated {
                    if let e { self?.error = Self.message(e); return }
                    // after the members' documents, which the directory's rules check
                    for inv in invited { self?.listInDirectory(inv.email, role: inv.role, name: inv.name) }
                    for (email, role) in roles { self?.listInDirectory(email, role: role, name: nil) }
                }
            }
            for inv in invites where inv.role == .external && !inv.jobs.isEmpty { assign(inv.jobs, inv.email) }
            if let o = saved.overrides { savedOverrides = o; MemberRole.shared.apply(o) }
        } else {
            // the demo keeps its changes in memory
            for inv in invites { members.append(Member(email: inv.email, role: inv.role, name: inv.name.isEmpty ? nil : inv.name)) }
            for (email, role) in roleChanges { if let i = members.firstIndex(where: { $0.email == email }) { members[i].role = role } }
            for (email, on) in suspensions {
                if let i = members.firstIndex(where: { $0.email == email }) { members[i].suspended = on; members[i].suspendedAt = on ? .now : nil }
            }
            for inv in invites where inv.role == .external { jobsByEmail[inv.email] = inv.jobs.compactMap { id in jobChoices.first { $0.id == id }?.label } }
            savedOverrides = overrides
            log.insert(contentsOf: audits.enumerated().map { i, a in AuditEntry(id: "demo-\(Date.now.timeIntervalSince1970)-\(i)", at: .now, by: me, kind: a.kind, title: a.title, detail: a.detail) }, at: 0)
        }
        roleChanges = [:]
        suspensions = [:]
        invites = []
        return saved
    }

    private func label(_ email: String) -> String { shown.first { $0.email == email }?.label ?? email }

    private func auditEntries() -> [(kind: AuditKind, title: String, detail: String)] {
        var out: [(AuditKind, String, String)] = []
        for inv in invites {
            let jobs = inv.jobs.compactMap { id in jobChoices.first { $0.id == id }?.label }
            out.append((.user, "เพิ่ม \(inv.name.isEmpty ? inv.email : inv.name) ในรายชื่อสมาชิก",
                        (["บทบาท " + inv.role.label] + jobs).joined(separator: " · ")))
        }
        for (email, role) in roleChanges.sorted(by: { $0.key < $1.key }) {
            let from = members.first { $0.email == email }?.role ?? .internalTeam
            let c = RoleChange(from: from, to: role, overrides: overrides)
            out.append((.role, "เปลี่ยนบทบาท \(label(email)): \(from.label) → \(role.label)",
                        "\(email) · ได้เพิ่ม \(c.gained.count) · เสีย \(c.lost.count)"))
        }
        for (email, on) in suspensions.sorted(by: { $0.key < $1.key }) {
            out.append((.sus, on ? "ปิดบัญชี \(label(email))" : "เปิดใช้งาน \(label(email)) อีกครั้ง", email))
        }
        for (r, c) in changedCells {
            let from = c.access(r, overrides: savedOverrides), to = c.access(r, overrides: overrides)
            out.append((.perm, "\(c.rawValue): \(r.label) \(from.label) → \(to.label)", c.label))
        }
        return out.map { (kind: $0.0, title: String($0.1.prefix(300)), detail: String($0.2.prefix(500))) }
    }

    /// The team directory follows the list, as `MemberDirectory` keeps it: team and managers in, external out.
    private func listInDirectory(_ email: String, role: UserRole, name: String?) {
        let doc = db.document("\(TeamDirectory.collection)/\(email)")
        if role != .external { doc.setData(TeamDirectory.entry(email: email, name: name), merge: true) }
        else { doc.delete() }
    }

    func inviteText(_ invite: Invite) -> String {
        var lines = ["คุณได้รับเชิญให้ใช้แอป TCRoof ในบทบาท \(invite.role.label)",
                     "เข้าสู่ระบบด้วยบัญชี Google: \(invite.email)"]
        if let installLink { lines.append("ติดตั้งแอป: \(installLink)") }
        return lines.joined(separator: "\n")
    }

    private static func message(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == FirestoreErrorDomain, e.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "บันทึกไม่สำเร็จ · บัญชีนี้ไม่มีสิทธิ์ (firestore.rules ปฏิเสธ)"
        }
        return error.localizedDescription
    }

    // MARK: demo

    #if DEBUG
    /// `-userAdminDemo YES`: the board's example (`iPadUsers.dc.html` U0 and its log), nothing written. The example key
    /// works only here.
    private func seedDemo() {
        let day: TimeInterval = 86_400, now = Date.now
        func m(_ n: String, _ e: String, _ r: UserRole, _ jobs: [String], suspended: Bool = false, unsaved: Bool = false) -> Member {
            jobsByEmail[e] = jobs
            return Member(email: e, role: r, name: n, suspended: suspended, suspendedAt: suspended ? now - 16 * day : nil,
                          invitedBy: "wit.chanthawat@gmail.com", invitedAt: now - 30 * day)
        }
        members = [
            m("Chanthawat Kiriyadee", "wit.chanthawat@gmail.com", .maintainer, []),
            m("สมชาย ใจดี", "somchai@tcroof.example", .internalTeam, ["ผู้ควบคุมงาน MP 98 บ้านโป่ง", "MP 154 แพรกหนามแดง"]),
            m("วนิดา ศรีสุข", "wanida@tcroof.example", .internalTeam, ["ผู้ควบคุมงาน MP 77 โชคชัย"]),
            m("ประกิต แก้วมณี", "prakit@tcroof.example", .internalTeam, []),
            m("ณัฐพล ทองดี", "nattapon@tcroof.example", .internalTeam, []),
            m("มานพ กิจเจริญ", "manop@tcroof.example", .manager, []),
            m("อารีย์ มั่นคง", "aree@contractor-a.example", .external, ["MP 189 ทุ่งน้อย", "MP 98 บ้านโป่ง", "MP 133 บางปะกง"]),
            m("เกียรติศักดิ์ บุญมา", "kiattisak@contractor-b.example", .external, ["MP 120 วัดชัย", "MP 77 โชคชัย"]),
            m("ธีรพงษ์ สายทอง", "teerapong@contractor-c.example", .external, ["MP 154 แพรกหนามแดง", "MP 142 หนองแค"]),
            m("สุรเชษฐ์ พรหมมา", "surachet@eng-firm.example", .external, ["ออกแบบ MP 61 แม่ข่ายชนบท · ผู้ลงนาม"]),
            m("จิราพร ทองคำ", "jiraporn@contractor-d.example", .external, ["MP 171 สามโคก"]),
            m("โอภาส ชัยวัฒน์", "opas@contractor-c.example", .external, [], suspended: true),
        ]
        jobChoices = ["MP 189 ทุ่งน้อย", "MP 171 สามโคก", "MP 154 แพรกหนามแดง", "MP 142 หนองแค", "MP 133 บางปะกง"]
            .map { JobRef(id: $0, label: $0) }
        companyDomain = "tcroof.example"
        let me = "wit.chanthawat@gmail.com"
        func l(_ ago: TimeInterval, _ t: String, _ d: String, _ k: AuditKind) -> AuditEntry {
            AuditEntry(id: t, at: now - ago, by: me, kind: k, title: t, detail: d)
        }
        log = [
            l(0.2 * day, "ปิด / ระงับบัญชี: เฉพาะ Maintainer", "users.suspend · ผู้จัดการไม่มีสิทธิ์นี้แล้ว", .perm),
            l(0.21 * day, "ตั้ง Chanthawat Kiriyadee เป็น Maintainer", "ทำได้ทุกอย่าง · ไม่ขึ้นกับ 3 บทบาท", .role),
            l(1.1 * day, "มอบหมาย MP 133 บางปะกง ให้ อารีย์ มั่นคง", "วิศวกรภายนอก / ผู้รับเหมา", .role),
            l(1.5 * day, "drive.upload: ผู้รับเหมาใช้ Drive ของตัวเอง", "ตามข้อตกลง drive-by-role", .perm),
            l(3 * day, "handover.final_signoff: ทีมภายใน → เฉพาะวิศวกรผู้ควบคุมงาน", "เซ็นตรวจรับงานขั้นสุดท้าย", .perm),
            l(6 * day, "เพิ่ม จิราพร ทองคำ ในรายชื่อสมาชิก", "บทบาท วิศวกรภายนอก / ผู้รับเหมา · MP 171 สามโคก", .user),
            l(8 * day, "เปลี่ยนคีย์นักพัฒนา", "หมดอายุใน 30 วัน", .key),
            l(16 * day, "ปิดบัญชี โอภาส ชัยวัฒน์", "opas@contractor-c.example", .sus),
        ]
        devKey = DevKey.make(digits: "246810", salt: Data("user-admin-demo".utf8), iterations: 1000, expiresAt: now + 22 * day)
        keyState = .ready
        lastSync = now - 600
        installLink = "https://testflight.apple.com/join/XXXXXX"
        loaded = true
        if let n = UserDefaults.standard.object(forKey: "userAdminWrongKey") as? Int ?? Int(UserDefaults.standard.string(forKey: "userAdminWrongKey") ?? "") {
            attempts = DevKeyAttempts()
            for _ in 0..<min(max(n, 0), DevKey.maxTries) { attempts.fail() }
        } else {
            attempts = DevKeyAttempts()
        }
        if UserDefaults.standard.bool(forKey: "userAdminUnlocked") { unlockedAt = .now - 28 }
    }
    #endif
}

import Foundation

/// A member's role (docs/reference/roles/user-roles.json). Kept as `role` on the member's `members/<email>` document;
/// a member without one is `internalTeam`, so accounts made before roles keep what they could do.
public enum UserRole: String, Codable, CaseIterable, Sendable {
    case manager
    case internalTeam = "internal"
    case external
    /// The app's developer: everything a role can do, plus suspending accounts and the role overrides. Set in the
    /// Firebase console only (firestore.rules never lets the app write it), and not a column of the roles table.
    case maintainer

    /// The roles of the table, which a manager sets from the app. The Maintainer isn't one of them.
    public static var allCases: [UserRole] { [.manager, .internalTeam, .external] }
    /// The table's roles and the Maintainer.
    public static var every: [UserRole] { allCases + [.maintainer] }

    public var label: String {
        switch self {
        case .manager: "ผู้จัดการ"
        case .internalTeam: "ทีมภายใน"
        case .external: "วิศวกรภายนอก / ผู้รับเหมา"
        case .maintainer: "Maintainer"
        }
    }

    /// The role's English name (user-roles.json `en`, short).
    public var english: String {
        switch self {
        case .manager: "Manager"
        case .internalTeam: "Internal"
        case .external: "External"
        case .maintainer: "Maintainer"
        }
    }

    /// A manager or the Maintainer: firestore.rules `isManager()`.
    public var managesTeam: Bool { self == .manager || self == .maintainer }

    /// The `role` field as written in Firestore; nil or unknown reads as the internal team.
    public init(field: String?) {
        self = field.flatMap(UserRole.init(rawValue:)) ?? .internalTeam
    }
}

/// One cell of the roles table.
public enum RoleAccess: String, Codable, Sendable {
    /// ✓ ทำได้
    case allow
    /// ดูได้อย่างเดียว
    case view
    /// ✕ ไม่ได้
    case deny
    /// ทำได้แบบมีเงื่อนไข: `Permissions.can` checks the condition against the job.
    case conditional
    /// ปิดใช้งานทุกบทบาท (BOQ)
    case disabled
}

/// The things a role may or may not do, by the ids of user-roles.json.
public enum Capability: String, CaseIterable, Sendable {
    // งานและแผนงาน
    case jobList = "job.list"
    case jobEdit = "job.edit"
    case jobDelete = "job.delete"
    case assignExternal = "job.assign_external"
    case assignTeam = "job.assign_team"
    case mpSetup = "mp.setup"
    case mpProgress = "mp.progress"
    case mpWBSTick = "mp.wbs_tick"
    case moveToInstall = "survey.move_to_install"
    case installTracking = "install.tracking"
    case overviewReports = "overview.reports"
    /// The project assistant (Qwen through the `assistant` Cloud Function, which checks the role itself).
    case assistantUse = "assistant.use"
    // สำรวจ ออกแบบ และราคา
    case surveyEdit = "survey.edit"
    case surveySignRev = "survey.sign_rev"
    case designLibrary = "design.library"
    /// The team's tank structure standard (`TankStandard`, `config/tankStandard`): managers change it, everyone reads it.
    case tankStandard = "tank.standard"
    case boqDraft = "boq.draft"
    case boqApprove = "boq.approve"
    case companyDocs = "library.company_docs"
    // เอกสารลูกค้าและการขออนุญาต
    case customerPersonalDocs = "customer.personal_docs"
    case permitPPIM = "permit.pea_ppim"
    case engineerCertify = "engineer.certify"
    case attachFiles = "project.attach_files"
    case driveUpload = "drive.upload"
    case ercFlow = "erc.flow_record"
    case stationDocsDrafts = "stationdocs.drafts"
    // หน้างานและผู้รับเหมา
    case workOrder = "site.work_order"
    case changeRequest = "site.change_request"
    case punchList = "site.punch_list"
    case dailyFill = "daily.fill"
    /// The weekly request R1: the contractor fills and sends it, the team approves or sends it back.
    case weeklyRequest = "weekly.request"
    case dailySign = "daily.sign"
    case iecFillSubmit = "iec.fill_submit"
    case iecClose = "iec.close"
    case iclChecklist = "icl.checklist"
    /// The PWA site ICL (`SiteICL`): the contractor inspects, fills and sends each sheet; the team signs it.
    case iclSiteFill = "icl.site_fill"
    case iclSiteSign = "icl.site_sign"
    case finalSignoff = "handover.final_signoff"
    case feedAckFix = "feed.ack_fix"
    // ผู้ใช้และระบบ
    case usersManage = "users.manage"
    /// Suspend or reactivate an account: the Maintainer's only.
    case usersSuspend = "users.suspend"
    /// Edit the roles table (`RoleOverrides`) and the rules list: the Maintainer's only.
    case usersPermissions = "users.permissions"
    /// Open จัดการผู้ใช้และสิทธิ์ (behind the developer key): the Maintainer's only.
    case usersAdmin = "users.admin"
    case companyTemplates = "settings.company_templates"
    case toolsRegister = "tools.register"

    /// The table of user-roles.json (`RoleTableTests` keeps them the same).
    public func access(_ role: UserRole) -> RoleAccess {
        let (m, i, e) = Self.table[self]!
        switch role {
        case .manager: return m
        case .internalTeam: return i
        case .external: return e
        // everything, except what is off for every role (BOQ)
        case .maintainer: return m == .disabled && i == .disabled && e == .disabled ? .disabled : .allow
        }
    }

    /// The cell with the role overrides applied (`config/roleOverrides`). A locked cell keeps the table's value.
    public func access(_ role: UserRole, overrides: RoleOverrides) -> RoleAccess {
        guard !isLocked(for: role), let o = overrides[role, self] else { return access(role) }
        return o
    }

    private typealias Row = (manager: RoleAccess, internalTeam: RoleAccess, external: RoleAccess)
    private static let table: [Capability: Row] = [
        .jobList: (.allow, .allow, .conditional),
        .jobEdit: (.allow, .allow, .deny),
        .jobDelete: (.allow, .allow, .deny),
        .assignExternal: (.allow, .allow, .deny),
        .assignTeam: (.allow, .allow, .deny),
        .mpSetup: (.allow, .allow, .deny),
        .mpProgress: (.allow, .allow, .deny),
        .mpWBSTick: (.allow, .allow, .conditional),
        .moveToInstall: (.allow, .allow, .deny),
        .installTracking: (.allow, .allow, .conditional),
        .overviewReports: (.allow, .allow, .deny),
        .assistantUse: (.allow, .allow, .deny),
        .surveyEdit: (.allow, .allow, .conditional),
        .surveySignRev: (.allow, .allow, .conditional),
        .designLibrary: (.allow, .allow, .deny),
        .tankStandard: (.allow, .view, .view),
        .boqDraft: (.disabled, .disabled, .disabled),
        .boqApprove: (.disabled, .disabled, .disabled),
        .companyDocs: (.allow, .view, .deny),
        .customerPersonalDocs: (.allow, .allow, .deny),
        .permitPPIM: (.allow, .allow, .deny),
        .engineerCertify: (.conditional, .conditional, .conditional),
        .attachFiles: (.allow, .allow, .conditional),
        .driveUpload: (.allow, .allow, .conditional),
        .ercFlow: (.allow, .allow, .deny),
        .stationDocsDrafts: (.allow, .allow, .view),
        .workOrder: (.allow, .allow, .conditional),
        .changeRequest: (.conditional, .conditional, .conditional),
        .punchList: (.allow, .conditional, .conditional),
        .dailyFill: (.allow, .allow, .conditional),
        .weeklyRequest: (.allow, .conditional, .conditional),
        .dailySign: (.allow, .conditional, .deny),
        .iecFillSubmit: (.allow, .allow, .conditional),
        .iecClose: (.allow, .allow, .deny),
        .iclChecklist: (.allow, .allow, .view),
        .iclSiteFill: (.allow, .allow, .conditional),
        .iclSiteSign: (.allow, .allow, .deny),
        .finalSignoff: (.allow, .conditional, .conditional),
        .feedAckFix: (.allow, .allow, .conditional),
        .usersManage: (.allow, .deny, .deny),
        .usersSuspend: (.deny, .deny, .deny),
        .usersPermissions: (.deny, .deny, .deny),
        .usersAdmin: (.deny, .deny, .deny),
        .companyTemplates: (.allow, .deny, .deny),
        .toolsRegister: (.allow, .allow, .view),
    ]
}

/// Who a job is open to beyond the team: the external people assigned to it and its supervising engineer
/// (ผู้ควบคุมงาน). Emails are compared lowercased.
public struct JobAccess: Equatable, Sendable {
    public var externals: [String]
    public var supervisor: String?
    /// The team (internal) members working on the job (`job.assign_team`). It opens nothing: the team sees every job.
    /// It decides whose job it is (`Permissions.isNamed`) and who hears its news first (`Permissions.hearsNews`).
    public var teamMembers: [String]

    public init(externals: [String] = [], supervisor: String? = nil, teamMembers: [String] = []) {
        self.externals = externals
        self.supervisor = supervisor
        self.teamMembers = teamMembers
    }

    /// Someone of ours is named on the job (a team member or the supervisor), so its news goes to them.
    public var hasOwners: Bool { !teamMembers.isEmpty || !(supervisor ?? "").isEmpty }
}

/// What the signed-in member may do. The app hides or disables an action `can` refuses; Firestore's rules enforce the
/// same for the data an external member reads and writes.
public struct Permissions: Equatable, Sendable {
    public var role: UserRole
    /// The signed-in Google account, lowercased; empty before sign-in.
    public var email: String
    /// The Maintainer's changes to the table (`config/roleOverrides`).
    public var overrides: RoleOverrides

    public init(role: UserRole, email: String, overrides: RoleOverrides = RoleOverrides()) {
        self.role = role
        self.email = Self.normalized(email)
        self.overrides = overrides
    }

    /// The cell that applies to this member.
    public func access(_ capability: Capability) -> RoleAccess { capability.access(role, overrides: overrides) }

    /// Before roles were read, everyone could do everything a team member can.
    public static let team = Permissions(role: .internalTeam, email: "")

    public static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The job lists this member among its external people.
    public func isAssigned(_ job: JobAccess?) -> Bool {
        guard let job, !email.isEmpty else { return false }
        return job.externals.contains { Self.normalized($0) == email }
    }

    /// The job lists this member on its team.
    public func isOnTeam(_ job: JobAccess?) -> Bool {
        guard let job, !email.isEmpty else { return false }
        return job.teamMembers.contains { Self.normalized($0) == email }
    }

    /// The job names this member: on its team, its supervisor, or an assigned external (`งานของฉัน`).
    public func isNamed(_ job: JobAccess?) -> Bool { isOnTeam(job) || isSupervisor(job) || isAssigned(job) }

    /// The team's half of `daily.sign`: on the job's team, its supervisor, or the job names none of ours (firestore.rules
    /// `signsFor`). No job to ask about: true.
    public func signsDaily(_ job: JobAccess?) -> Bool {
        guard let job else { return true }
        return !job.hasOwners || isOnTeam(job) || isSupervisor(job)
    }

    /// Whether a job's news (a daily report sent, a test result, an issue) is announced on this member's device: a
    /// manager hears every job's; the others hear a job's when it names them, or when it names none of ours.
    public func hearsNews(_ job: JobAccess?) -> Bool {
        guard !role.managesTeam, let job, job.hasOwners else { return true }
        return isNamed(job)
    }

    public func isSupervisor(_ job: JobAccess?) -> Bool {
        guard let s = job?.supervisor, !email.isEmpty else { return false }
        return Self.normalized(s) == email
    }

    /// May do `capability`, on `job` when it concerns one. A conditional cell is decided here:
    /// - an external member acts only on the jobs assigned to them (signing ones included: the job's signing
    ///   engineer is an assigned external);
    /// - final acceptance (`handover.final_signoff`) is signed by the manager or the job's supervising engineer;
    /// - a daily report (`daily.sign`) is signed by the job's own people: its team members and supervisor, or, on a job
    ///   that names none of ours, any team member (`signsDaily`);
    /// - the team's other conditions (an engineer with a licence certifies, change requests and punch-list steps) are
    ///   left to the person: the app doesn't know licences.
    public func can(_ capability: Capability, on job: JobAccess? = nil) -> Bool {
        switch access(capability) {
        case .allow: return true
        case .view, .deny, .disabled: return false
        case .conditional:
            if role == .external { return isAssigned(job) }
            if capability == .finalSignoff { return isSupervisor(job) }
            if capability == .dailySign { return signsDaily(job) }
            return true
        }
    }

    /// May open it, even read only: a view or conditional cell shows the team everything and an external member
    /// their own jobs (or the things that aren't a job's, such as the tools register).
    public func canView(_ capability: Capability, on job: JobAccess? = nil) -> Bool {
        switch access(capability) {
        case .allow: return true
        case .deny, .disabled: return false
        case .view, .conditional: return role != .external || job == nil || isAssigned(job)
        }
    }
}

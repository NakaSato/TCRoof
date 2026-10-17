import Foundation

/// A member's role (docs/reference/roles/user-roles.json). Kept as `role` on the member's `members/<email>` document;
/// a member without one is `internalTeam`, so accounts made before roles keep what they could do.
public enum UserRole: String, Codable, CaseIterable, Sendable {
    case manager
    case internalTeam = "internal"
    case external

    public var label: String {
        switch self {
        case .manager: "ผู้จัดการ"
        case .internalTeam: "ทีมภายใน"
        case .external: "วิศวกรภายนอก / ผู้รับเหมา"
        }
    }

    /// The `role` field as written in Firestore; nil or unknown reads as the internal team.
    public init(field: String?) {
        self = field.flatMap(UserRole.init(rawValue:)) ?? .internalTeam
    }
}

/// One cell of the roles table.
public enum RoleAccess: String, Sendable {
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

/// The 34 things a role may or may not do, by the ids of user-roles.json.
public enum Capability: String, CaseIterable, Sendable {
    // งานและแผนงาน
    case jobList = "job.list"
    case jobEdit = "job.edit"
    case jobDelete = "job.delete"
    case assignExternal = "job.assign_external"
    case mpSetup = "mp.setup"
    case mpProgress = "mp.progress"
    case moveToInstall = "survey.move_to_install"
    case installTracking = "install.tracking"
    case overviewReports = "overview.reports"
    // สำรวจ ออกแบบ และราคา
    case surveyEdit = "survey.edit"
    case surveySignRev = "survey.sign_rev"
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
    case dailySign = "daily.sign"
    case iecFillSubmit = "iec.fill_submit"
    case iecClose = "iec.close"
    case iclChecklist = "icl.checklist"
    case finalSignoff = "handover.final_signoff"
    case feedAckFix = "feed.ack_fix"
    // ผู้ใช้และระบบ
    case usersManage = "users.manage"
    case companyTemplates = "settings.company_templates"
    case toolsRegister = "tools.register"

    /// The table of user-roles.json (`RoleTableTests` keeps them the same).
    public func access(_ role: UserRole) -> RoleAccess {
        let (m, i, e) = Self.table[self]!
        switch role {
        case .manager: return m
        case .internalTeam: return i
        case .external: return e
        }
    }

    private typealias Row = (manager: RoleAccess, internalTeam: RoleAccess, external: RoleAccess)
    private static let table: [Capability: Row] = [
        .jobList: (.allow, .allow, .conditional),
        .jobEdit: (.allow, .allow, .deny),
        .jobDelete: (.allow, .deny, .deny),
        .assignExternal: (.allow, .allow, .deny),
        .mpSetup: (.allow, .allow, .deny),
        .mpProgress: (.allow, .allow, .deny),
        .moveToInstall: (.allow, .allow, .deny),
        .installTracking: (.allow, .allow, .conditional),
        .overviewReports: (.allow, .allow, .deny),
        .surveyEdit: (.allow, .allow, .conditional),
        .surveySignRev: (.allow, .allow, .conditional),
        .boqDraft: (.disabled, .disabled, .disabled),
        .boqApprove: (.disabled, .disabled, .disabled),
        .companyDocs: (.allow, .view, .deny),
        .customerPersonalDocs: (.allow, .allow, .deny),
        .permitPPIM: (.allow, .allow, .deny),
        .engineerCertify: (.conditional, .conditional, .conditional),
        .attachFiles: (.allow, .allow, .conditional),
        .driveUpload: (.allow, .allow, .deny),
        .ercFlow: (.allow, .allow, .deny),
        .stationDocsDrafts: (.allow, .allow, .deny),
        .workOrder: (.allow, .allow, .conditional),
        .changeRequest: (.conditional, .conditional, .conditional),
        .punchList: (.allow, .conditional, .conditional),
        .dailyFill: (.allow, .allow, .conditional),
        .dailySign: (.allow, .conditional, .deny),
        .iecFillSubmit: (.allow, .allow, .conditional),
        .iecClose: (.allow, .allow, .deny),
        .iclChecklist: (.allow, .allow, .view),
        .finalSignoff: (.allow, .conditional, .conditional),
        .feedAckFix: (.allow, .allow, .conditional),
        .usersManage: (.allow, .deny, .deny),
        .companyTemplates: (.allow, .deny, .deny),
        .toolsRegister: (.allow, .allow, .view),
    ]
}

/// Who a job is open to beyond the team: the external people assigned to it and its supervising engineer
/// (ผู้ควบคุมงาน). Emails are compared lowercased.
public struct JobAccess: Equatable, Sendable {
    public var externals: [String]
    public var supervisor: String?

    public init(externals: [String] = [], supervisor: String? = nil) {
        self.externals = externals
        self.supervisor = supervisor
    }
}

/// What the signed-in member may do. The app hides or disables an action `can` refuses; Firestore's rules enforce the
/// same for the data an external member reads and writes.
public struct Permissions: Equatable, Sendable {
    public var role: UserRole
    /// The signed-in Google account, lowercased; empty before sign-in.
    public var email: String

    public init(role: UserRole, email: String) {
        self.role = role
        self.email = Self.normalized(email)
    }

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

    public func isSupervisor(_ job: JobAccess?) -> Bool {
        guard let s = job?.supervisor, !email.isEmpty else { return false }
        return Self.normalized(s) == email
    }

    /// May do `capability`, on `job` when it concerns one. A conditional cell is decided here:
    /// - an external member acts only on the jobs assigned to them (signing ones included: the job's signing
    ///   engineer is an assigned external);
    /// - final acceptance (`handover.final_signoff`) is signed by the manager or the job's supervising engineer;
    /// - the team's other conditions (our engineer signs daily reports, an engineer with a licence certifies,
    ///   change requests and punch-list steps) are left to the person: the app doesn't know licences.
    public func can(_ capability: Capability, on job: JobAccess? = nil) -> Bool {
        switch capability.access(role) {
        case .allow: return true
        case .view, .deny, .disabled: return false
        case .conditional:
            if role == .external { return isAssigned(job) }
            if capability == .finalSignoff { return isSupervisor(job) }
            return true
        }
    }

    /// May open it, even read only: a view or conditional cell shows the team everything and an external member
    /// their own jobs (or the things that aren't a job's, such as the tools register).
    public func canView(_ capability: Capability, on job: JobAccess? = nil) -> Bool {
        switch capability.access(role) {
        case .allow: return true
        case .deny, .disabled: return false
        case .view, .conditional: return role != .external || job == nil || isAssigned(job)
        }
    }
}

import Foundation

/// The Maintainer's changes to the roles table, kept in `config/roleOverrides` as `{ "<role>|<capability>": "<access>" }`
/// and applied by `Permissions` over the built-in table. They change what the app shows; firestore.rules still decides
/// what the data allows, so the cells it enforces are locked (`Capability.isLocked`).
public struct RoleOverrides: Equatable, Sendable {
    public private(set) var cells: [String: RoleAccess]

    public init(cells: [String: RoleAccess] = [:]) {
        self.cells = cells.filter { Self.parse($0.key) != nil && $0.value != .disabled }
    }

    /// The Firestore document; unknown keys and values are left out.
    public init(document: [String: Any]) {
        var cells: [String: RoleAccess] = [:]
        for (k, v) in document {
            if let v = v as? String, let a = RoleAccess(rawValue: v) { cells[k] = a }
        }
        self.init(cells: cells)
    }

    public static func key(_ role: UserRole, _ capability: Capability) -> String { role.rawValue + "|" + capability.rawValue }

    static func parse(_ key: String) -> (UserRole, Capability)? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let r = UserRole(rawValue: parts[0]), r != .maintainer,
              let c = Capability(rawValue: parts[1]) else { return nil }
        return (r, c)
    }

    public subscript(role: UserRole, capability: Capability) -> RoleAccess? {
        get { cells[Self.key(role, capability)] }
        set { cells[Self.key(role, capability)] = newValue == .disabled ? nil : newValue }
    }

    public var isEmpty: Bool { cells.isEmpty }
    public var count: Int { cells.count }

    /// As written to Firestore.
    public var document: [String: String] { cells.mapValues(\.rawValue) }

    /// The overrides kept on the device, as JSON.
    public var json: String {
        (try? String(data: JSONEncoder().encode(document), encoding: .utf8)) ?? "{}"
    }

    public init(json: String?) {
        let dict = json.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        self.init(document: dict)
    }
}

public extension RoleAccess {
    /// A matrix cell's next value when tapped in edit mode.
    var next: RoleAccess {
        switch self {
        case .allow: .conditional
        case .conditional: .view
        case .view: .deny
        case .deny, .disabled: .allow
        }
    }

    /// The matrix cell's label.
    var label: String {
        switch self {
        case .allow: "✓ ทำได้"
        case .conditional: "มีเงื่อนไข"
        case .view: "ดูอย่างเดียว"
        case .deny: "✕"
        case .disabled: "ปิดใช้งาน"
        }
    }

    /// How much it lets a person do, to compare two roles (`RoleChange`).
    var rank: Int {
        switch self {
        case .allow: 3
        case .conditional: 2
        case .view: 1
        case .deny, .disabled: 0
        }
    }
}

public extension Capability {
    /// Capabilities whose data firestore.rules gates by role: an override can't change what the rules allow, so the
    /// matrix locks them (`บังคับใน rules`). Jobs and their records (an external member writes only their job's IEC
    /// test, daily reports, scans and surveys), deleting a job, the customers' contacts, ICLs, signing daily reports,
    /// closing the IEC test and the member list.
    static let enforcedByRules: Set<Capability> = [
        .jobList, .jobEdit, .jobDelete, .assignExternal, .assignTeam, .mpSetup, .mpProgress, .mpWBSTick, .moveToInstall,
        .surveyEdit, .customerPersonalDocs, .permitPPIM, .ercFlow, .stationDocsDrafts,
        .dailyFill, .dailySign, .iecFillSubmit, .iecClose, .iclChecklist, .iclSiteFill, .iclSiteSign, .usersManage, .designLibrary, .tankStandard,
    ]

    /// The Maintainer's own capabilities.
    static let maintainerOnly: Set<Capability> = [.usersSuspend, .usersPermissions, .usersAdmin]

    /// Why the matrix can't change this cell, or nil when it can.
    func lockReason(for role: UserRole) -> String? {
        if role == .maintainer { return "Maintainer ทำได้ทุกอย่าง" }
        if access(role) == .disabled { return "BOQ ปิดใช้งานทุกบทบาท" }
        if Self.maintainerOnly.contains(self) { return self == .usersSuspend ? "ปิดบัญชีได้เฉพาะ Maintainer" : "เฉพาะ Maintainer" }
        if self == .usersManage, role == .manager { return "ผู้จัดการต้องจัดการผู้ใช้ได้เสมอ" }
        if self == .assistantUse { return "บังคับในฟังก์ชันผู้ช่วย | แก้ใน functions/" }
        if Self.enforcedByRules.contains(self) { return "บังคับใน rules | แก้ใน firestore.rules" }
        return nil
    }

    func isLocked(for role: UserRole) -> Bool { lockReason(for: role) != nil }
}

/// What a role change gives and takes away, for the detail panel's diff box.
public struct RoleChange: Equatable, Sendable {
    public var from: UserRole
    public var to: UserRole
    public var gained: [Capability]
    public var lost: [Capability]

    public init(from: UserRole, to: UserRole, overrides: RoleOverrides = RoleOverrides()) {
        self.from = from
        self.to = to
        let caps = Capability.allCases
        gained = caps.filter { $0.access(to, overrides: overrides).rank > $0.access(from, overrides: overrides).rank }
        lost = caps.filter { $0.access(to, overrides: overrides).rank < $0.access(from, overrides: overrides).rank }
    }
}

/// The kinds of `auditLog/{id}` entries (firestore.rules).
public enum AuditKind: String, CaseIterable, Sendable {
    case role, perm, user, key, sus

    public var label: String {
        switch self {
        case .role: "บทบาท"
        case .perm: "สิทธิ์"
        case .user: "ผู้ใช้"
        case .key: "คีย์"
        case .sus: "ปิดบัญชี"
        }
    }
}

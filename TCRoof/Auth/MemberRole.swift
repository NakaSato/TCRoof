import Foundation
import Observation
import FirebaseFirestore
import TCRoofCore

/// The signed-in member's role, from the `role` field of their `members/<email>` document (firestore.rules lets each
/// member read their own). Kept per account so the app opens offline with the last role it read; a member without a
/// role, or one not read yet, is the internal team, as everyone was before roles.
@MainActor
@Observable
final class MemberRole {
    static let shared = MemberRole()

    private(set) var permissions = Permissions.team

    init() {
        #if DEBUG
        // `-screen` skips sign-in, so `-role` applies here, to `-roleEmail` (default uitest@tcroof.test): the UI tests
        // open a screen as each role (RoleUITests)
        if UserDefaults.standard.string(forKey: "screen") != nil, let role = Self.override {
            permissions = Permissions(role: role, email: UserDefaults.standard.string(forKey: "roleEmail") ?? "uitest@tcroof.test")
        }
        #endif
    }

    private static func key(_ email: String) -> String { "member.role.\(email)" }
    /// The role overrides last read (`config/roleOverrides`), so the app opens offline with them.
    private static let overridesKey = "member.roleOverrides"
    private static var savedOverrides: RoleOverrides { RoleOverrides(json: UserDefaults.standard.string(forKey: overridesKey)) }

    /// The account's last known role, at once; then `refresh` reads the current one.
    func signedIn(_ email: String) {
        let email = Permissions.normalized(email)
        let saved = UserDefaults.standard.string(forKey: Self.key(email))
        #if DEBUG
        let activeEmail = (UserDefaults.standard.string(forKey: "screen") != nil && Self.override != nil)
            ? (UserDefaults.standard.string(forKey: "roleEmail") ?? "uitest@tcroof.test")
            : email
        permissions = Permissions(role: Self.override ?? UserRole(field: saved), email: activeEmail, overrides: Self.savedOverrides)
        #else
        permissions = Permissions(role: Self.override ?? UserRole(field: saved), email: email, overrides: Self.savedOverrides)
        #endif
    }

    /// The role this device last read for an account.
    static func savedRole(_ email: String) -> UserRole {
        override ?? UserRole(field: UserDefaults.standard.string(forKey: key(Permissions.normalized(email))))
    }

    /// Whether an account is on the member list, as far as this device can tell.
    enum Membership { case member, notMember, suspended, unknown }

    /// Called when the server says the signed-in account is no longer a member (removed in the Firebase console or
    /// สมาชิกทีม), or was suspended by a Maintainer (`true`).
    var onRemoved: ((_ suspended: Bool) -> Void)?

    private static func confirmedKey(_ email: String) -> String { "member.confirmed.\(email)" }

    /// The server once listed this account here, so it may open the app offline.
    static func wasConfirmed(_ email: String) -> Bool {
        UserDefaults.standard.bool(forKey: confirmedKey(Permissions.normalized(email)))
    }

    /// Reads `members/<email>` once Firebase has signed in, keeping its role. Only the server's answer says
    /// `notMember`; offline, or a refused read, is `unknown`.
    func membership(of email: String) async -> Membership {
        let email = Permissions.normalized(email)
        guard !email.isEmpty else { return .unknown }
        guard let doc = try? await Firestore.firestore().document("members/\(email)").getDocument() else { return .unknown }
        guard doc.exists else {
            if doc.metadata.isFromCache { return .unknown }
            UserDefaults.standard.removeObject(forKey: Self.confirmedKey(email))
            UserDefaults.standard.removeObject(forKey: Self.key(email))
            return .notMember
        }
        // suspended by a Maintainer: firestore.rules treat it as no member; it can't open the app offline either
        if doc.get("suspended") as? Bool == true, !doc.metadata.isFromCache {
            UserDefaults.standard.removeObject(forKey: Self.confirmedKey(email))
            return .suspended
        }
        let field = doc.get("role") as? String
        UserDefaults.standard.set(field, forKey: Self.key(email))
        UserDefaults.standard.set(true, forKey: Self.confirmedKey(email))
        return .member
    }

    /// Reads the signed-in account's role again; signs it out when the server no longer lists it. A failure
    /// (offline) keeps the role already known.
    func refresh() async {
        let email = permissions.email
        guard !email.isEmpty else { return }
        switch await membership(of: email) {
        case .member:
            guard permissions.email == email else { return }
            let overrides = await Self.readOverrides()
            guard permissions.email == email else { return }
            let field = UserDefaults.standard.string(forKey: Self.key(email))
            permissions = Permissions(role: Self.override ?? UserRole(field: field), email: email, overrides: overrides)
        case .notMember:
            guard permissions.email == email else { return }
            onRemoved?(false)
        case .suspended:
            guard permissions.email == email else { return }
            onRemoved?(true)
        case .unknown:
            break
        }
    }

    /// `config/roleOverrides`, kept for offline; the last read when it can't be read now.
    private static func readOverrides() async -> RoleOverrides {
        guard let doc = try? await Firestore.firestore().document("config/roleOverrides").getDocument() else { return savedOverrides }
        let overrides = RoleOverrides(document: doc.data() ?? [:])
        UserDefaults.standard.set(overrides.json, forKey: overridesKey)
        return overrides
    }

    /// The overrides just saved in จัดการผู้ใช้และสิทธิ์, applied at once.
    func apply(_ overrides: RoleOverrides) {
        UserDefaults.standard.set(overrides.json, forKey: Self.overridesKey)
        permissions.overrides = overrides
    }

    func signedOut() { permissions = .team }

    /// `-role manager|internal|external|maintainer` (DEBUG) tries a role on the simulator.
    static var override: UserRole? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "role").flatMap(UserRole.init(rawValue:))
        #else
        nil
        #endif
    }
}

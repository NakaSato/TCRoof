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

    private static func key(_ email: String) -> String { "member.role.\(email)" }

    /// The account's last known role, at once; then `refresh` reads the current one.
    func signedIn(_ email: String) {
        let email = Permissions.normalized(email)
        let saved = UserDefaults.standard.string(forKey: Self.key(email))
        permissions = Permissions(role: Self.override ?? UserRole(field: saved), email: email)
    }

    /// Reads `members/<email>.role` once Firebase has signed in. A failure (offline) keeps the role already known.
    func refresh() async {
        let email = permissions.email
        guard !email.isEmpty else { return }
        guard let doc = try? await Firestore.firestore().document("members/\(email)").getDocument(), doc.exists else { return }
        let field = doc.get("role") as? String
        UserDefaults.standard.set(field, forKey: Self.key(email))
        guard permissions.email == email else { return }
        permissions = Permissions(role: Self.override ?? UserRole(field: field), email: email)
    }

    func signedOut() { permissions = .team }

    /// `-role manager|internal|external` (DEBUG) tries a role on the simulator.
    private static var override: UserRole? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "role").flatMap(UserRole.init(rawValue:))
        #else
        nil
        #endif
    }
}

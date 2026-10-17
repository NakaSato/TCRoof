import Foundation
import Observation
import FirebaseFirestore
import TCRoofCore

/// The team's names and emails (`directory/<email>`), so a job's ทีมงานของเรา is picked from a list rather than typed:
/// a typed address with a slip, or a personal one, would never reach that person's งานของฉัน or notifications.
/// It holds the internal team and managers, never roles, and only the team reads it (firestore.rules). Each team
/// member writes their own entry when sync starts (`CloudSync`, with the name in settings), and a manager's invites,
/// role changes and removals in สมาชิกทีม keep it in step (`MemberDirectory`).
@MainActor
@Observable
final class TeamDirectory {
    static let shared = TeamDirectory()
    static let collection = "directory"

    struct Person: Identifiable, Equatable {
        var email: String
        var name: String
        var id: String { email }
        /// The name, else the email.
        var label: String { name.isEmpty ? email : name }
    }

    /// Everyone listed, by name.
    private(set) var people: [Person] = []

    func receive(_ documents: [QueryDocumentSnapshot]) {
        people = documents.map { d in
            Person(email: d.documentID, name: ((d.get("name") as? String) ?? "").trimmingCharacters(in: .whitespaces))
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func clear() { people = [] }

    /// The person listed under `email`, if any.
    func person(_ email: String) -> Person? {
        let e = Permissions.normalized(email)
        return people.first { $0.email == e }
    }

    /// A member's entry as written: the email (the document's id) and, when known, the name.
    static func entry(email: String, name: String?) -> [String: Any] {
        var d: [String: Any] = ["email": email]
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { d["name"] = String(name.prefix(100)) }
        return d
    }
}

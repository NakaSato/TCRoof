import Foundation

extension Monitoring.Settings {
    /// The team's settings live in one Firestore document, `config/monitoring` (CHA-91): every team iPad reads it and a
    /// manager's save is the next revision. These are the rules the app follows when it saves and receives a copy.

    /// What a manager's save sends: these values as the revision after `current`'s, signed with `by`. The connection
    /// test results go too, but each iPad keeps its own (`keepingTests`).
    public func signed(after current: Monitoring.Settings, by: String?, at date: Date = Date()) -> Monitoring.Settings {
        var s = self
        s.revision = current.revision + 1
        s.savedBy = by
        s.savedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        return s
    }

    /// Whether a copy from Firestore replaces this device's: one of the same or a later revision does, since Firestore
    /// keeps only one save per revision (the rules refuse a second), so at the same revision its copy is the team's.
    /// Never an older one, and nothing when the values are already these.
    public func takes(_ remote: Monitoring.Settings) -> Bool {
        guard remote.revision >= revision else { return false }
        return remote.keepingTests(of: self) != self
    }

    /// `remote` with this iPad's connection test results for its servers: a token is in one iPad's Keychain, so a
    /// test says whether that iPad reads the server, not another.
    public func keepingTests(of local: Monitoring.Settings) -> Monitoring.Settings {
        var s = self
        for i in s.servers.indices {
            let old = local.servers.first { $0.id == s.servers[i].id }
            s.servers[i].plants = old?.plants
            s.servers[i].testedAt = old?.testedAt
            s.servers[i].testOK = old?.testOK
        }
        return s
    }

    /// Settings set up on this iPad before they synced (revision 0, not the defaults): sent once as revision 1 when
    /// Firestore has none yet, so a manager who already paired the stations doesn't do it again.
    public var unsentSetup: Bool {
        revision == 0 && self != Monitoring.Settings()
    }
}

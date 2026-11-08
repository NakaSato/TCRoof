import Foundation

/// Durable account ownership. Failed cleanup must be retried before exposing local records.
@MainActor
public final class AccountDataTransition {
    private let defaults: UserDefaults
    private let ownerKey = "session.owner"
    private let wipeKey = "session.wipePending"
    /// Whether the records here were kept for an external role: the owner's role can change while they stay.
    private let externalKey = "session.ownerExternal"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var owner: String? { defaults.string(forKey: ownerKey) }
    public var needsCleanup: Bool { defaults.bool(forKey: wipeKey) }

    /// Records `email` signing in, or its role changing, as `external` or not. Returns whether an internal account may
    /// inherit the preceding account's sync fingerprints.
    @discardableResult
    public func signedIn(_ email: String, external: Bool) -> Bool {
        let changed = owner != nil && owner != email
        // The same account made external keeps the team's records it synced as a member: they go too. Records from
        // before the role was recorded go only if the device's records show it (`needsRecordCheck`).
        let recorded = defaults.object(forKey: externalKey) as? Bool
        let demoted = owner == email && external && recorded == false
        // A repeated sign-in, or another account arriving after a failed wipe, must not clear pending cleanup.
        if (owner != email && external) || demoted { defaults.set(true, forKey: wipeKey) }
        // an external owner from before the role was recorded may have been made external then: `checkedRecords`
        if owner == email && external && recorded == nil { defaults.set(true, forKey: checkKey) }
        defaults.set(email, forKey: ownerKey)
        defaults.set(external, forKey: externalKey)
        return changed && !external && !needsCleanup
    }

    private let checkKey = "session.checkOwnerRecords"

    /// The external owner's records here are from before the role was recorded: whether they were kept for the team is
    /// for the device's records to tell (`checkedRecords`).
    public var needsRecordCheck: Bool { defaults.bool(forKey: checkKey) }

    /// The answer to `needsRecordCheck`: records an external account isn't assigned to were kept for the team, and go.
    public func checkedRecords(teamRecordsFound: Bool) {
        if teamRecordsFound { defaults.set(true, forKey: wipeKey) }
        defaults.removeObject(forKey: checkKey)
    }

    public func adopt(_ email: String) {
        if owner == nil { defaults.set(email, forKey: ownerKey) }
    }

    public func cleanupIfNeeded(_ cleanup: () throws -> Void) throws {
        guard needsCleanup else { return }
        try cleanup()
        defaults.removeObject(forKey: wipeKey)
    }
}

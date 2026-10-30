import Foundation

/// Durable account ownership. Failed cleanup must be retried before exposing local records.
@MainActor
public final class AccountDataTransition {
    private let defaults: UserDefaults
    private let ownerKey = "session.owner"
    private let wipeKey = "session.wipePending"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var owner: String? { defaults.string(forKey: ownerKey) }
    public var needsCleanup: Bool { defaults.bool(forKey: wipeKey) }

    /// Returns whether an internal account may inherit the preceding account's sync fingerprints.
    @discardableResult
    public func signedIn(_ email: String, external: Bool) -> Bool {
        let changed = owner != nil && owner != email
        // A repeated sign-in, or another account arriving after a failed wipe, must not clear pending cleanup.
        if owner != email && external { defaults.set(true, forKey: wipeKey) }
        defaults.set(email, forKey: ownerKey)
        return changed && !external && !needsCleanup
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

/// A cached-only project can be removed after a complete server refresh only if it has no local changes.
public enum ProjectCacheReconciliation {
    public static func canRestore(existsLocally: Bool, wasPreviouslySynced: Bool, hasPendingWrite: Bool) -> Bool {
        !existsLocally && !wasPreviouslySynced && !hasPendingWrite
    }

    public static func canRemove(serverContainsID: Bool, knownFingerprint: String?, localFingerprint: String,
                                 hasPendingWrite: Bool) -> Bool {
        !serverContainsID && !hasPendingWrite && knownFingerprint == localFingerprint
    }
}

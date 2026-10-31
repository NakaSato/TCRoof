import Foundation

/// Multiple visible project surfaces share the same transfer scheduler.
public struct BackgroundFileDeferral: Sendable {
    private var owners = Set<UUID>()
    public var isDeferred: Bool { !owners.isEmpty }
    public init() {}

    /// Returns true only when the final visible surface leaves and transfers may resume.
    @discardableResult
    public mutating func setVisible(_ visible: Bool, owner: UUID) -> Bool {
        if visible {
            owners.insert(owner)
            return false
        }
        return owners.remove(owner) != nil && owners.isEmpty
    }
}

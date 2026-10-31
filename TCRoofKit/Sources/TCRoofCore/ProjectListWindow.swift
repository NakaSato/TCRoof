/// Limits the combined survey-and-station list, including projects already cached on the device.
public struct ProjectListWindow: Equatable, Sendable {
    public static let pageSize = 10
    public private(set) var limit = Self.pageSize

    public init() {}
    public func hasMore(total: Int) -> Bool { total > limit }
    public func stationLimit(surveyCount: Int) -> Int { max(0, limit - surveyCount) }
    public mutating func revealMore() { limit += Self.pageSize }
    public mutating func reset() { limit = Self.pageSize }
}

import Foundation

/// Disposable, account-scoped project summaries. An input fingerprint/day match prevents stale links and progress.
public actor ProjectOverviewCache {
    private struct Snapshot: Codable, Equatable {
        let version: Int
        let owner: String
        let day: Date
        let inputDigest: String
        let summaries: [InstallStationSummary]
    }
    private let file: URL
    private var snapshot: Snapshot?
    private var didRead = false

    public init(file: URL) { self.file = file }

    public func load(owner: String, inputs: [InstallSummaryInput], at now: Date) -> [InstallStationSummary]? {
        guard !owner.isEmpty, !Task.isCancelled else { return nil }
        if !didRead {
            didRead = true
            if let data = try? Data(contentsOf: file) {
                snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
                if snapshot == nil || snapshot?.version != 2 { try? FileManager.default.removeItem(at: file) }
            }
        }
        guard let snapshot, snapshot.version == 2, snapshot.owner == owner,
              snapshot.day == MasterSchedule.calendar.startOfDay(for: now), snapshot.inputDigest == (try? digest(inputs)) else { return nil }
        return snapshot.summaries
    }

    public func save(owner: String, inputs: [InstallSummaryInput], summaries: [InstallStationSummary], at now: Date) throws {
        guard !owner.isEmpty, !Task.isCancelled else { return }
        let next = Snapshot(version: 2, owner: owner, day: MasterSchedule.calendar.startOfDay(for: now), inputDigest: try digest(inputs), summaries: summaries)
        guard snapshot != next else { return }
        let data = try JSONEncoder().encode(next)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
#if canImport(Darwin)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
        try data.write(to: file, options: .atomic)
#endif
        snapshot = next
        didRead = true
    }

    private func digest(_ inputs: [InstallSummaryInput]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256Pure.hash(try encoder.encode(inputs)).base64EncodedString()
    }

    public func clear() {
        snapshot = nil
        didRead = true
        try? FileManager.default.removeItem(at: file)
    }
}

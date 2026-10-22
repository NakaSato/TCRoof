import Foundation
import Observation
import TCRoofCore

/// `สรุปโดย AI` on the feed's daily summary, kept on this device (`Assistant.DailyDigest`): asked once when the feed
/// first shows that day's summary, and again when the day's facts have changed since (a report signed later), at most
/// once an hour and three times a day. Only for `assistant.use` (the team and managers); a question counts against the
/// day's limit like one typed in the chat.
@MainActor @Observable
final class FeedDigestStore {
    static let shared = FeedDigestStore()

    struct Entry: Codable, Equatable {
        var text: String
        /// When `text` was written, or the last attempt failed.
        var at: Date
        /// `DailyDigest.json` of the facts `text` was written from.
        var facts: String
        var tries: Int
        var failed: Bool
    }

    static let maxTries = 3
    static let wait: TimeInterval = 60 * 60
    private static let key = "feed.aiDigest"
    private static let keepDays = 7

    private(set) var entries: [String: Entry]
    /// Days being asked now.
    private(set) var busy: Set<String> = []
    @ObservationIgnored var transport: Assistant.Transport = AssistantRouter()

    init() {
        entries = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func entry(_ day: Date) -> Entry? { entries[RoutineReport.dayKey(day)] }
    func isBusy(_ day: Date) -> Bool { busy.contains(RoutineReport.dayKey(day)) }

    /// Asks for `day`'s digest when it has none, or its facts changed and the last one is an hour old.
    func refresh(_ stations: [FeedBuilder.Station], day: Date, now: Date) {
        let k = RoutineReport.dayKey(day)
        guard !busy.contains(k), let facts = Assistant.DailyDigest.facts(stations, day: day, now: now) else { return }
        let json = Assistant.DailyDigest.json(facts)
        let old = entries[k]
        if let old {
            if !old.failed, old.facts == json { return }
            if old.tries >= Self.maxTries || now.timeIntervalSince(old.at) < Self.wait { return }
        }
        busy.insert(k)
        Task {
            defer { busy.remove(k) }
            let tries = (old?.tries ?? 0) + 1
            do {
                let reply = try await transport.complete(Assistant.DailyDigest.request(facts))
                let text = (reply.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw Assistant.Failure.emptyReply }
                entries[k] = Entry(text: text, at: .now, facts: json, tries: tries, failed: false)
            } catch {
                // keep the last good text (asked again once the facts differ from its own); with none, try again in an hour
                let kept = old?.text ?? ""
                entries[k] = Entry(text: kept, at: .now, facts: old?.facts ?? "", tries: tries, failed: kept.isEmpty)
            }
            save()
        }
    }

    private func save() {
        let oldest = RoutineReport.dayKey(RoutineReport.add(RoutineReport.day(.now), -Self.keepDays))
        entries = entries.filter { $0.key >= oldest }
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }
}

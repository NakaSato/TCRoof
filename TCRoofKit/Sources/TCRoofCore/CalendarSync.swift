import Foundation

/// ซิงก์นัดอัตโนมัติ (docs/specs/calendar-travel-expenses-swift.md §A1): which Calendar events to create, move or remove so
/// the survey appointments stay in the iPad's Calendar. Pure: the app passes the jobs, its own links (per device: event
/// ids are device-local and never synced) and whether each linked event still exists, then applies the actions with
/// EventKit.
public enum CalendarSync {
    /// A job and its event as the app last wrote it.
    public struct Link: Codable, Equatable, Sendable {
        public var eventID: String
        public var fingerprint: String
        /// The event was deleted in Calendar: the app doesn't put it back until asked (`เพิ่มอีกครั้ง`).
        public var deletedInCalendar: Bool

        public init(eventID: String, fingerprint: String, deletedInCalendar: Bool = false) {
            self.eventID = eventID
            self.fingerprint = fingerprint
            self.deletedInCalendar = deletedInCalendar
        }
    }

    /// One job as the sync sees it.
    public struct Item: Equatable, Sendable {
        public var jobKey: String
        /// The appointment to keep in Calendar; nil when there is none to keep (no date, completed, another team).
        public var event: SurveyEvent?

        public init(jobKey: String, event: SurveyEvent?) {
            self.jobKey = jobKey
            self.event = event
        }
    }

    public enum Action: Equatable, Sendable {
        case create(jobKey: String, event: SurveyEvent)
        case update(jobKey: String, eventID: String, event: SurveyEvent)
        /// Remove the event, then forget the link.
        case delete(jobKey: String, eventID: String)
        /// Forget the link and leave the event (a past appointment, or one already gone).
        case forget(jobKey: String)
        /// The event was deleted in Calendar: keep the link, flagged, so it isn't recreated.
        case markDeleted(jobKey: String)
    }

    /// What changes, in job order. `exists` says whether a linked event is still in Calendar.
    /// - an upcoming appointment without a link is created, and one whose content changed is updated;
    /// - a linked event deleted in Calendar is flagged, never recreated;
    /// - a past appointment's link is forgotten and its event left alone;
    /// - a job with nothing to keep (completed, date cleared, out of scope, or gone from the device) loses its event.
    public static func plan(_ items: [Item], links: [String: Link], exists: (String) -> Bool, now: Date) -> [Action] {
        var out: [Action] = []
        var seen = Set<String>()
        for item in items.sorted(by: { $0.jobKey < $1.jobKey }) {
            seen.insert(item.jobKey)
            let link = links[item.jobKey]
            guard let event = item.event else {
                if let link { out.append(link.deletedInCalendar || !exists(link.eventID) ? .forget(jobKey: item.jobKey) : .delete(jobKey: item.jobKey, eventID: link.eventID)) }
                continue
            }
            guard event.end > now else {
                if link != nil { out.append(.forget(jobKey: item.jobKey)) }
                continue
            }
            guard let link else {
                out.append(.create(jobKey: item.jobKey, event: event))
                continue
            }
            if link.deletedInCalendar { continue }
            if !exists(link.eventID) { out.append(.markDeleted(jobKey: item.jobKey)); continue }
            if link.fingerprint != fingerprint(event) { out.append(.update(jobKey: item.jobKey, eventID: link.eventID, event: event)) }
        }
        for (key, link) in links.sorted(by: { $0.key < $1.key }) where !seen.contains(key) {
            out.append(link.deletedInCalendar || !exists(link.eventID) ? .forget(jobKey: key) : .delete(jobKey: key, eventID: link.eventID))
        }
        return out
    }

    /// Everything the app writes into an event: a change in any of it updates the event.
    public static func fingerprint(_ e: SurveyEvent) -> String {
        let alarms = e.alarms.map { a -> String in
            switch a {
            case .at(let d): "at:\(Int(d.timeIntervalSince1970))"
            case .before(let s): "before:\(Int(s))"
            }
        }
        return [e.title, "\(Int(e.start.timeIntervalSince1970))", "\(Int(e.end.timeIntervalSince1970))", e.isAllDay ? "allday" : "",
                e.location, e.latitude.map { String(format: "%.6f", $0) } ?? "", e.longitude.map { String(format: "%.6f", $0) } ?? "",
                e.url?.absoluteString ?? "", e.notes, alarms.joined(separator: ",")].joined(separator: "\u{1F}")
    }

    /// The links as kept on the device (a JSON file), and back.
    public static func encode(_ links: [String: Link]) -> Data { (try? JSONEncoder().encode(links)) ?? Data("{}".utf8) }
    public static func decode(_ data: Data?) -> [String: Link] {
        data.flatMap { try? JSONDecoder().decode([String: Link].self, from: $0) } ?? [:]
    }

    /// The default calendar the app makes for the events.
    public static let calendarTitle = "TCRoof นัดสำรวจ"
    /// Event length range in Settings (hours), and its default.
    public static let hoursRange: ClosedRange<Double> = 1...8
    public static let defaultHours: Double = 3
}

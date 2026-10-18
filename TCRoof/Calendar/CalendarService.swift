import SwiftUI
import SwiftData
import EventKit
import TCRoofCore
import TCRoofUI

/// ซิงก์นัดอัตโนมัติ (docs/specs/calendar-travel-expenses-swift.md §A1): keeps the survey appointments in the iPad's
/// Calendar. Off by default; turning it on asks for full Calendar access (write-only access can't read an event back to
/// move it). The job ↔ event links are this device's own (`calendar-links.json`): event ids are device-local, so each
/// iPad manages its own events. `CalendarSync.plan` decides what changes; this applies it with EventKit.
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    enum Status: Equatable {
        /// Sync is off, or the job isn't one it keeps.
        case off
        case synced
        /// Deleted in Calendar: not put back until `readd`.
        case deletedInCalendar
    }

    private enum Key {
        static let on = "calendarSync.on", team = "calendarSync.team", hours = "calendarSync.hours", calendar = "calendarSync.calendar"
    }

    /// Settings › ปฏิทิน.
    var isOn: Bool { didSet { UserDefaults.standard.set(isOn, forKey: Key.on); bump() } }
    /// The team whose jobs are kept; empty for every team.
    var team: String { didSet { UserDefaults.standard.set(team, forKey: Key.team); bump() } }
    /// A timed appointment's length (spec: 3 h, 1–8 in Settings).
    var hours: Double { didSet { UserDefaults.standard.set(hours, forKey: Key.hours); bump() } }
    /// The calendar the events go to; nil until sync makes `TCRoof นัดสำรวจ`.
    var calendarID: String? { didSet { UserDefaults.standard.set(calendarID, forKey: Key.calendar); bump() } }

    private(set) var links: [String: CalendarSync.Link] = [:]
    /// Bumped when a setting or the Calendar database changes, so `CalendarSyncer` runs again.
    private(set) var version = 0
    private(set) var lastError: String?

    let store = EKEventStore()

    private init() {
        let d = UserDefaults.standard
        isOn = d.bool(forKey: Key.on)
        team = d.string(forKey: Key.team) ?? ""
        let h = d.double(forKey: Key.hours)
        hours = h == 0 ? CalendarSync.defaultHours : min(max(h, CalendarSync.hoursRange.lowerBound), CalendarSync.hoursRange.upperBound)
        calendarID = d.string(forKey: Key.calendar)
        links = CalendarSync.decode(try? Data(contentsOf: Self.linksURL))
    }

    private func bump() { version += 1 }

    /// Called when Calendar's database changes (an event deleted or moved there).
    func calendarChanged() { bump() }

    // MARK: permission and calendar

    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var denied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted || s == .writeOnly
    }

    /// Turns sync on: asks for full access, then makes or finds the calendar. False when access was refused.
    func enable() async -> Bool {
        lastError = nil
        if !authorized {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            guard granted else { isOn = false; return false }
        }
        _ = calendar(creating: true)
        isOn = true
        return true
    }

    /// The writable event calendars, for the picker.
    var calendars: [EKCalendar] {
        guard authorized else { return [] }
        return store.calendars(for: .event).filter(\.allowsContentModifications).sorted { $0.title < $1.title }
    }

    /// The chosen calendar; with `creating`, `TCRoof นัดสำรวจ` is found or made when none is chosen.
    func calendar(creating: Bool = false) -> EKCalendar? {
        guard authorized else { return nil }
        if let id = calendarID, let c = store.calendar(withIdentifier: id), c.allowsContentModifications { return c }
        if let mine = store.calendars(for: .event).first(where: { $0.title == CalendarSync.calendarTitle && $0.allowsContentModifications }) {
            calendarID = mine.calendarIdentifier
            return mine
        }
        guard creating else { return nil }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = CalendarSync.calendarTitle
        c.cgColor = UIColor(Theme.navySolid).cgColor
        // iCloud when the device has it, else where new events go, else the device's own
        let sources = store.sources
        c.source = sources.first { $0.sourceType == .calDAV && $0.title.lowercased() == "icloud" }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        do {
            try store.saveCalendar(c, commit: true)
            calendarID = c.calendarIdentifier
            return c
        } catch {
            lastError = "สร้างปฏิทินไม่สำเร็จ: \(error.localizedDescription)"
            return nil
        }
    }

    /// Exchange calendars, and CalDAV ones the app didn't make, may be shared: their events carry the customer's phone
    /// and address (spec §A6). The app can't know for sure, so it warns.
    var mayBeShared: Bool {
        guard let c = calendar() else { return false }
        switch c.source.sourceType {
        case .exchange: return true
        case .calDAV: return c.title != CalendarSync.calendarTitle
        default: return false
        }
    }

    // MARK: sync

    func status(_ jobKey: String) -> Status {
        guard isOn, let link = links[jobKey] else { return .off }
        return link.deletedInCalendar ? .deletedInCalendar : .synced
    }

    /// `เพิ่มอีกครั้ง` on an event deleted in Calendar: the next sync makes it again.
    func readd(_ jobKey: String) {
        links[jobKey] = nil
        saveLinks()
        bump()
    }

    /// Brings Calendar in step with `items` (every job on the device; `event` nil for those not kept).
    func sync(_ items: [CalendarSync.Item]) {
        guard isOn, authorized, let cal = calendar(creating: true) else { return }
        let actions = CalendarSync.plan(items, links: links, exists: { [store] in store.event(withIdentifier: $0) != nil }, now: .now)
        guard !actions.isEmpty else { return }
        lastError = nil
        for action in actions {
            switch action {
            case .create(let key, let e):
                let ev = EKEvent(eventStore: store)
                SurveyEventEditor.fill(ev, from: e, store: store)
                ev.calendar = cal
                if save(ev) { links[key] = .init(eventID: ev.eventIdentifier, fingerprint: CalendarSync.fingerprint(e)) }
            case .update(let key, let id, let e):
                guard let ev = store.event(withIdentifier: id) else { continue }
                SurveyEventEditor.fill(ev, from: e, store: store)
                if save(ev) { links[key]?.fingerprint = CalendarSync.fingerprint(e) }
            case .delete(let key, let id):
                if let ev = store.event(withIdentifier: id) { try? store.remove(ev, span: .thisEvent, commit: false) }
                links[key] = nil
            case .forget(let key):
                links[key] = nil
            case .markDeleted(let key):
                links[key]?.deletedInCalendar = true
            }
        }
        do { try store.commit() } catch { lastError = "บันทึกลงปฏิทินไม่สำเร็จ: \(error.localizedDescription)" }
        saveLinks()
    }

    private func save(_ ev: EKEvent) -> Bool {
        do { try store.save(ev, span: .thisEvent, commit: false); return true } catch {
            lastError = "บันทึกลงปฏิทินไม่สำเร็จ: \(error.localizedDescription)"
            return false
        }
    }

    private static var linksURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calendar-links.json")
    }

    private func saveLinks() {
        let url = Self.linksURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? CalendarSync.encode(links).write(to: url, options: .atomic)
    }

    /// The job as the sync sees it: its appointment while it is one to keep (a date set, not completed, the chosen team).
    func item(_ job: Job) -> CalendarSync.Item {
        let keep = job.hasSurveyAppointment && job.status != .completed && (team.isEmpty || job.team.rawValue == team)
        return .init(jobKey: job.syncID ?? job.code, event: keep ? job.surveyEvent(hours: hours) : nil)
    }
}

extension View {
    /// Runs `CalendarService` sync while signed in as the team: on launch, when jobs change, when a setting changes and
    /// when Calendar's database changes.
    func calendarSync() -> some View { modifier(CalendarSyncer()) }
}

private struct CalendarSyncer: ViewModifier {
    @Query private var jobs: [Job]
    @Environment(\.permissions) private var permissions
    @State private var service = CalendarService.shared

    /// The events' content: a change in a date, an address or a phone reruns the sync. Empty while it is off.
    private var key: [String] {
        guard service.isOn, permissions.can(.jobEdit) else { return [] }
        return jobs.map { j in
            let item = service.item(j)
            return item.jobKey + ":" + (item.event.map(CalendarSync.fingerprint) ?? "-")
        } + ["v\(service.version)"]
    }

    func body(content: Content) -> some View {
        content
            .task(id: key) {
                guard service.isOn, permissions.can(.jobEdit) else { return }
                service.sync(jobs.map(service.item))
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in service.calendarChanged() }
    }
}

import SwiftUI
import EventKit
import EventKitUI
import CoreLocation
import TCRoofUI
import TCRoofCore

/// เพิ่มลงปฏิทิน (docs/specs/calendar-travel-expenses-swift.md §A1, manual mode): the system event editor filled in from
/// `SurveyEvent`. It runs out of process on iPadOS 17, so it needs no Calendar permission; the surveyor taps เพิ่ม, and
/// the app keeps no link to the event (a later date change isn't followed).
struct SurveyEventEditor: UIViewControllerRepresentable {
    let event: SurveyEvent
    let done: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = context.coordinator.store
        vc.event = Self.ekEvent(event, store: context.coordinator.store)
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store = EKEventStore()
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { done() }
    }

    static func ekEvent(_ e: SurveyEvent, store: EKEventStore) -> EKEvent {
        let ev = EKEvent(eventStore: store)
        fill(ev, from: e, store: store)
        return ev
    }

    /// Writes the appointment into an event, new or existing (the automatic sync updates its own in place).
    static func fill(_ ev: EKEvent, from e: SurveyEvent, store: EKEventStore) {
        ev.title = e.title
        ev.isAllDay = e.isAllDay
        ev.startDate = e.start
        ev.endDate = e.end
        ev.notes = e.notes
        ev.url = e.url
        ev.location = e.location
        if !e.location.isEmpty || e.latitude != nil {
            let place = EKStructuredLocation(title: e.location.isEmpty ? e.title : e.location)
            if let lat = e.latitude, let lon = e.longitude { place.geoLocation = CLLocation(latitude: lat, longitude: lon) }
            ev.structuredLocation = place
        } else {
            ev.structuredLocation = nil
        }
        ev.alarms = e.alarms.map { a in
            switch a {
            case .at(let date): EKAlarm(absoluteDate: date)
            case .before(let seconds): EKAlarm(relativeOffset: -seconds)
            }
        }
    }
}

extension Job {
    /// The survey appointment as an event: the job's fields, with its latest linked NO.224 form's coordinator, phone,
    /// address and GPS when filled.
    @MainActor var surveyEvent: SurveyEvent { surveyEvent(hours: CalendarService.shared.hours) }

    /// The same, `hours` long when it has a time (Settings › ปฏิทิน).
    @MainActor func surveyEvent(hours: Double) -> SurveyEvent {
        let form = syncID.flatMap { SurveyModel.shared.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        func text(_ id: String) -> String { form?.values.text(id) ?? "" }
        return SurveyEvent(.init(projectName: projectName, code: code, customerName: customerName, phone: phone, address: address,
                                 province: province, team: team.rawValue, capacityKW: capacityKW, start: surveyDate, syncID: syncID,
                                 formCoordinator: text("coordinator"), formPhone: text("phone"), formAddress: text("address"),
                                 formGPS: text("gps")), hours: hours)
    }

    /// A survey date that is a real appointment (not the placeholder of a job with none yet).
    var hasSurveyAppointment: Bool { Self.isDate(surveyDate) }
}

/// The appointment's `เพิ่มลงปฏิทิน`: opens the filled-in event editor in a sheet.
struct AddToCalendarButton: View {
    let job: Job
    var compact = false
    @State private var event: SurveyEvent?

    var body: some View {
        Button { event = job.surveyEvent } label: {
            Label(compact ? "ปฏิทิน" : "เพิ่มลงปฏิทิน", systemImage: "calendar.badge.plus")
                .font(.sarabun(compact ? 13 : 15, .semibold, relativeTo: .subheadline))
                .frame(minHeight: touchMin)
        }
        .accessibilityIdentifier("addToCalendar")
        .sheet(item: Binding(get: { event.map(Shown.init) }, set: { if $0 == nil { event = nil } })) { s in
            SurveyEventEditor(event: s.event) { event = nil }.ignoresSafeArea()
        }
    }

    private struct Shown: Identifiable {
        let event: SurveyEvent
        var id: String { event.title + event.start.description }
    }
}

/// The appointment's calendar line (spec §A1, §A5): `ซิงก์ลงปฏิทินแล้ว ✓` while automatic sync keeps it,
/// `นัดถูกลบจากปฏิทิน · เพิ่มอีกครั้ง` after it was deleted in Calendar, else `เพิ่มลงปฏิทิน`.
struct AppointmentCalendarControl: View {
    let job: Job
    var compact = false
    @State private var service = CalendarService.shared

    var body: some View {
        let key = job.syncID ?? job.code
        switch service.status(key) {
        case .synced:
            Label(compact ? "ในปฏิทิน" : "ซิงก์ลงปฏิทินแล้ว ✓", systemImage: "calendar.badge.checkmark")
                .font(.sarabun(compact ? 13 : 15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.successText)
                .frame(minHeight: touchMin)
                .accessibilityIdentifier("calendarSynced")
        case .deletedInCalendar:
            Button { service.readd(key) } label: {
                Label(compact ? "เพิ่มอีกครั้ง" : "นัดถูกลบจากปฏิทิน · เพิ่มอีกครั้ง", systemImage: "calendar.badge.exclamationmark")
                    .font(.sarabun(compact ? 13 : 15, .semibold, relativeTo: .subheadline)).frame(minHeight: touchMin)
            }
            .accessibilityIdentifier("calendarReadd")
        case .off:
            AddToCalendarButton(job: job, compact: compact)
        }
    }
}

/// `นำทาง · โทร · ปฏิทิน` under an appointment in the plan (spec §A5), the team's (the customer's phone and address).
struct AppointmentActions: View {
    let job: Job
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 14) {
            if let url = job.mapsURL {
                Button { openURL(url) } label: { Label("นำทาง", systemImage: "location.fill") }
            }
            let digits = job.phone.filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty, let url = URL(string: "tel:\(digits)") {
                Button { openURL(url) } label: { Label("โทร", systemImage: "phone.fill") }
            }
            AppointmentCalendarControl(job: job, compact: true)
            Spacer(minLength: 0)
        }
        .font(.sarabun(13, .semibold, relativeTo: .caption))
        .buttonStyle(.borderless)
        .frame(minHeight: touchMin)
        .padding(.horizontal, 12)
    }
}

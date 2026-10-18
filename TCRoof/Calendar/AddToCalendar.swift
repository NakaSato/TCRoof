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
        }
        ev.alarms = e.alarms.map { a in
            switch a {
            case .at(let date): EKAlarm(absoluteDate: date)
            case .before(let seconds): EKAlarm(relativeOffset: -seconds)
            }
        }
        return ev
    }
}

extension Job {
    /// The survey appointment as an event: the job's fields, with its latest linked NO.224 form's coordinator, phone,
    /// address and GPS when filled.
    @MainActor var surveyEvent: SurveyEvent {
        let form = syncID.flatMap { SurveyModel.shared.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        func text(_ id: String) -> String { form?.values.text(id) ?? "" }
        return SurveyEvent(.init(projectName: projectName, code: code, customerName: customerName, phone: phone, address: address,
                                 province: province, team: team.rawValue, capacityKW: capacityKW, start: surveyDate, syncID: syncID,
                                 formCoordinator: text("coordinator"), formPhone: text("phone"), formAddress: text("address"),
                                 formGPS: text("gps")))
    }

    /// A survey date that is a real appointment (not the placeholder of a job with none yet).
    var hasSurveyAppointment: Bool { Self.isDate(surveyDate) }
}

/// The appointment's `เพิ่มลงปฏิทิน`: opens the filled-in event editor in a sheet.
struct AddToCalendarButton: View {
    let job: Job
    @State private var event: SurveyEvent?

    var body: some View {
        Button { event = job.surveyEvent } label: {
            Label("เพิ่มลงปฏิทิน", systemImage: "calendar.badge.plus").font(.sarabun(15, .semibold, relativeTo: .subheadline))
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

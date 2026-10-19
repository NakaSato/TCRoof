import Foundation
import SwiftData
import CoreLocation
import MapKit
import TCRoofCore

/// The claim settings (docs/specs/calendar-travel-expenses-swift.md §B3, §5), kept on the device.
enum TravelSettings {
    static let companyKey = "travel.company", officeKey = "travel.office", officeLatKey = "travel.officeLat",
               officeLonKey = "travel.officeLon", vehicleKey = "travel.vehicle", plateKey = "travel.plate",
               rateKey = "travel.rate", returnKey = "travel.returnLeg"

    private static var d: UserDefaults { .standard }

    static var company: String { d.string(forKey: companyKey).flatMap { $0.isEmpty ? nil : $0 } ?? "TCRoof" }
    static var office: String { d.string(forKey: officeKey).flatMap { $0.isEmpty ? nil : $0 } ?? "สำนักงาน" }
    static var officeLocation: CLLocationCoordinate2D? {
        guard d.object(forKey: officeLatKey) != nil, d.object(forKey: officeLonKey) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: d.double(forKey: officeLatKey), longitude: d.double(forKey: officeLonKey))
    }
    static var vehicle: TravelClaim.Vehicle { d.string(forKey: vehicleKey).flatMap(TravelClaim.Vehicle.init) ?? .company }
    static var plate: String { d.string(forKey: plateKey) ?? "" }
    static var rate: Double { d.object(forKey: rateKey) == nil ? TravelClaim.defaultRate : d.double(forKey: rateKey) }
    /// The day ends back at the office (decided 2026-10-19); a person on an overnight trip turns it off for that day.
    static var returnLeg: Bool { d.object(forKey: returnKey) == nil ? true : d.bool(forKey: returnKey) }

    static func setOffice(_ c: CLLocationCoordinate2D?) {
        if let c { d.set(c.latitude, forKey: officeLatKey); d.set(c.longitude, forKey: officeLonKey) }
        else { d.removeObject(forKey: officeLatKey); d.removeObject(forKey: officeLonKey) }
    }
}

/// Trips, stamps and distances for the signed-in person.
@MainActor
enum TravelStore {
    /// The person's name on the claim: the settings' name, else the account's.
    static var person: String {
        let name = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? MemberRole.shared.permissions.email : name
    }
    static var owner: String { MemberRole.shared.permissions.email }

    static func trips(_ context: ModelContext, month: String? = nil) -> [Trip] {
        let me = owner
        let all = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.ownerEmail == me }, sortBy: [SortDescriptor(\.date)]))) ?? []
        return month.map { m in all.filter { $0.monthKey == m } } ?? all
    }

    static func expenses(_ context: ModelContext, month: String? = nil) -> [Expense] {
        let me = owner
        let all = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.ownerEmail == me }, sortBy: [SortDescriptor(\.date)]))) ?? []
        return month.map { m in all.filter { $0.monthKey == m } } ?? all
    }

    static func claim(_ context: ModelContext, month: String, create: Bool = false) -> ClaimMonth? {
        let me = owner
        if let found = try? context.fetch(FetchDescriptor<ClaimMonth>(predicate: #Predicate { $0.ownerEmail == me && $0.month == month })).first {
            return found
        }
        guard create else { return nil }
        let c = ClaimMonth(ownerEmail: me, month: month)
        context.insert(c)
        return c
    }

    /// A submitted month is locked until it is withdrawn.
    static func isLocked(_ context: ModelContext, month: String) -> Bool { claim(context, month: month)?.isSubmitted ?? false }

    /// The person's trip on `date`, made from the settings when asked to.
    static func trip(_ context: ModelContext, on date: Date, create: Bool) -> Trip? {
        let day = TravelClaim.calendar.startOfDay(for: date)
        if let t = trips(context).first(where: { $0.date == day }) { return t }
        guard create else { return nil }
        let t = Trip(date: day, ownerEmail: owner, person: person, vehicle: TravelSettings.vehicle, plate: TravelSettings.plate,
                     startPlace: TravelSettings.office, rate: TravelSettings.rate)
        context.insert(t)
        return t
    }

    static func label(_ job: Job) -> String { "\(job.code) \(job.projectName)" }

    /// ถึงสถานีแล้ว / ออกจากสถานี on `job` now: the stamp with this device's location, then the day's distances.
    @discardableResult
    static func stamp(_ kind: TravelClaim.StampKind, job: Job, context: ModelContext, now: Date = .now) async -> TravelClaim.StampResult? {
        guard !isLocked(context, month: TravelClaim.monthKey(now)) else { return nil }
        // the location only for an arrival; a departure keeps the time alone
        let location = kind == .arrive ? await currentLocation() : nil
        guard let trip = trip(context, on: now, create: true) else { return nil }
        var stops = trip.stops
        let result = TravelClaim.stamp(kind, jobID: job.ensureSyncID(), label: label(job), at: now, location: location, stops: &stops)
        trip.stops = stops
        try? context.save()
        await route(trip, context: context)
        return result
    }

    /// One fix within 10 s, or nil (no permission, indoors, the simulator).
    static func currentLocation() async -> TravelClaim.Location? {
        let fetcher = LocationFetcher()
        return await withCheckedContinuation { (done: CheckedContinuation<TravelClaim.Location?, Never>) in
            let once = Once(done)
            fetcher.request { result in
                if case .success(let l) = result {
                    once.finish(TravelClaim.Location(lat: l.coordinate.latitude, lon: l.coordinate.longitude, accuracy: l.horizontalAccuracy))
                } else { once.finish(nil) }
            }
            // the fetcher lives until then
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { _ = fetcher; once.finish(nil) }
        }
    }

    /// Resumes the continuation with whichever comes first, the fix or the timeout.
    private final class Once {
        private var done: CheckedContinuation<TravelClaim.Location?, Never>?
        init(_ done: CheckedContinuation<TravelClaim.Location?, Never>) { self.done = done }
        func finish(_ v: TravelClaim.Location?) { done?.resume(returning: v); done = nil }
    }

    // MARK: distance (§B3)

    /// Works out each leg the person hasn't typed in, start place → stops → back, from Maps' driving routes. A leg whose
    /// end has no position yet stays unknown. Kept on the trip so the claim doesn't move if Maps changes later.
    static func route(_ trip: Trip, context: ModelContext, again: Bool = false) async {
        guard !isLocked(context, month: trip.monthKey) else { return }
        var stops = trip.stops
        var previous = TravelSettings.officeLocation
        var changed = false
        for i in stops.indices {
            let here = await position(stops[i], context: context)
            if !stops[i].legEdited, again || stops[i].legKm == nil, let from = previous, let to = here,
               let km = await drivingKm(from, to) {
                stops[i].legKm = km
                changed = true
            }
            previous = here
        }
        if again || trip.backKm == nil {
            if !TravelSettings.returnLeg || stops.isEmpty {
                if trip.backKm != 0, !stops.isEmpty { trip.backKm = 0 }
            } else if let from = previous, let office = TravelSettings.officeLocation, let km = await drivingKm(from, office) {
                trip.backKm = km
            }
        }
        if changed { trip.stops = stops }
        try? context.save()
    }

    /// Where a stop is: the arrival stamp, else the job's position, else its address found by the geocoder.
    static func position(_ stop: TravelClaim.Stop, context: ModelContext) async -> CLLocationCoordinate2D? {
        if let lat = stop.lat, let lon = stop.lon { return CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        guard let id = stop.jobID,
              let job = try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })).first else { return nil }
        if let lat = job.latitude, let lon = job.longitude { return CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        return await geocode("\(job.address) \(job.province)")
    }

    private static var geocoded: [String: CLLocationCoordinate2D] = [:]

    static func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        let key = address.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let hit = geocoded[key] { return hit }
        let found = try? await CLGeocoder().geocodeAddressString(key).first?.location?.coordinate
        if let found { geocoded[key] = found }
        return found
    }

    /// Road distance by car, rounded to 0.1 km; nil offline or with no route.
    static func drivingKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) async -> Double? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .automobile
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        return (route.distance / 100).rounded() / 10
    }

    // MARK: per job

    /// This person's travel cost on `job` (the job screen's line): its expenses and its share of the mileage.
    static func jobCost(_ job: Job, context: ModelContext) -> (amount: Int, visits: Int) {
        guard let id = job.syncID else { return (0, 0) }
        return TravelClaim.jobCost(id, days: trips(context).map(\.day), items: expenses(context).map(\.item))
    }
}

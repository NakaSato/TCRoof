import Foundation
import TCRoofCore

/// Reads the paired stations' plants from Growatt's OpenAPI for `MonitoringStore`, off the main actor. Every call is
/// read only. One call after another (a server answers 10012 to calls too close together; `GrowattAPI` waits and
/// retries). Only the parts a target asks for are read (CHA-107): the summary (`plant/data`, today's `plant/power`,
/// `device/list`), the inverters' latest readings (`invs_data`, for the string currents), and the history at most once
/// a day each (yesterday's `plant/power` for `เมื่อวานถึงเวลานี้`, `plant/energy` by day for the 30 days and by month for
/// the 12 months). What a call couldn't give is nil in the reading, and the mapping keeps the station's previous value.
actor MonitoringFeed {
    struct Target: Sendable {
        var stationID: String
        var api: GrowattAPI
        var plantID: Int
        /// The station's position, for the forecast (`Monitoring.Forecast.dailyKWhPerKWp`).
        var latitude: Double?
        var longitude: Double?
        var parts: Parts

        /// The caches' key: a station paired with another plant starts again.
        var plantKey: String { stationID + "/" + String(plantID) }
    }

    /// What a read covers: the summary each poll, the rest only for the screen that shows it.
    struct Parts: OptionSet, Hashable, Sendable {
        let rawValue: Int
        /// `plant/data`, today's `plant/power` and `device/list`: the overview's cards, table and alarms.
        static let summary = Parts(rawValue: 1 << 0)
        /// `invs_data`: the string currents.
        static let strings = Parts(rawValue: 1 << 1)
        /// Yesterday's `plant/power`: `เทียบเมื่อวานเวลาเดียวกัน` on today's chart.
        static let yesterday = Parts(rawValue: 1 << 2)
        /// `plant/energy` by day: the 7 and 30 days.
        static let days = Parts(rawValue: 1 << 3)
        /// `plant/energy` by month: the 12 months and this month's energy.
        static let months = Parts(rawValue: 1 << 4)

        static let history: [Parts] = [.yesterday, .days, .months]

        /// The history a chart's range draws.
        static func history(for range: Monitoring.ChartRange) -> Parts {
            switch range {
            case .today: .yesterday
            case .week, .month: .days
            case .year: .months
            }
        }
    }

    struct Reading: Sendable {
        var stationID: String
        var reading: Monitoring.GrowattReading
        /// kWh/kWp a day at the site.
        var forecastDailyKWhPerKWp: Double
        /// The first call that failed, if any.
        var failure: GrowattAPI.Failure?
    }

    /// The day each station's plant's history part was last read.
    private var historyDay: [String: [Int: Date]] = [:]
    /// Each station's plant zone and inverters as its last summary gave them, for a read without the summary.
    private var zones: [String: String] = [:]
    private var inverterSNs: [String: [String]] = [:]
    /// The site's daily yield per station, worked out once (it runs the hourly engine).
    private var forecastDaily: [String: Double] = [:]

    /// One of Growatt's web portal example plants (DEBUG `MonitoringStore.growattWebDemo`): its figures and its day's
    /// 5-minute power (W, on the plant's own date); `plant` nil when they failed.
    struct WebDemoPlant: Sendable {
        var id: String
        var plant: GrowattWebDemo.Plant?
        var day: [Double?]
    }

    /// Lists the portal's example plants on a guest session and reads each at once, as the `บำรุงรักษา` overview does
    /// (`GrowattDemoFeed`): the portal can take about 70 s on a plant it hasn't served lately, which mustn't hold up the
    /// rest. Read only, like every call here.
    func readWebDemo() async -> (plants: [WebDemoPlant], failure: GrowattAPI.Failure?) {
        let web = GrowattWebDemo()
        let list: [(id: String, name: String)]
        do {
            try await web.openGuest()
            list = try await web.plantList()
        } catch let f as GrowattAPI.Failure {
            return ([], f)
        } catch {
            return ([], .badResponse)
        }
        let plants = await withTaskGroup(of: WebDemoPlant.self) { group in
            for p in list {
                group.addTask {
                    guard let plant = try? await web.plant(id: p.id, name: p.name) else { return WebDemoPlant(id: p.id, plant: nil, day: []) }
                    let date = plant.devices.map(\.lastUpdate).max().map { String($0.prefix(10)) } ?? ""
                    let day = date.isEmpty ? [] : (try? await web.dayPower(plantID: p.id, date: date)) ?? []
                    return WebDemoPlant(id: p.id, plant: plant, day: day)
                }
            }
            var out: [String: WebDemoPlant] = [:]
            for await p in group { out[p.id] = p }
            return list.compactMap { out[$0.id] }
        }
        let failed = !plants.isEmpty && plants.allSatisfy { $0.plant == nil }
        return (plants, failed ? .badResponse : nil)
    }

    /// The site's kWh/kWp a day, worked out once per station (it runs the hourly engine).
    func forecast(stationID: String, latitude: Double?, longitude: Double?) -> Double {
        if let d = forecastDaily[stationID] { return d }
        let d = Monitoring.Forecast.dailyKWhPerKWp(latitude: latitude, longitude: longitude)
        forecastDaily[stationID] = d
        return d
    }

    /// The targets read, in order; one with nothing left to read (its history already read today) gives no reading.
    func read(_ targets: [Target], now: Date, calendar: Calendar) async -> [Reading] {
        var out: [Reading] = []
        for t in targets {
            if Task.isCancelled { break }
            if let r = await read(t, now: now, calendar: calendar) { out.append(r) }
        }
        return out
    }

    /// The target's parts still to read: the history parts not read today, and nothing but the summary before a
    /// summary has given the plant's zone.
    private func due(_ t: Target, today: Date) -> Parts {
        var p = t.parts
        for h in Parts.history where historyDay[t.plantKey]?[h.rawValue] == today { p.remove(h) }
        if !p.contains(.summary), zones[t.plantKey] == nil { p = [] }
        return p
    }

    private func read(_ t: Target, now: Date, calendar: Calendar) async -> Reading? {
        let today = calendar.startOfDay(for: now)
        let parts = due(t, today: today)
        guard !parts.isEmpty else { return nil }
        var r = Monitoring.GrowattReading(timezone: zones[t.plantKey])
        var failure: GrowattAPI.Failure?
        func call<T: Sendable>(_ f: () async throws -> T) async -> T? {
            do { return try await f() } catch let e as GrowattAPI.Failure { failure = failure ?? e } catch { failure = failure ?? .badResponse }
            return nil
        }
        let daily = forecast(stationID: t.stationID, latitude: t.latitude, longitude: t.longitude)

        if parts.contains(.summary) {
            r.data = await call { try await t.api.data(plantID: t.plantID) }
            // a token refused or no network: the other calls would fail the same way
            guard let data = r.data else { return Reading(stationID: t.stationID, reading: r, forecastDailyKWhPerKWp: daily, failure: failure) }
            zones[t.plantKey] = data.timezone
            r.timezone = data.timezone
        }
        let zone = Monitoring.GrowattMap.timeZone(r.timezone ?? "")
        func day(_ back: Int) -> String {
            let d = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return Monitoring.GrowattMap.dayText(d.addingTimeInterval(12 * 3600), zone: zone)
        }
        if parts.contains(.summary) {
            r.power = await call { try await t.api.power(plantID: t.plantID, date: day(0)) }
            r.devices = await call { try await t.api.devices(plantID: t.plantID) }
            if let d = r.devices { inverterSNs[t.plantKey] = d.filter(\.isInverter).map(\.sn) }
        }
        // the inverters' string currents (CHA-106): `invs_data` isn't confirmed on the live server yet, so its failure
        // only keeps the last currents and never shows in the header
        if parts.contains(.strings), let sns = inverterSNs[t.plantKey], !sns.isEmpty {
            r.inverters = try? await t.api.latest(deviceSNs: sns)
        }

        func done(_ part: Parts) { historyDay[t.stationID, default: [:]][part.rawValue] = today }
        if parts.contains(.yesterday) {
            r.yesterdayPower = await call { try await t.api.power(plantID: t.plantID, date: day(1)) }
            if r.yesterdayPower != nil { done(.yesterday) }
        }
        if parts.contains(.days) {
            // the guide limits a range: a week of days at a time, the 29 days before today in five calls
            var days: [GrowattAPI.EnergyPoint]? = []
            for chunk in [(29, 23), (22, 16), (15, 9), (8, 2), (1, 1)] {
                guard let rows = await call({ try await t.api.energy(plantID: t.plantID, start: day(chunk.0), end: day(chunk.1), unit: .day) }) else {
                    days = nil
                    break
                }
                days?.append(contentsOf: rows)
            }
            r.days = days
            if days != nil { done(.days) }
        }
        if parts.contains(.months) {
            let firstMonth = calendar.date(byAdding: .month, value: -11, to: calendar.dateInterval(of: .month, for: now)?.start ?? today) ?? today
            r.months = await call {
                try await t.api.energy(plantID: t.plantID, start: Monitoring.GrowattMap.dayText(firstMonth.addingTimeInterval(12 * 3600), zone: zone),
                                       end: day(0), unit: .month)
            }
            if r.months != nil { done(.months) }
        }
        return Reading(stationID: t.stationID, reading: r, forecastDailyKWhPerKWp: daily, failure: failure)
    }
}

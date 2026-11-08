import Foundation
import TCRoofCore

/// Reads the paired stations' plants from Growatt's OpenAPI for `MonitoringStore`, off the main actor. Every call is
/// read only. One call after another (a server answers 10012 to calls too close together; `GrowattAPI` waits and
/// retries): each poll `plant/data`, today's `plant/power` and `device/list` per station, and once a day the history
/// (yesterday's `plant/power` for `เมื่อวานถึงเวลานี้`, `plant/energy` by day for the 30 days and by month for the
/// 12 months). What a call couldn't give is nil in the reading, and the mapping keeps the station's previous value.
actor MonitoringFeed {
    struct Target: Sendable {
        var stationID: String
        var api: GrowattAPI
        var plantID: Int
        /// The station's position, for the forecast (`Monitoring.Forecast.dailyKWhPerKWp`).
        var latitude: Double?
        var longitude: Double?
    }

    struct Reading: Sendable {
        var stationID: String
        var reading: Monitoring.GrowattReading
        /// kWh/kWp a day at the site.
        var forecastDailyKWhPerKWp: Double
        /// The first call that failed, if any.
        var failure: GrowattAPI.Failure?
    }

    /// The day each station's history was last read whole.
    private var historyDay: [String: Date] = [:]
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

    func read(_ targets: [Target], now: Date, calendar: Calendar) async -> [Reading] {
        var out: [Reading] = []
        for t in targets {
            if Task.isCancelled { break }
            out.append(await read(t, now: now, calendar: calendar))
        }
        return out
    }

    private func read(_ t: Target, now: Date, calendar: Calendar) async -> Reading {
        var r = Monitoring.GrowattReading()
        var failure: GrowattAPI.Failure?
        func call<T: Sendable>(_ f: () async throws -> T) async -> T? {
            do { return try await f() } catch let e as GrowattAPI.Failure { failure = failure ?? e } catch { failure = failure ?? .badResponse }
            return nil
        }
        let daily = forecastDaily[t.stationID] ?? Monitoring.Forecast.dailyKWhPerKWp(latitude: t.latitude, longitude: t.longitude)
        forecastDaily[t.stationID] = daily

        r.data = await call { try await t.api.data(plantID: t.plantID) }
        // a token refused or no network: the other calls would fail the same way
        if r.data == nil { return Reading(stationID: t.stationID, reading: r, forecastDailyKWhPerKWp: daily, failure: failure) }

        let zone = Monitoring.GrowattMap.timeZone(r.data?.timezone ?? "")
        let today = calendar.startOfDay(for: now)
        func day(_ back: Int) -> String {
            let d = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return Monitoring.GrowattMap.dayText(d.addingTimeInterval(12 * 3600), zone: zone)
        }
        r.power = await call { try await t.api.power(plantID: t.plantID, date: day(0)) }
        r.devices = await call { try await t.api.devices(plantID: t.plantID) }

        if historyDay[t.stationID] != today {
            r.yesterdayPower = await call { try await t.api.power(plantID: t.plantID, date: day(1)) }
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
            let firstMonth = calendar.date(byAdding: .month, value: -11, to: calendar.dateInterval(of: .month, for: now)?.start ?? today) ?? today
            r.months = await call {
                try await t.api.energy(plantID: t.plantID, start: Monitoring.GrowattMap.dayText(firstMonth.addingTimeInterval(12 * 3600), zone: zone),
                                       end: day(0), unit: .month)
            }
            if r.yesterdayPower != nil, r.days != nil, r.months != nil { historyDay[t.stationID] = today }
        }
        return Reading(stationID: t.stationID, reading: r, forecastDailyKWhPerKWp: daily, failure: failure)
    }
}

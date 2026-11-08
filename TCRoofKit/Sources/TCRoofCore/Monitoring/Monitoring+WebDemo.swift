import Foundation

extension Monitoring {
    /// Growatt's web portal example plants (`GrowattWebDemo`) as Monitor rows, for trying the page without the company's
    /// token (DEBUG `-growattDemo YES`, or the PWA settings' `สถานีตัวอย่าง Growatt` switch). Each plant is turned
    /// into the reading a paired OpenAPI plant gives (`GrowattReading`), so `GrowattMap.station` works out its row,
    /// offline state, alarms and today's curve the same way. The portal gives no history, so the 30 days and
    /// 12 months stay empty.
    public enum GrowattWebMap {
        /// Row ids, as the `บำรุงรักษา` overview's (`growatt-web-<id>`), so the station page loads the plant's own figures.
        public static func stationID(_ plantID: String) -> String { "growatt-web-" + plantID }

        /// The portal names no zone. A plant still reporting is read in the zone that puts its last reading at `now`
        /// (whole half hours, at most 14 h off); one that isn't keeps `GrowattMap.defaultZone`, so its age shows.
        public static func zone(lastUpdate: String, reporting: Bool, now: Date) -> TimeZone {
            let gmt = TimeZone(secondsFromGMT: 0) ?? .current
            guard reporting, let asGMT = GrowattMap.date(lastUpdate, zone: gmt) else { return GrowattMap.defaultZone }
            let offset = (asGMT.timeIntervalSince(now) / 1800).rounded() * 1800
            guard abs(offset) <= 14 * 3600 else { return GrowattMap.defaultZone }
            return TimeZone(secondsFromGMT: Int(offset)) ?? GrowattMap.defaultZone
        }

        /// `GMT+07:00`, as `GrowattMap.timeZone` reads it.
        static func zoneText(_ zone: TimeZone) -> String {
            let s = zone.secondsFromGMT()
            return String(format: "GMT%@%02d:%02d", s < 0 ? "-" : "+", abs(s) / 3600, abs(s) % 3600 / 60)
        }

        /// The plant as one poll's reading: `plant/data` from its devices' sums, `plant/power` from the day's 5-minute
        /// samples (`GrowattWebDemo.dayPower`, W, on the date of its last reading) and `device/list` from its devices.
        public static func reading(_ plant: GrowattWebDemo.Plant, day: [Double?], now: Date) -> GrowattReading {
            let last = plant.devices.map(\.lastUpdate).filter { !$0.isEmpty }.max() ?? ""
            let reporting = plant.devices.contains { $0.status != -1 }
            let zone = zone(lastUpdate: last, reporting: reporting, now: now)
            let data = GrowattAPI.PlantData(
                todayEnergy: plant.devices.reduce(0) { $0 + $1.eToday },
                monthlyEnergy: plant.devices.reduce(0) { $0 + $1.eMonth },
                yearlyEnergy: 0,
                totalEnergy: plant.eTotal > 0 ? plant.eTotal : plant.devices.reduce(0) { $0 + $1.eTotal },
                // never reported: no device, or none with a time
                currentPower: last.isEmpty ? -1 : plant.devices.filter { !$0.isError }.reduce(0) { $0 + $1.pac } / 1000,
                lastUpdate: last,
                timezone: zoneText(zone))
            let date = String(last.prefix(10))
            let power: [GrowattAPI.PowerPoint]? = date.isEmpty ? nil : day.enumerated().map { i, w in
                let minutes = i * Monitoring.slotMinutes
                return GrowattAPI.PowerPoint(time: String(format: "%@ %02d:%02d", date, minutes / 60, minutes % 60), power: w)
            }
            let devices = plant.devices.map { d in
                GrowattAPI.Device(sn: d.sn, type: d.typeName.lowercased() == "storage" ? 2 : nil, model: d.model,
                                  status: d.status, lost: d.status == -1, lastUpdate: d.lastUpdate, datalogger: d.datalogger)
            }
            return GrowattReading(data: data, power: power, devices: devices)
        }

        /// The plant's row: its size (the plant's, else its inverters'), its inverters, and `reading` mapped as a paired
        /// station's. `forecastDailyKWhPerKWp` defaults to the figure without a site (the portal gives no position).
        public static func station(_ plant: GrowattWebDemo.Plant, day: [Double?], previous: Station?, now: Date,
                                   offlineAfter: Int, forecastDailyKWhPerKWp: Double? = nil,
                                   belowExpectedPercent: Int? = nil, calendar: Calendar = .current) -> Station {
            let watts = plant.nominalPower > 0 ? plant.nominalPower : plant.devices.reduce(0) { $0 + $1.nominalPower }
            let inverters = plant.devices.filter { $0.typeName.lowercased() != "storage" }.count
            let base = Station(id: stationID(plant.id), name: plant.name, kWp: watts / 1000, inverters: max(inverters, 1))
            return GrowattMap.station(base, reading: reading(plant, day: day, now: now), previous: previous, now: now,
                                      offlineAfter: offlineAfter,
                                      forecastDailyKWhPerKWp: forecastDailyKWhPerKWp
                                          ?? Forecast.dailyKWhPerKWp(latitude: nil, longitude: nil),
                                      belowExpectedPercent: belowExpectedPercent, calendar: calendar)
        }
    }
}

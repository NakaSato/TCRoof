import Foundation

/// A handed-over station's real figures on the `บำรุงรักษา` overview and its station page: the Monitoring station that
/// `MonitoringStore`'s poll read from Growatt's OpenAPI (`GrowattAPI`, the plant it is paired with in ตั้งค่า Monitoring,
/// with this device's token). A station not paired, or not read yet, keeps its row as it was.
extension MaintenanceStationSummary {
    /// The row with the station's reading: today's energy and forecast, PR (only with an irradiance sensor), its health,
    /// power now, inverters reporting, the last reading's time and today's hourly power for the sparkline.
    public func monitored(by s: Monitoring.Station, now: Date, offlineAfter: Int,
                          calendar: Calendar = .current) -> MaintenanceStationSummary {
        guard s.paired, let last = s.lastReading else { return self }
        var r = self
        let status: Status = switch s.health(now: now, offlineAfter: offlineAfter) {
        case .normal: .normal
        case .alarm: .alarm
        case .offline: .offline
        }
        if r.kWp <= 0 { r.kWp = s.kWp }
        r.energy = s.energyToday ?? 0
        r.expected = s.expectedToday ?? 0
        r.pr = s.prToday ?? 0
        r.status = status
        r.powerNow = status == .offline ? nil : s.powerNow
        r.invertersOnline = s.invertersOnline
        r.invertersTotal = s.inverters
        r.updated = Monitoring.clock(last, calendar: calendar)
        r.hourly = Monitoring.hourly(s.curve)
        // the card shows the note only without power now: offline says since when, else the first fault
        let issue = s.alarms.first { $0.source != .tcroof }.map { "\($0.part) \($0.label)" }
        r.note = ["Growatt", status == .offline ? "ไม่มีข้อมูลตั้งแต่ " + r.updated : issue ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " | ")
        return r
    }
}

extension MaintenanceStationDetail {
    /// The station page with the station's reading in place of the sample figures: the issue, today's hourly power
    /// against the forecast, the last reading, PR, this month's energy and its forecast, CO₂, the total and the
    /// inverters' states. Growatt has no repairs, PM, contractor or equipment list, so those stay as `mock(for:)` gives
    /// them, as on a station that isn't paired.
    public static func monitored(summary: MaintenanceStationSummary, station s: Monitoring.Station, now: Date,
                                 offlineAfter: Int, calendar: Calendar = .current) -> MaintenanceStationDetail {
        let row = summary.monitored(by: s, now: now, offlineAfter: offlineAfter, calendar: calendar)
        var d = MaintenanceStationDetail.mock(for: row)
        guard s.paired, s.lastReading != nil else { return d }
        let actual = Monitoring.hourly(s.curve)
        let expected = Monitoring.hourly(s.expectedCurve.map { Optional($0) })
        d.actualHourly = actual
        d.expectedHourly = expected
        d.hourlyMax = max(actual.max() ?? 0, expected.max() ?? 0, row.kWp * 0.8, 0.1)
        d.lastUpdated = row.updated.isEmpty ? "—" : row.updated
        d.prToday = s.prToday ?? 0
        let month = s.months.last
        d.energyThisMonth = month?.energy.map(Monitoring.energyText) ?? "—"
        d.energyExpectedThisMonth = month?.expected.map { "คาด " + Monitoring.energyText($0) } ?? ""
        d.co2SavedThisMonth = month?.energy.map { Monitoring.co2Text($0 * Monitoring.co2PerKWh) } ?? "—"
        d.energyTotal = s.totalEnergy.map(Monitoring.energyText) ?? ""
        let offline = row.status == .offline
        d.inverters = (0..<max(s.inverters, 1)).map { i in
            let name = "INV \(i + 1)"
            let alarm = s.alarms.first { $0.part == name && $0.source != .tcroof }
            let statusText = offline ? "ออฟไลน์" : alarm?.label ?? "ปกติ"
            return InverterItem(id: s.id + "/" + name, name: name, model: alarm?.detail ?? "", power: "—",
                                statusText: statusText, isError: offline || alarm != nil)
        }
        let first = s.alarms.first { $0.source != .tcroof }
        switch row.status {
        case .normal:
            d.issueTitle = nil; d.issueSubtitle = nil
        case .alarm:
            d.issueTitle = first.map { "\($0.part) \($0.label)" } ?? "อินเวอร์เตอร์ไม่รายงาน"
            d.issueSubtitle = "จาก Growatt" + (first.map { " | " + $0.detail } ?? "")
        case .offline:
            d.issueTitle = "สถานีออฟไลน์"
            d.issueSubtitle = first?.detail ?? "ไม่มีข้อมูลจาก Growatt"
        }
        return d
    }
}

extension Monitoring {
    /// The hours 06:00 … 18:00 of a day's 5-minute power (kW, `slots` from 00:00) as 13 hourly means, kW; 0 for an
    /// hour with nothing read.
    public static func hourly(_ curve: [Double?], from first: Int = 6, count: Int = 13) -> [Double] {
        let perHour = 60 / slotMinutes
        return (first..<(first + count)).map { h in
            let slice = curve.dropFirst(h * perHour).prefix(perHour).compactMap { $0 }
            return slice.isEmpty ? 0 : slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// `14:55` on the device's clock.
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `17.6 MWh`, `850.0 kWh`.
    static func energyText(_ kWh: Double) -> String {
        kWh >= 1000 ? String(format: "%.1f MWh", kWh / 1000) : String(format: "%.1f kWh", kWh)
    }

    /// `8.8 t`, `425 kg`.
    static func co2Text(_ kg: Double) -> String {
        kg >= 1000 ? String(format: "%.1f t", kg / 1000) : String(format: "%.0f kg", kg)
    }
}

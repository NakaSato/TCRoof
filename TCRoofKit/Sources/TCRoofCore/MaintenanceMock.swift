import Foundation

/// Demo only: the maintenance figures a monitoring source doesn't give (Growatt has no expected energy, PR, PM dates,
/// repair tickets or module list), made up from the plant's size so the overview and station page look complete. It
/// fills only what is missing, never a figure the source gave, and the same `seed` (the plant's id) always gives the
/// same values.
public enum MaintenanceMock {
    /// kWh per kWp in a day, Thailand.
    static let yieldPerKWp = 4.2
    /// Irradiation a day, kWh/m², for the made-up PR.
    static let referenceYield = 5.0
    /// The module the made-up module list counts.
    static let moduleWatts = 570.0

    /// A row with its missing figures filled: expected energy from its size, a PR from today's energy (kept between 55
    /// and 92 %), a next PM 3–42 days ahead, and one open repair for a station in alarm.
    public static func fill(_ s: MaintenanceStationSummary, seed: String, now: Date = .now,
                            calendar: Calendar = .current) -> MaintenanceStationSummary {
        var s = s
        if s.expected <= 0, s.kWp > 0 { s.expected = (s.kWp * yieldPerKWp).rounded() }
        if s.pr <= 0, s.status != .offline, s.kWp > 0, s.energy > 0 {
            s.pr = min(max(s.energy / s.kWp / referenceYield * 100, 55), 92).rounded()
        }
        if s.nextPM == nil {
            let today = calendar.startOfDay(for: now)
            s.nextPM = calendar.date(byAdding: .day, value: 3 + number(seed) % 40, to: today)
        }
        if s.status == .alarm, s.openRepairs == 0 { s.openRepairs = 1 }
        return s
    }

    /// A station page with its missing parts filled: the row as `fill`, the expected hourly curve, PR, and the sample
    /// repairs, PM and module list of `MaintenanceStationDetail.mock`.
    public static func fill(_ d: MaintenanceStationDetail, seed: String, now: Date = .now,
                            calendar: Calendar = .current) -> MaintenanceStationDetail {
        var d = d
        d.summary = fill(d.summary, seed: seed, now: now, calendar: calendar)
        let s = d.summary, sample = MaintenanceStationDetail.mock(for: s)
        if d.expectedHourly.allSatisfy({ $0 <= 0 }), s.kWp > 0 { d.expectedHourly = expectedHourly(kWp: s.kWp) }
        d.hourlyMax = max(d.hourlyMax, (d.expectedHourly + d.actualHourly).max() ?? 0)
        if d.prToday <= 0 { d.prToday = s.pr }
        if d.tickets.isEmpty { d.tickets = sample.tickets }
        if d.nextPM == nil { d.nextPM = sample.nextPM }
        if d.pmHistory.isEmpty { d.pmHistory = sample.pmHistory }
        if !d.equipmentGroups.contains(where: { $0.title.hasPrefix("แผง") }), s.kWp > 0 {
            let modules = Int((s.kWp * 1000 / moduleWatts).rounded(.up))
            d.equipmentGroups.insert(EquipmentGroup(title: "แผง (ตัวอย่าง)", rows: [
                EquipmentRow(key: "Znshine \(Int(moduleWatts)) W", value: "\(modules) แผง"),
            ]), at: 0)
        }
        return d
    }

    /// 06:00 … 18:00, kW: a clear day's bell peaking at 80 % of the size at noon.
    static func expectedHourly(kWp: Double) -> [Double] {
        (0..<13).map { h in
            let x = (Double(h) - 6) / 6
            return max(0, (1 - x * x)) * kWp * 0.8
        }
    }

    /// A small number from the seed, the same on every device and launch (`hashValue` is not).
    static func number(_ seed: String) -> Int {
        seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
    }
}

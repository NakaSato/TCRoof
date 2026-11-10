import Foundation

extension Monitoring {
    /// The board's example fleet (`iPadPwaMonitoring`: six stations, 965 kWp), for `-monitoringDemo YES` and the tests.
    /// Example values only, never shown for real stations. Each station's curve is built so its day adds up to the
    /// board's figure, so the cards, the chart and the table agree. `now` is the board's 14:55 unless given.
    public static func demo(now: Date? = nil, calendar: Calendar = .current) -> [Station] {
        let clock = now ?? demoNow(calendar: calendar)
        let today = calendar.startOfDay(for: clock)
        func at(_ h: Int, _ m: Int) -> Date { calendar.date(bySettingHour: h, minute: m, second: 0, of: today) ?? today }

        struct Spec {
            var mp: Int, name: String, kWp: Double, inverters: Int, online: Int
            var soFar: Double, expected: Double, total: Double, yesterday: Double
            /// Readings stop here (offline), or the output drops to `after` of itself from here (an inverter down).
            var stop: (h: Int, m: Int)? = nil
            var drop: (h: Int, m: Int, after: Double)? = nil
            var sensor = false
            var alarms: [Alarm] = []
            /// INV 1's string (MPPT, place) carrying 31 % of its share.
            var lowString: (mppt: Int, string: Int)? = nil
        }
        let specs: [Spec] = [
            Spec(mp: 44, name: "สถานีผลิตน้ำสามพราน", kWp: 120, inverters: 1, online: 0, soFar: 0, expected: 430, total: 160_000,
                 yesterday: 410, stop: (9, 0),
                 alarms: [Alarm(id: "mp44-lost", source: .lost, part: "ดาต้าล็อกเกอร์", detail: "ไม่มีข้อมูลตั้งแต่ 09:00 · ผลิตจริงไม่ทราบ",
                                since: at(9, 0), workOrder: "TK-0415", loss: .atMost(430))]),
            Spec(mp: 25, name: "สถานีผลิตน้ำนครชัยศรี", kWp: 220, inverters: 2, online: 1, soFar: 410, expected: 790, total: 290_000,
                 yesterday: 760, drop: (9, 50, 0.5),
                 alarms: [Alarm(id: "mp25-124", source: .growatt, code: "124", part: "INV 2", detail: "No AC Connection",
                                since: at(9, 50), occurrences: 4, workOrder: "TK-0412", loss: .measured(380)),
                          Alarm(id: "mp25-117", source: .growatt, code: "117", part: "INV 2", detail: "Relay fault",
                                since: at(9, 48), occurrences: 1, workOrder: "TK-0412", loss: .unknown)]),
            // INV 1's MPPT 4 b carries 31 % of the others' current: the fleet raises its `TCRoof` line (`demoRaised`)
            Spec(mp: 12, name: "สถานีผลิตน้ำบางเลน", kWp: 180, inverters: 2, online: 2, soFar: 612, expected: 650, total: 240_000,
                 yesterday: 640, sensor: true, lowString: (3, 1)),
            Spec(mp: 52, name: "สถานีผลิตน้ำกำแพงแสน", kWp: 200, inverters: 2, online: 2, soFar: 690, expected: 720, total: 265_000,
                 yesterday: 450, sensor: true),
            Spec(mp: 7, name: "สถานีผลิตน้ำดอนตูม", kWp: 95, inverters: 1, online: 1, soFar: 330, expected: 345, total: 155_000,
                 yesterday: 330),
            Spec(mp: 31, name: "สถานีผลิตน้ำพุทธมณฑล", kWp: 150, inverters: 1, online: 1, soFar: 530, expected: 540, total: 200_000,
                 yesterday: 333),
        ]

        let nowSlot = Forecast.slot(of: clock, calendar: calendar)
        let unit = Forecast.curve(dailyKWh: 1)
        let unitSoFar = Forecast.energy(unit, through: nowSlot)
        return specs.map { s in
            // the forecast: a clear day whose part to now is the board's expected figure
            let day = unitSoFar > 0 ? s.expected / unitSoFar : s.expected
            let expectedCurve = unit.map { $0 * day }
            let stopSlot = s.stop.map { ($0.h * 60 + $0.m) / Monitoring.slotMinutes }
            let dropSlot = s.drop.map { ($0.h * 60 + $0.m) / Monitoring.slotMinutes }
            var raw: [Double?] = expectedCurve.enumerated().map { i, e in
                if i > nowSlot { return nil }
                if let st = stopSlot, i >= st { return nil }
                // a little cloud, the same every time
                let wobble = 1 + 0.06 * sin(Double(i) * 0.7 + Double(s.mp))
                var v = e * wobble
                if let d = dropSlot, let f = s.drop?.after, i >= d { v *= f }
                return v
            }
            // scaled so the day so far is the board's figure (an offline station keeps what it made before it stopped)
            let made = Forecast.energy(raw, through: nowSlot) ?? 0
            if s.stop == nil, made > 0 { raw = raw.map { $0.map { $0 * s.soFar / made } } }
            // offline: the logger's day total never came in (the board's `0 / 430`, `ผลิตจริงไม่ทราบ`); the curve keeps
            // the morning it sent
            let energy = s.stop == nil ? (Forecast.energy(raw, through: nowSlot) ?? 0) : s.soFar
            let last: Date = s.stop.map { at($0.h, $0.m) } ?? clock
            let power: Double? = s.stop == nil ? raw[min(nowSlot, raw.count - 1)] : nil
            let days: [Period] = (0..<30).reversed().compactMap { back -> Period? in
                guard let d = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
                if back == 0 { return Period(start: d, energy: energy, expected: s.expected) }
                let x = s.kWp * 4.0
                let f = 0.82 + 0.16 * (0.5 + 0.5 * sin(Double(back * 3 + s.mp)))
                return Period(start: d, energy: x * f, expected: x)
            }
            let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            let months: [Period] = (0..<12).reversed().compactMap { back -> Period? in
                guard let m = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
                let x = s.kWp * 4.0 * 30
                let f = 0.85 + 0.12 * (0.5 + 0.5 * cos(Double(back + s.mp)))
                return Period(start: m, energy: back == 0 ? x * f * 0.25 : x * f, expected: back == 0 ? x * 0.27 : x)
            }
            var station = Station(id: "demo-mp\(s.mp)", mpNumber: s.mp, name: s.name, kWp: s.kWp, inverters: s.inverters,
                                  invertersOnline: s.stop == nil ? s.online : nil, powerNow: power,
                                  energyToday: energy, expectedSoFar: s.expected, expectedToday: Forecast.energy(expectedCurve, through: Monitoring.slots - 1),
                                  totalEnergy: s.total, lastReading: last, backfeedToday: s.stop == nil ? 0 : nil,
                                  hasIrradianceSensor: s.sensor, prToday: s.sensor ? 81 : nil, alarms: s.alarms, curve: raw,
                                  expectedCurve: expectedCurve, yesterdaySoFar: s.yesterday, days: days, months: months)
            // the string currents the station page shows, read by the fleet's `สตริงกระแสต่ำ` too
            if s.stop == nil {
                var strings = demoDetail(station, now: clock, calendar: calendar).inverters.map(\.strings)
                if let low = s.lowString, !strings.isEmpty, low.mppt < strings[0].count, low.string < strings[0][low.mppt].count,
                   let v = strings[0][low.mppt][low.string] {
                    strings[0][low.mppt][low.string] = v * 0.31
                }
                station.inverterStrings = strings
            }
            return station
        }
    }

    /// The demo's `TCRoof` lines as first raised, for the fleet's `raised`: MP 12's low string since 11:30, as on the
    /// board, so it shows at once and not 30 minutes after the page opens.
    public static func demoRaised(_ stations: [Station], now: Date, settings: Settings = Settings(),
                                  calendar: Calendar = .current) -> [String: Raised] {
        let today = calendar.startOfDay(for: now)
        let since = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: today) ?? today
        let fleet = Fleet(stations, now: now, settings: settings, calendar: calendar)
        return fleet.raised.mapValues { r in
            var r = r
            guard r.active, !r.shown else { return r }
            r.since = since
            return r
        }
    }

    /// The board's clock: today at 14:55.
    public static func demoNow(calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: 14, minute: 55, second: 0, of: today) ?? today
    }
}

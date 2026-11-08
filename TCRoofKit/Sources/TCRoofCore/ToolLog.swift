import Foundation

/// `บันทึกการใช้เครื่องมือและรถ`: who borrowed which measuring tool and which company vehicle went out, for which job, and
/// what came back (the iPad tools tab, the board's `iPadToolsHub`). Every entry is an `Event`, kept for good and synced to
/// the team (`toolEvents`); what is out now, the activity and the month's figures are worked out from them.
public enum ToolLog {
    public enum Kind: String, Codable, Sendable { case tool, car }

    public enum Action: String, Codable, Sendable, CaseIterable {
        case borrow, giveBack, carOut, carIn, fuel, remind

        public var kind: Kind { self == .borrow || self == .giveBack ? .tool : self == .remind ? .tool : .car }
        public var title: String {
            switch self {
            case .borrow: "ยืม"
            case .giveBack: "คืน"
            case .carOut: "ออกรถ"
            case .carIn: "คืนรถ"
            case .fuel: "เติมน้ำมัน"
            case .remind: "ทวงคืน"
            }
        }
        /// Takes an item out (`borrow`, `carOut`) or brings it back.
        var opens: Bool { self == .borrow || self == .carOut }
        var closes: Bool { self == .giveBack || self == .carIn }
    }

    /// One entry of the log. `item` is the register tool's or the vehicle's id, `itemName` its name as shown then.
    public struct Event: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var action: Action
        public var item: String
        public var itemName: String
        public var person: String
        public var personEmail: String
        /// The job's code, empty when it was for none.
        public var job: String
        public var at: Date
        /// When a borrowed tool is due back.
        public var due: Date?
        /// The vehicle's odometer, km, at `carOut` / `carIn` / `fuel`.
        public var odometer: Int?
        /// The tank, 0…1, at `carIn`.
        public var fuelLevel: Double?
        public var litres: Double?
        public var baht: Double?
        /// The condition on return, or any note.
        public var note: String

        public init(id: String = UUID().uuidString, action: Action, item: String, itemName: String, person: String, personEmail: String,
                    job: String = "", at: Date = .now, due: Date? = nil, odometer: Int? = nil, fuelLevel: Double? = nil,
                    litres: Double? = nil, baht: Double? = nil, note: String = "") {
            self.id = id; self.action = action; self.item = item; self.itemName = itemName; self.person = person
            self.personEmail = personEmail; self.job = job; self.at = at; self.due = due; self.odometer = odometer
            self.fuelLevel = fuelLevel; self.litres = litres; self.baht = baht; self.note = note
        }

        enum CodingKeys: String, CodingKey { case id, action, item, itemName, person, personEmail, job, at, due, odometer, fuelLevel, litres, baht, note }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            // an action a later version adds reads as a note, which neither opens nor closes anything
            action = (try? c.decodeIfPresent(Action.self, forKey: .action)) ?? .remind
            item = try c.decodeIfPresent(String.self, forKey: .item) ?? ""
            itemName = try c.decodeIfPresent(String.self, forKey: .itemName) ?? ""
            person = try c.decodeIfPresent(String.self, forKey: .person) ?? ""
            personEmail = try c.decodeIfPresent(String.self, forKey: .personEmail) ?? ""
            job = try c.decodeIfPresent(String.self, forKey: .job) ?? ""
            at = try c.decodeIfPresent(Date.self, forKey: .at) ?? .distantPast
            due = try c.decodeIfPresent(Date.self, forKey: .due)
            odometer = try c.decodeIfPresent(Int.self, forKey: .odometer)
            fuelLevel = try c.decodeIfPresent(Double.self, forKey: .fuelLevel)
            litres = try c.decodeIfPresent(Double.self, forKey: .litres)
            baht = try c.decodeIfPresent(Double.self, forKey: .baht)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        }
    }

    /// A company vehicle (`vehicles`, synced to the team).
    public struct Vehicle: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var plate: String
        /// The odometer reading at which its next service is due.
        public var serviceAtKm: Int?

        public init(id: String = UUID().uuidString, name: String, plate: String, serviceAtKm: Int? = nil) {
            self.id = id; self.name = name; self.plate = plate; self.serviceAtKm = serviceAtKm
        }

        enum CodingKeys: String, CodingKey { case id, name, plate, serviceAtKm }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            plate = try c.decodeIfPresent(String.self, forKey: .plate) ?? ""
            serviceAtKm = try c.decodeIfPresent(Int.self, forKey: .serviceAtKm)
        }

        /// `Isuzu D-Max · 1กข 1234`
        public var title: String { plate.isEmpty ? name : name + " · " + plate }
    }

    /// An item out now: its `borrow` or `carOut`, not followed by a return.
    public struct Out: Identifiable, Equatable, Sendable {
        public let event: Event
        /// A borrowed tool past its due time.
        public let late: Bool
        public var id: String { event.item }
        public var kind: Kind { event.action.kind }
    }

    static var calendar: Calendar { MasterSchedule.calendar }

    /// Every item out at `now`, the late ones first, then the longest out.
    public static func outs(_ events: [Event], now: Date = .now) -> [Out] {
        var last: [String: Event] = [:]
        for e in events.sorted(by: { $0.at < $1.at }) where e.action.opens || e.action.closes { last[e.item] = e }
        return last.values.filter(\.action.opens)
            .map { Out(event: $0, late: $0.due.map { $0 < now } ?? false) }
            .sorted { ($0.late ? 0 : 1, $0.event.at) < ($1.late ? 0 : 1, $1.event.at) }
    }

    /// The item's open `borrow` / `carOut`, if it is out.
    public static func out(_ item: String, in events: [Event]) -> Event? {
        events.filter { $0.item == item && ($0.action.opens || $0.action.closes) }.max { $0.at < $1.at }.flatMap { $0.action.opens ? $0 : nil }
    }

    /// `4 วัน`, `2 ชม. 18 น.`, `25 น.`
    public static func duration(from start: Date, to end: Date = .now) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60)) วัน" }
        if minutes >= 60 { return "\(minutes / 60) ชม." + (minutes % 60 > 0 ? " \(minutes % 60) น." : "") }
        return "\(minutes) น."
    }

    /// The events of the last `days` days (today included), by day, newest first.
    public static func days(_ events: [Event], now: Date = .now, days: Int = 7) -> [(day: Date, events: [Event])] {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let recent = events.filter { $0.at >= from && $0.at <= now }.sorted { $0.at > $1.at }
        let grouped = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    /// Each `carIn` with the odometer of the `carOut` it closes (the vehicle's latest one before it), oldest first.
    /// A trip whose way out has no odometer, or that has no way out, is left out.
    static func trips(_ events: [Event]) -> [(carIn: Event, start: Int)] {
        var open: [String: Int] = [:], trips: [(carIn: Event, start: Int)] = []
        for e in events.sorted(by: { $0.at < $1.at }) {
            if e.action == .carOut { open[e.item] = e.odometer }
            if e.action == .carIn, let start = open.removeValue(forKey: e.item) { trips.append((e, start)) }
        }
        return trips
    }

    /// Km driven in `now`'s month: each `carIn` of the month less its `carOut`'s odometer.
    public static func monthKm(_ events: [Event], now: Date = .now) -> Int {
        trips(events).reduce(0) { km, t in
            guard let end = t.carIn.odometer, end > t.start, calendar.isDate(t.carIn.at, equalTo: now, toGranularity: .month) else { return km }
            return km + (end - t.start)
        }
    }

    /// `วิ่ง 212 กม.`: km of the trip `carIn` closes, from the odometer of its `carOut` in `events` (the pairing of
    /// `monthKm`); nil for another action, a trip with no way out or no readings, or one that read no km.
    public static func driven(_ carIn: Event, in events: [Event]) -> Int? {
        guard carIn.action == .carIn, let end = carIn.odometer,
              let trip = trips(events + (events.contains { $0.id == carIn.id } ? [] : [carIn])).first(where: { $0.carIn.id == carIn.id }),
              end > trip.start else { return nil }
        return end - trip.start
    }

    /// `driven` for every `carIn` of `events` at once, by event id: what a table or an export of many rows reads.
    public static func driven(in events: [Event]) -> [String: Int] {
        var km: [String: Int] = [:]
        for t in trips(events) { if let end = t.carIn.odometer, end > t.start { km[t.carIn.id] = end - t.start } }
        return km
    }

    /// Baht of fuel in `now`'s month.
    public static func monthFuel(_ events: [Event], now: Date = .now) -> Double {
        events.filter { $0.action == .fuel && calendar.isDate($0.at, equalTo: now, toGranularity: .month) }.compactMap(\.baht).reduce(0, +)
    }

    /// The vehicle's latest odometer and tank, from its events.
    public static func lastReading(_ vehicle: String, in events: [Event]) -> (odometer: Int?, fuel: Double?) {
        let mine = events.filter { $0.item == vehicle }.sorted { $0.at < $1.at }
        return (mine.compactMap(\.odometer).last, mine.compactMap(\.fuelLevel).last)
    }

    // MARK: the iPad ledger (docs/ui/tools-log-ipad)

    /// The ledger's range: today, the last 7 or 30 days (today included), or everything.
    public enum Period: String, CaseIterable, Sendable {
        case today, week, month, all

        /// `วันนี้`, `7 วัน`, `30 วัน`, `ทั้งหมด`
        public var title: String {
            switch self {
            case .today: "วันนี้"
            case .week: "7 วัน"
            case .month: "30 วัน"
            case .all: "ทั้งหมด"
            }
        }

        /// Days counted back from today, today included; nil for everything.
        public var days: Int? {
            switch self {
            case .today: 1
            case .week: 7
            case .month: 30
            case .all: nil
            }
        }
    }

    /// The ledger's log rows, newest first: of one kind (nil: both), within `range` of `now`'s day, of one action (nil:
    /// every action, `ทวงคืน` included, which no single action filter shows), by one person and / or for one job (nil:
    /// anyone, any job), whose item name, person or job contains `query` (ignoring case and accents; a vehicle's item
    /// name carries its plate). An event later than `now` (another device's clock ahead) is kept.
    public static func filter(_ events: [Event], kind: Kind? = nil, range: Period = .all, action: Action? = nil,
                              person: String? = nil, job: String? = nil, query: String = "", now: Date = .now) -> [Event] {
        let from: Date? = range.days.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: calendar.startOfDay(for: now)) }
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter { e in
            if let kind, e.action.kind != kind { return false }
            if let from, e.at < from { return false }
            if let action, e.action != action { return false }
            if let person, e.person != person { return false }
            if let job, e.job != job { return false }
            if !words.isEmpty, ![e.itemName, e.person, e.job].contains(where: { $0.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                return false
            }
            return true
        }
        .sorted { $0.at > $1.at }
    }

    /// Whole days a borrowed tool is past its due day at `now` (`เกิน 1 วัน` the day after), 0 when not late.
    public static func daysLate(_ e: Event, now: Date = .now) -> Int {
        guard let due = e.due, due < now else { return 0 }
        let days: Int = calendar.dateComponents([.day], from: calendar.startOfDay(for: due), to: calendar.startOfDay(for: now)).day ?? 0
        return max(days, 0)
    }

    /// The give-back condition `ToolLogFormSheet` writes for a damaged tool.
    public static let damagedNote = "ชำรุด / ต้องซ่อม"

    /// Tools whose latest borrow or give-back is a give-back marked `ชำรุด / ต้องซ่อม`: the ledger's `งดใช้ / ซ่อม`.
    public static func damaged(_ events: [Event]) -> [Event] {
        var last: [String: Event] = [:]
        for e in events.sorted(by: { $0.at < $1.at }) where e.action == .borrow || e.action == .giveBack { last[e.item] = e }
        return last.values.filter { $0.action == .giveBack && $0.note.hasPrefix(damagedNote) }.sorted { $0.at > $1.at }
    }

    /// Km left before a service at which the ledger warns (`ถึงรอบเช็กระยะ`, docs/ui/tools-log-ipad §7 question 4).
    public static let serviceWarningKm = 500

    /// Km left to the vehicle's next service from its latest odometer; nil without a service mark or a reading.
    public static func serviceLeft(_ vehicle: Vehicle, in events: [Event]) -> Int? {
        guard let at = vehicle.serviceAtKm, let odometer = lastReading(vehicle.id, in: events).odometer else { return nil }
        return at - odometer
    }

    /// `ส่งออก CSV`: the rows as a spreadsheet, UTF-8 with a BOM (so Excel reads the Thai), every field quoted, lines
    /// ended CRLF. Dates are `yyyy-MM-dd` and times `HH:mm` in Thai time; numbers carry no grouping. `วิ่ง (กม.)` pairs a
    /// `carIn` with its `carOut` in `log` (the whole log; the rows themselves when nil), so a filtered export keeps it.
    public static func csv(_ rows: [Event], log: [Event]? = nil) -> String {
        let km = driven(in: log ?? rows)
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func number(_ v: Double?) -> String {
            guard let v else { return "" }
            let r: Double = (v * 100).rounded() / 100
            return r == r.rounded() ? String(Int(r)) : String(r)
        }
        let header = ["วันที่", "เวลา", "ประเภท", "รายการ", "ผู้ใช้", "งาน", "ไมล์", "วิ่ง (กม.)", "ลิตร", "บาท", "หมายเหตุ"]
        let lines = rows.map { e -> String in
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: e.at)
            let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            let fields: [String] = [date, time, e.action.title, e.itemName, e.person, e.job, e.odometer.map(String.init) ?? "",
                                    km[e.id].map(String.init) ?? "", number(e.litres), number(e.baht), e.note]
            return fields.map(quoted).joined(separator: ",")
        }
        return "\u{FEFF}" + ([header.map(quoted).joined(separator: ",")] + lines).joined(separator: "\r\n") + "\r\n"
    }
}

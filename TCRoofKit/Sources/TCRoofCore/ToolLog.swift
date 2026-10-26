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

    /// Km driven in `now`'s month: each `carIn` of the month less its `carOut`'s odometer.
    public static func monthKm(_ events: [Event], now: Date = .now) -> Int {
        let sorted = events.sorted { $0.at < $1.at }
        var open: [String: Int] = [:], km = 0
        for e in sorted {
            if e.action == .carOut { open[e.item] = e.odometer }
            if e.action == .carIn, let start = open.removeValue(forKey: e.item), let end = e.odometer,
               end > start, calendar.isDate(e.at, equalTo: now, toGranularity: .month) { km += end - start }
        }
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
}

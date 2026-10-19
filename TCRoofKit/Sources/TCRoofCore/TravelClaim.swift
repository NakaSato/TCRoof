import Foundation

/// The travel and expense log (docs/specs/calendar-travel-expenses-swift.md part B): a day's trip with its station
/// stops, the expenses with their receipts, and the monthly claim made from them. Pure values and rules; the app keeps
/// them in SwiftData (`Trip`, `Expense`, `ClaimMonth`) and syncs them to their owner only.
///
/// Money is in satang (1 baht = 100), so totals and splits add up exactly.
public enum TravelClaim {
    public static var calendar: Calendar { MasterSchedule.calendar }

    // MARK: - Kinds

    public enum Vehicle: String, Codable, CaseIterable, Identifiable, Sendable {
        case company, personal, transit
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .company: "รถบริษัท"
            case .personal: "รถส่วนตัว"
            case .transit: "รถสาธารณะ"
            }
        }
        /// A private car is paid per km (`mileage`); the others claim their receipts only.
        public var paysMileage: Bool { self == .personal }
    }

    public enum Category: String, Codable, CaseIterable, Identifiable, Sendable {
        case fuel, toll, parking, lodging, perDiem, mileage, other
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .fuel: "น้ำมัน"
            case .toll: "ทางด่วน"
            case .parking: "ค่าจอดรถ"
            case .lodging: "ที่พัก"
            case .perDiem: "เบี้ยเลี้ยง"
            case .mileage: "ค่าเดินทางรถส่วนตัว"
            case .other: "อื่น ๆ"
            }
        }
        public var symbol: String {
            switch self {
            case .fuel: "fuelpump"
            case .toll: "road.lanes"
            case .parking: "parkingsign"
            case .lodging: "bed.double"
            case .perDiem: "fork.knife"
            case .mileage: "car"
            case .other: "doc.text"
            }
        }
        /// The categories a person picks for a receipt; mileage comes from the trips.
        public static var receipts: [Category] { allCases.filter { $0 != .mileage } }
    }

    // MARK: - Defaults (docs/specs/calendar-travel-expenses-swift.md §5, decided 2026-10-19)

    /// Baht per km for a private car; editable in the claim settings.
    public static let defaultRate = 5.0
    /// A second tap within this many seconds undoes the stamp (§B2).
    public static let undoWindow: TimeInterval = 120
    /// Odometer and route distance further apart than this need a reason (§B3).
    public static let odometerTolerance = 0.20

    // MARK: - Stops

    /// One station visit on a trip: when the person arrived and left, and where the arrival was stamped.
    public struct Stop: Codable, Hashable, Identifiable, Sendable {
        public var id: UUID
        /// The job's sync id; nil for a place that isn't a job (a supplier, the PWA office).
        public var jobID: String?
        /// The job's code and name when stamped, so the claim reads the same if the job is renamed or removed.
        public var label: String
        public var arrivedAt: Date?
        public var departedAt: Date?
        public var lat: Double?
        public var lon: Double?
        public var accuracy: Double?
        /// Road distance from the previous stop (or the start place) in km.
        public var legKm: Double?
        /// Typed by the person instead of the route (a closed road, a detour); `legNote` says why.
        public var legEdited: Bool
        public var legNote: String

        public init(id: UUID = UUID(), jobID: String?, label: String, arrivedAt: Date? = nil, departedAt: Date? = nil,
                    lat: Double? = nil, lon: Double? = nil, accuracy: Double? = nil, legKm: Double? = nil,
                    legEdited: Bool = false, legNote: String = "") {
            self.id = id; self.jobID = jobID; self.label = label; self.arrivedAt = arrivedAt; self.departedAt = departedAt
            self.lat = lat; self.lon = lon; self.accuracy = accuracy; self.legKm = legKm
            self.legEdited = legEdited; self.legNote = legNote
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            jobID = try c.decodeIfPresent(String.self, forKey: .jobID)
            label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
            arrivedAt = try c.decodeIfPresent(Date.self, forKey: .arrivedAt)
            departedAt = try c.decodeIfPresent(Date.self, forKey: .departedAt)
            lat = try c.decodeIfPresent(Double.self, forKey: .lat)
            lon = try c.decodeIfPresent(Double.self, forKey: .lon)
            accuracy = try c.decodeIfPresent(Double.self, forKey: .accuracy)
            legKm = try c.decodeIfPresent(Double.self, forKey: .legKm)
            legEdited = try c.decodeIfPresent(Bool.self, forKey: .legEdited) ?? false
            legNote = try c.decodeIfPresent(String.self, forKey: .legNote) ?? ""
        }

        /// Time on site, once both ends are stamped.
        public var onSite: TimeInterval? {
            guard let a = arrivedAt, let d = departedAt, d >= a else { return nil }
            return d.timeIntervalSince(a)
        }

        /// At the station now: arrived and not left.
        public var isOpen: Bool { arrivedAt != nil && departedAt == nil }
    }

    public enum StampKind: Sendable { case arrive, depart }

    /// What a tap on ถึงสถานีแล้ว / ออกจากสถานี did.
    public enum StampResult: Equatable, Sendable {
        case stamped(UUID)
        /// A second tap within `undoWindow`: the stamp was taken back.
        case undone(UUID)
        /// ออก with no arrival to close.
        case nothingToClose
    }

    public struct Location: Sendable, Equatable {
        public var lat, lon, accuracy: Double
        public init(lat: Double, lon: Double, accuracy: Double) { self.lat = lat; self.lon = lon; self.accuracy = accuracy }
    }

    /// Stamps an arrival or a departure at `job` (§B2). An arrival adds a stop (unless the person is still at this
    /// job), a departure closes the job's open stop. A second tap within two minutes undoes the first: ออก right after
    /// ถึง takes the arrival back, ออก again takes the departure back.
    public static func stamp(_ kind: StampKind, jobID: String?, label: String, at now: Date, location: Location?,
                             stops: inout [Stop]) -> StampResult {
        switch kind {
        case .arrive:
            if let i = stops.lastIndex(where: { $0.jobID == jobID }), let a = stops[i].arrivedAt {
                if stops[i].departedAt == nil, now.timeIntervalSince(a) < undoWindow {
                    let id = stops[i].id
                    stops.remove(at: i)
                    return .undone(id)
                }
                // still here from earlier: the first arrival stands
                if stops[i].departedAt == nil { return .stamped(stops[i].id) }
            }
            // arriving somewhere else closes the stop left open
            for i in stops.indices where stops[i].isOpen { stops[i].departedAt = now }
            let stop = Stop(jobID: jobID, label: label, arrivedAt: now, lat: location?.lat, lon: location?.lon,
                            accuracy: location?.accuracy)
            stops.append(stop)
            return .stamped(stop.id)
        case .depart:
            if let i = stops.lastIndex(where: { $0.jobID == jobID && $0.isOpen }) {
                // the screen turns ถึง into ออก: a second tap right after arriving is the mistaken arrival, not a visit
                if let a = stops[i].arrivedAt, now.timeIntervalSince(a) < undoWindow {
                    let id = stops[i].id
                    stops.remove(at: i)
                    return .undone(id)
                }
                stops[i].departedAt = now
                return .stamped(stops[i].id)
            }
            if let i = stops.lastIndex(where: { $0.jobID == jobID }), let d = stops[i].departedAt,
               now.timeIntervalSince(d) < undoWindow {
                stops[i].departedAt = nil
                return .undone(stops[i].id)
            }
            return .nothingToClose
        }
    }

    // MARK: - Distance

    /// The day's road distance: every leg plus the way back, rounded to 0.1 km; nil while a leg is unknown.
    public static func routeKm(legs: [Double?], back: Double?) -> Double? {
        var total = 0.0
        for leg in legs + [back] {
            guard let leg else { return nil }
            total += leg
        }
        return (total * 10).rounded() / 10
    }

    /// Mileage for a private car: km × rate, to the satang.
    public static func mileage(km: Double, rate: Double) -> Int {
        Int((km * rate * 100).rounded())
    }

    /// The odometer's distance and how far it is from the route's; true when they differ by more than 20 %.
    public static func odometerDiffers(start: Int?, end: Int?, routeKm: Double?) -> Bool {
        guard let start, let end, end > start, let routeKm, routeKm > 0 else { return false }
        return abs(Double(end - start) - routeKm) / routeKm > odometerTolerance
    }

    /// Splits `amount` across jobs by their leg distance (§B4 แบ่งตามระยะทาง). Rounding goes to the last job, so the
    /// parts add up to the amount. Jobs with no distance share equally when none has one.
    public static func split(_ amount: Int, by weights: [(jobID: String, km: Double)]) -> [(jobID: String, amount: Int)] {
        guard !weights.isEmpty else { return [] }
        let total = weights.reduce(0) { $0 + max($1.km, 0) }
        var out: [(String, Int)] = []
        var given = 0
        for (i, w) in weights.enumerated() {
            if i == weights.count - 1 {
                out.append((w.jobID, amount - given))
            } else {
                let share = total > 0 ? max(w.km, 0) / total : 1 / Double(weights.count)
                let part = Int((Double(amount) * share).rounded())
                out.append((w.jobID, part))
                given += part
            }
        }
        return out
    }

    // MARK: - Month

    /// "2026-10": the month a date is claimed in.
    public static func monthKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// The first day of a month key.
    public static func monthStart(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }

    /// "1,234.50".
    public static func baht(_ satang: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US_POSIX")
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: Double(satang) / 100)) ?? "0.00"
    }

    /// A trip as the claim reads it.
    public struct Day: Sendable, Identifiable {
        public var id: String
        public var date: Date
        public var vehicle: Vehicle
        public var plate: String
        public var startPlace: String
        public var stops: [Stop]
        public var backKm: Double?
        public var rate: Double
        public var odoStart: Int?
        public var odoEnd: Int?
        public var odoReason: String
        public var hasOdoPhotos: Bool

        public init(id: String, date: Date, vehicle: Vehicle, plate: String = "", startPlace: String = "", stops: [Stop],
                    backKm: Double? = nil, rate: Double = TravelClaim.defaultRate, odoStart: Int? = nil, odoEnd: Int? = nil,
                    odoReason: String = "", hasOdoPhotos: Bool = false) {
            self.id = id; self.date = date; self.vehicle = vehicle; self.plate = plate; self.startPlace = startPlace
            self.stops = stops; self.backKm = backKm; self.rate = rate; self.odoStart = odoStart; self.odoEnd = odoEnd
            self.odoReason = odoReason; self.hasOdoPhotos = hasOdoPhotos
        }

        public var km: Double? { TravelClaim.routeKm(legs: stops.map(\.legKm), back: backKm) }
        /// Mileage paid for the day, once its distance is known; 0 for a company car or public transport.
        public var mileage: Int? {
            guard vehicle.paysMileage else { return 0 }
            return km.map { TravelClaim.mileage(km: $0, rate: rate) }
        }
        public var odometerKm: Int? {
            guard let s = odoStart, let e = odoEnd, e > s else { return nil }
            return e - s
        }
        public var odometerDiffers: Bool { TravelClaim.odometerDiffers(start: odoStart, end: odoEnd, routeKm: km) }

        /// Each job's share of the day's mileage, by the legs that reach its stops; the way back goes to the last stop.
        public var mileageByJob: [(jobID: String, amount: Int)] {
            guard let mileage, mileage > 0 else { return [] }
            var weights: [(jobID: String, km: Double)] = []
            for (i, s) in stops.enumerated() {
                guard let id = s.jobID else { continue }
                let km = (s.legKm ?? 0) + (i == stops.count - 1 ? backKm ?? 0 : 0)
                if let j = weights.firstIndex(where: { $0.jobID == id }) { weights[j].km += km } else { weights.append((id, km)) }
            }
            return TravelClaim.split(mileage, by: weights)
        }
    }

    /// An expense as the claim reads it.
    public struct Item: Sendable, Identifiable, Equatable {
        public var id: String
        public var date: Date
        public var category: Category
        /// Satang; 0 while not typed in or read from the receipt.
        public var amount: Int
        public var vendor: String
        public var taxID: String
        public var note: String
        public var jobID: String?
        public var hasReceipt: Bool
        /// The amount was read from the receipt photo (`ReceiptParser`).
        public var fromReceipt: Bool

        public init(id: String, date: Date, category: Category, amount: Int, vendor: String = "", taxID: String = "",
                    note: String = "", jobID: String? = nil, hasReceipt: Bool = false, fromReceipt: Bool = false) {
            self.id = id; self.date = date; self.category = category; self.amount = amount; self.vendor = vendor
            self.taxID = taxID; self.note = note; self.jobID = jobID; self.hasReceipt = hasReceipt; self.fromReceipt = fromReceipt
        }
    }

    public enum Warning: Equatable, Sendable {
        /// An expense without an amount.
        case noAmount(itemID: String)
        /// The same amount, date and vendor as another expense.
        case duplicate(itemID: String)
        /// A private-car day whose distance isn't known yet.
        case noDistance(dayID: String)
        /// Odometer and route differ by more than 20 % with no reason given.
        case odometerReason(dayID: String)

        public var text: String {
            switch self {
            case .noAmount: "ใบเสร็จยังไม่มียอดเงิน"
            case .duplicate: "อาจซ้ำ: ยอด วันที่ และร้านเดียวกัน"
            case .noDistance: "ยังไม่มีระยะทาง จึงคิดค่าเดินทางไม่ได้"
            case .odometerReason: "เลขไมล์กับระยะทางต่างกันเกิน 20% ต้องใส่เหตุผล"
            }
        }
    }

    /// Items that look like the same receipt twice: same day, amount and vendor (ignoring case and spaces).
    public static func duplicates(_ items: [Item]) -> Set<String> {
        var seen: [String: String] = [:]
        var out = Set<String>()
        for item in items where item.amount > 0 {
            let day = calendar.startOfDay(for: item.date).timeIntervalSince1970
            let vendor = item.vendor.lowercased().filter { !$0.isWhitespace }
            let key = "\(day)|\(item.amount)|\(vendor)"
            if let first = seen[key] { out.insert(first); out.insert(item.id) } else { seen[key] = item.id }
        }
        return out
    }

    /// One month of one person's claim (§B5): the lines, the totals and what to check before submitting.
    public struct Summary: Sendable {
        public var days: [Day]
        public var items: [Item]

        public init(days: [Day], items: [Item]) {
            self.days = days.sorted { $0.date < $1.date }
            self.items = items.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        }

        public var km: Double { days.compactMap(\.km).reduce(0, +) }
        public var mileage: Int { days.compactMap(\.mileage).reduce(0, +) }

        /// Totals by category, mileage included, in the categories' order; categories with nothing are left out.
        public var byCategory: [(category: Category, amount: Int)] {
            Category.allCases.compactMap { c in
                let sum = c == .mileage ? mileage + items.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
                    : items.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
                return sum > 0 ? (c, sum) : nil
            }
        }

        public var total: Int { byCategory.reduce(0) { $0 + $1.amount } }

        /// Totals per job: its expenses and its share of the mileage. Expenses with no job are under nil.
        public var byJob: [(jobID: String?, amount: Int)] {
            var sums: [String?: Int] = [:]
            var order: [String?] = []
            func add(_ id: String?, _ amount: Int) {
                guard amount != 0 else { return }
                if sums[id] == nil { order.append(id) }
                sums[id, default: 0] += amount
            }
            for d in days { for part in d.mileageByJob { add(part.jobID, part.amount) } }
            for i in items { add(i.jobID, i.amount) }
            return order.map { ($0, sums[$0] ?? 0) }
        }

        public var warnings: [Warning] {
            var out: [Warning] = []
            for i in items where i.amount <= 0 { out.append(.noAmount(itemID: i.id)) }
            let dup = TravelClaim.duplicates(items)
            for i in items where dup.contains(i.id) { out.append(.duplicate(itemID: i.id)) }
            for d in days where d.vehicle.paysMileage && d.km == nil { out.append(.noDistance(dayID: d.id)) }
            for d in days where d.odometerDiffers && d.odoReason.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(.odometerReason(dayID: d.id))
            }
            return out
        }
    }

    /// One job's travel cost across the trips and expenses given (the job screen's `ค่าเดินทางงานนี้`).
    public static func jobCost(_ jobID: String, days: [Day], items: [Item]) -> (amount: Int, visits: Int) {
        let mileage = days.flatMap(\.mileageByJob).filter { $0.jobID == jobID }.reduce(0) { $0 + $1.amount }
        let spent = items.filter { $0.jobID == jobID }.reduce(0) { $0 + $1.amount }
        let visits = days.reduce(0) { $0 + $1.stops.filter { $0.jobID == jobID }.count }
        return (mileage + spent, visits)
    }

    /// The job a receipt taken at `time` belongs to: the stop the person was at then, if any (§B4).
    public static func jobAt(_ time: Date, stops: [Stop]) -> String? {
        stops.last { s in
            guard let a = s.arrivedAt, a <= time else { return false }
            return s.departedAt.map { time <= $0 } ?? true
        }?.jobID
    }
}

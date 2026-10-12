import Foundation

/// A measuring tool in the company's register (the iPhone `เครื่องมือ` tab): what it is and when its calibration runs out.
public struct Instrument: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// The company's asset code, e.g. TCR-MT-01.
    public var code: String
    /// What it measures, e.g. เครื่องวัดฉนวน.
    public var kind: String
    public var serial: String
    /// The day the calibration certificate runs out; nil for a tool that needs none.
    public var calibrationDue: Date?

    public init(id: String = UUID().uuidString, name: String, code: String = "", kind: String = "", serial: String = "",
                calibrationDue: Date? = nil) {
        self.id = id; self.name = name; self.code = code; self.kind = kind; self.serial = serial; self.calibrationDue = calibrationDue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        serial = try c.decodeIfPresent(String.self, forKey: .serial) ?? ""
        calibrationDue = try c.decodeIfPresent(Date.self, forKey: .calibrationDue)
    }
    private enum CodingKeys: String, CodingKey { case id, name, code, kind, serial, calibrationDue }

    public enum Calibration: Equatable, Sendable {
        /// Needs no calibration.
        case none
        case ok(daysLeft: Int)
        /// Inside the warning window, the day of the first reminder (`ToolNotification.scheduleCalibration`).
        case dueSoon(daysLeft: Int)
        case overdue(days: Int)

        /// Counted on the tab's badge.
        public var needsAction: Bool {
            switch self {
            case .dueSoon, .overdue: true
            case .none, .ok: false
            }
        }

        /// "เหลือ 76 วัน", "ครบวันนี้", "เกิน 10 วัน".
        public var title: String {
            switch self {
            case .none: "ไม่ต้องสอบเทียบ"
            case .ok(let d), .dueSoon(let d): d == 0 ? "ครบวันนี้" : "เหลือ \(d) วัน"
            case .overdue(let d): "เกิน \(d) วัน"
            }
        }
    }

    /// Days before the due date from which a tool counts as due.
    public static let warningDays = 30

    /// Whole days from `now` to the due date, in Thai time; negative once it has passed.
    public func daysLeft(on now: Date) -> Int? {
        guard let due = calibrationDue else { return nil }
        let cal = MasterSchedule.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day
    }

    public func calibration(on now: Date) -> Calibration {
        guard let d = daysLeft(on: now) else { return .none }
        if d < 0 { return .overdue(days: -d) }
        return d <= Self.warningDays ? .dueSoon(daysLeft: d) : .ok(daysLeft: d)
    }

    /// How many tools are due for calibration within 30 days or past it: the `เครื่องมือ` tab's badge.
    public static func dueCount(_ all: [Instrument], on now: Date) -> Int {
        all.filter { $0.calibration(on: now).needsAction }.count
    }

    /// Overdue first, then by days left, then tools that need no calibration, by name.
    public static func sorted(_ all: [Instrument], on now: Date) -> [Instrument] {
        all.sorted { a, b in
            switch (a.daysLeft(on: now), b.daysLeft(on: now)) {
            case let (x?, y?): x != y ? x < y : a.name < b.name
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.name < b.name
            }
        }
    }
}

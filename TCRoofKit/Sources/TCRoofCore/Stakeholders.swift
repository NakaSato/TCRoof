import Foundation

/// One row of the Master Plan's stakeholder list (`ผู้มีส่วนได้ส่วนเสีย`, CHA-82, PMBOK 5th §13.1 identify stakeholders
/// and §10.1 plan communications): an outside party who gets a report from the team, and when. The team's Google Sheet
/// copies the list into `config/stakeholders` on each pull (`tools/master-plan-sheet`, `Core.stakeholderList`); the app
/// reads it, read only, team only.
public struct Stakeholder: Codable, Equatable, Identifiable, Sendable {
    /// `S01`.
    public var id: String
    /// ชื่อ / ตำแหน่ง: `ผอ.กองแผนงาน`, `หัวหน้าสถานี`.
    public var name: String
    /// หน่วยงาน: `กปภ. เขต 5`, `กฟภ.`, `พพ.`.
    public var organisation: String
    /// บทบาทในโครงการ.
    public var role: String
    /// ความสนใจ and อิทธิพล: `สูง`, `กลาง`, `ต่ำ`.
    public var interest: String
    public var influence: String
    /// รายงานที่ได้รับ: `R3 รายงานประจำสัปดาห์`, `R4 รายงานประจำเดือน`, `เอกสารส่งมอบ`.
    public var reports: String
    /// ช่องทาง: `อีเมล`, `LINE`, `หนังสือ`.
    public var channel: String
    /// ความถี่ as typed: `รายสัปดาห์`, `รายเดือน`, `ก่อนส่งมอบ`, `ตามเหตุการณ์`; `cadence` is what it means.
    public var frequency: String
    /// กำหนดส่ง as typed: a weekday (`ศุกร์`), a day of the month (`25`, `สิ้นเดือน`) or days before the handover (`3`).
    public var due: String
    /// ผู้ส่ง (ฝั่งเรา).
    public var owner: String
    public var note: String
    /// ขอบเขต as typed; `jobs` is what the sheet made of it, as for the risk register.
    public var scope: String
    /// The app jobs (Firestore ids) of the stations it concerns; nil for every station.
    public var jobs: [String]?

    public init(id: String, name: String, organisation: String = "", role: String = "", interest: String = "",
                influence: String = "", reports: String = "", channel: String = "", frequency: String = "", due: String = "",
                owner: String = "", note: String = "", scope: String = "", jobs: [String]? = nil) {
        self.id = id; self.name = name; self.organisation = organisation; self.role = role; self.interest = interest
        self.influence = influence; self.reports = reports; self.channel = channel; self.frequency = frequency
        self.due = due; self.owner = owner; self.note = note; self.scope = scope; self.jobs = jobs
    }

    enum CodingKeys: String, CodingKey {
        case id, name, organisation, role, interest, influence, reports, channel, frequency, due, owner, note, scope, jobs
    }

    /// Every field but the id may be missing: a sheet edited by hand leaves cells blank.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        id = try c.decode(String.self, forKey: .id)
        name = s(.name); organisation = s(.organisation); role = s(.role); interest = s(.interest); influence = s(.influence)
        reports = s(.reports); channel = s(.channel); frequency = s(.frequency); due = s(.due); owner = s(.owner)
        note = s(.note); scope = s(.scope)
        jobs = (try? c.decodeIfPresent([String].self, forKey: .jobs)) ?? nil
    }

    /// When the reports go out.
    public enum Cadence: Equatable, Sendable {
        /// Each week on a `Calendar` weekday (1 = Sunday).
        case weekly(weekday: Int)
        /// Each month on a day; nil for the last day. A day past the month's end is its last day.
        case monthly(day: Int?)
        /// For each station it concerns, this many days before its handover (the MP plan's install end).
        case beforeHandover(days: Int)
        /// No fixed date (`ตามเหตุการณ์`): listed, never reminded.
        case asNeeded
    }

    /// `ความถี่` and `กำหนดส่ง` read together. A weekly row with no weekday goes out on Friday, a monthly one on the
    /// month's last day, a handover one on the handover day.
    public var cadence: Cadence {
        let f = frequency.trimmingCharacters(in: .whitespaces).lowercased()
        let d = due.trimmingCharacters(in: .whitespaces)
        if f.contains("สัปดาห์") || f.contains("week") { return .weekly(weekday: Self.weekday(d) ?? 6) }
        if f.contains("เดือน") || f.contains("month") {
            return .monthly(day: d.contains("สิ้น") ? nil : Self.number(d).map { min(max($0, 1), 31) })
        }
        if f.contains("ส่งมอบ") || f.contains("handover") { return .beforeHandover(days: max(Self.number(d) ?? 0, 0)) }
        return .asNeeded
    }

    /// Thai weekday names (`พฤหัส` or `พฤหัสบดี`, with or without `วัน`), and their short forms, to a `Calendar` weekday.
    static func weekday(_ text: String) -> Int? {
        let t = text.replacingOccurrences(of: "วัน", with: "").trimmingCharacters(in: .whitespaces)
        let names: [(String, Int)] = [("อาทิตย์", 1), ("จันทร์", 2), ("อังคาร", 3), ("พุธ", 4), ("พฤหัส", 5), ("ศุกร์", 6), ("เสาร์", 7),
                                      ("อา.", 1), ("จ.", 2), ("อ.", 3), ("พ.", 4), ("พฤ.", 5), ("ศ.", 6), ("ส.", 7)]
        // the long names first, so `พฤหัส` isn't read as `พ.`
        return names.first { t.hasPrefix($0.0) }?.1
    }

    static func number(_ text: String) -> Int? {
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    public func concerns(job id: String) -> Bool { jobs.map { $0.contains(id) } ?? true }

    /// `ผอ.กองแผนงาน (กปภ. เขต 5)`.
    public var label: String {
        let o = organisation.trimmingCharacters(in: .whitespaces)
        return o.isEmpty || name.contains(o) ? name : "\(name) (\(o))"
    }

    /// The report it gets, or `รายงาน` when the cell is blank.
    public var reportTitle: String {
        let r = reports.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? "รายงาน" : r
    }
}

/// `config/stakeholders`' list.
public struct StakeholderList: Codable, Equatable, Sendable {
    public var stakeholders: [Stakeholder]

    public init(stakeholders: [Stakeholder]) { self.stakeholders = stakeholders }

    /// `config/stakeholders`' `json` (`{ "stakeholders": [...] }`); nil when it doesn't read.
    public static func decode(_ json: String) -> StakeholderList? {
        guard let data = json.data(using: .utf8),
              let r = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        return StakeholderList(stakeholders: r.stakeholders.compactMap(\.value))
    }

    /// A row that doesn't read (no id) is skipped, not the whole list.
    private struct Wire: Decodable { var stakeholders: [Lenient] }
    private struct Lenient: Decodable {
        var value: Stakeholder?
        init(from decoder: Decoder) throws { value = try? Stakeholder(from: decoder) }
    }

    /// A station whose handover the `beforeHandover` rows count back from: one not handed over yet.
    public struct Station: Equatable, Sendable {
        /// The job's id (`Job.overviewID`), as the sheet writes in `jobs`.
        public var id: String
        /// `MP 154 แพรกหนามแดง`.
        public var label: String
        public var handover: Date

        public init(id: String, label: String, handover: Date) { self.id = id; self.label = label; self.handover = handover }
    }

    /// One report due to a stakeholder on a day.
    public struct Due: Identifiable, Equatable, Sendable {
        /// `comm-S01-2026-11-13`, with `-<job>` for a handover row.
        public var id: String
        public var date: Date
        public var stakeholder: Stakeholder
        /// The station a handover row is for; nil for the programme's reports.
        public var jobID: String?
        public var station: String

        /// `ส่ง R3 รายงานประจำสัปดาห์ ให้ ผอ.กองแผนงาน (กปภ. เขต 5)`.
        public var title: String { "ส่ง \(stakeholder.reportTitle) ให้ \(stakeholder.label)" }
    }

    /// The reports due from `from`'s day for `days` days, by date then the sheet's order. Weekly and monthly rows are
    /// the programme's; a handover row gives one per station it concerns whose handover minus its days falls in range.
    public func dues(stations: [Station], from: Date, days: Int = 14,
                     calendar cal: Calendar = MasterSchedule.calendar) -> [Due] {
        let start = cal.startOfDay(for: from)
        guard days > 0, let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        let range = start..<end
        let dayList = (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        var out: [(Due, Int)] = []
        for (order, s) in stakeholders.enumerated() {
            func add(_ d: Date, job: String? = nil, station: String = "") {
                let id = "comm-\(s.id)-\(ISODate.string(d))" + (job.map { "-\($0)" } ?? "")
                out.append((Due(id: id, date: d, stakeholder: s, jobID: job, station: station), order))
            }
            switch s.cadence {
            case .weekly(let weekday):
                for d in dayList where cal.component(.weekday, from: d) == weekday { add(d) }
            case .monthly(let day):
                for d in dayList {
                    let last = cal.range(of: .day, in: .month, for: d)?.count ?? 31
                    if cal.component(.day, from: d) == min(day ?? last, last) { add(d) }
                }
            case .beforeHandover(let before):
                for st in stations where s.concerns(job: st.id) {
                    guard let d = cal.date(byAdding: .day, value: -before, to: cal.startOfDay(for: st.handover)),
                          range.contains(d) else { continue }
                    add(d, job: st.id, station: st.label)
                }
            case .asNeeded:
                continue
            }
        }
        return out.sorted { $0.0.date != $1.0.date ? $0.0.date < $1.0.date : $0.1 < $1.1 }.map(\.0)
    }
}

// MARK: - Notifications

public enum StakeholderNotification {
    /// 08:00 the day before each report is due (`พรุ่งนี้ส่ง …`), while that is still ahead. A routine-report
    /// notification; a handover row's tap opens its station.
    public static func plans(_ dues: [StakeholderList.Due], now: Date,
                             calendar cal: Calendar = MasterSchedule.calendar) -> [NotificationPlan] {
        dues.compactMap { d in
            guard let eve = cal.date(byAdding: .day, value: -1, to: d.date),
                  let at = cal.date(bySettingHour: 8, minute: 0, second: 0, of: eve), at > now else { return nil }
            let s = d.stakeholder
            let sub = [s.channel.isEmpty ? "" : "ทาง \(s.channel)", s.owner.isEmpty ? "" : "ผู้ส่ง \(s.owner)"]
                .filter { !$0.isEmpty }.joined(separator: " | ")
            var info: [String: String] = [:]
            if let job = d.jobID { info[NotificationInfo.job] = job }
            return NotificationPlan(id: d.id, type: .report, title: "พรุ่งนี้" + d.title,
                                    body: d.station.isEmpty ? s.organisation : d.station, sub: sub, fire: .at(at), info: info)
        }
    }
}

// MARK: - The plan page's deadlines

public extension PWAPlan {
    /// The reports due to stakeholders as `กำหนดส่ง` rows (kind `report`): `วันนี้` today, else the cadence's word.
    static func stakeholderDeadlines(_ dues: [StakeholderList.Due], today: Date, calendar cal: Calendar = calendar) -> [Deadline] {
        let today = cal.startOfDay(for: today)
        return dues.map { d in
            let s = d.stakeholder
            let isToday = cal.isDate(d.date, inSameDayAs: today)
            let word = switch s.cadence {
            case .weekly: "รายสัปดาห์"
            case .monthly: "รายเดือน"
            case .beforeHandover: "ก่อนส่งมอบ"
            case .asNeeded: ""
            }
            let subtitle = [d.station, s.channel, s.owner.isEmpty ? "" : "ผู้ส่ง \(s.owner)"].filter { !$0.isEmpty }
                .joined(separator: " | ")
            return Deadline(id: d.id, date: cal.startOfDay(for: d.date), kind: .report, title: d.title,
                            subtitle: subtitle.isEmpty ? s.organisation : subtitle,
                            chip: isToday ? "วันนี้" : word, tone: isToday ? .risk : .ok, station: d.jobID ?? "", opens: .station)
        }
    }

    /// Two sorted deadline lists as one, by date; on the same day `a`'s rows first.
    static func merged(_ a: [Deadline], _ b: [Deadline]) -> [Deadline] {
        struct Row { let deadline: Deadline; let rank: Int }
        let rows: [Row] = a.enumerated().map { Row(deadline: $0.element, rank: $0.offset) }
            + b.enumerated().map { Row(deadline: $0.element, rank: a.count + $0.offset) }
        return rows.sorted { l, r in
            if l.deadline.date != r.deadline.date { return l.deadline.date < r.deadline.date }
            return l.rank < r.rank
        }
        .map(\.deadline)
    }
}

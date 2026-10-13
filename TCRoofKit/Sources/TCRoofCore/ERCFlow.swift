import Foundation

/// The ERC's แจ้งยกเว้นฯ flow for a system of 200 to under 1,000 kVA on a utility's network, per station: twelve
/// numbered steps between the operator, the utility, the ERC office and DEDE (`docs/specs/erc-exemption-flow-swift.md`,
/// from the diagrams in `docs/permit/`). The station keeps what happened (`Record`); where it stands, whose turn it
/// is and when a time limit ends are worked out from that.
public enum ERCFlow {

    public enum Party: String, Sendable, CaseIterable {
        case us, utility, erc, dede

        public var title: String {
            switch self {
            case .us: "ทีมเรา"
            case .utility: "การไฟฟ้า"
            case .erc: "สำนักงาน กกพ."
            case .dede: "พพ."
            }
        }
    }

    public enum Section: Int, Sendable, CaseIterable {
        case design, install, permit, connect

        public var title: String {
            switch self {
            case .design: "ออกแบบและขอความเห็นแบบ"
            case .install: "ติดตั้ง"
            case .permit: "พค.2 และตรวจระบบ (ทำคู่ขนานกันได้)"
            case .connect: "ขนานไฟและผลแจ้งยกเว้น"
            }
        }
    }

    /// Raw values are kept in the job's JSON: never rename them.
    public enum Step: String, Codable, CaseIterable, Sendable, Identifiable {
        case designRequest, designResult, install, pk2Request, ercToDede, dedeOpinion, pk2Signed,
             inspectionRequest, inspectionResult, utilityToERC, pk2ToUtility, cod, exemptionResult

        public var id: String { rawValue }

        /// The diagram's number; installation has none.
        public var number: Int? {
            switch self {
            case .designRequest: 1
            case .designResult: 2
            case .install: nil
            case .pk2Request: 3
            case .ercToDede: 4
            case .dedeOpinion: 5
            case .pk2Signed: 6
            case .inspectionRequest: 7
            case .inspectionResult: 8
            case .utilityToERC: 9
            case .pk2ToUtility: 10
            case .cod: 11
            case .exemptionResult: 12
            }
        }

        public var title: String {
            switch self {
            case .designRequest: "ยื่นคำขอตรวจสอบแบบและระบบไฟฟ้า"
            case .designResult: "ผลพิจารณาแบบและระบบไฟฟ้า"
            case .install: "ติดตั้งเครื่องจักร อุปกรณ์ สายไฟฟ้า"
            case .pk2Request: "ยื่นคำขอ พค.2"
            case .ercToDede: "กกพ. ตรวจเอกสาร ขอความเห็น พพ."
            case .dedeOpinion: "พพ. ให้ความเห็นต่อสำนักงาน กกพ."
            case .pk2Signed: "ได้รับ พค.2 ที่ลงนามแล้ว"
            case .inspectionRequest: "แจ้งขอตรวจระบบไฟฟ้า"
            case .inspectionResult: "ผลตรวจระบบ / อุปกรณ์การเชื่อมต่อ"
            case .utilityToERC: "การไฟฟ้าส่งข้อมูล / หนังสือพิจารณาการเชื่อมต่อให้ กกพ."
            case .pk2ToUtility: "ยื่น พค.2 ประกอบการขนานไฟ"
            case .cod: "ขนานไฟ / COD"
            case .exemptionResult: "กกพ. แจ้งผลการแจ้งยกเว้นฯ"
            }
        }

        /// Who does the step.
        public var party: Party {
            switch self {
            case .designRequest, .install, .pk2Request, .inspectionRequest, .pk2ToUtility: .us
            case .designResult, .inspectionResult, .utilityToERC, .cod: .utility
            case .ercToDede, .pk2Signed, .exemptionResult: .erc
            case .dedeOpinion: .dede
            }
        }

        public var section: Section {
            switch self {
            case .designRequest, .designResult: .design
            case .install: .install
            case .pk2Request, .ercToDede, .dedeOpinion, .pk2Signed, .inspectionRequest, .inspectionResult, .utilityToERC: .permit
            case .pk2ToUtility, .cod, .exemptionResult: .connect
            }
        }

        /// The utility's answer can be "not passed", which sends the request round again.
        public var hasResult: Bool { self == .designResult || self == .inspectionResult }

        /// The answering party's time limit, counted from the step that asked.
        public var limit: Limit? {
            switch self {
            case .designResult: Limit(days: 15, working: true)
            case .dedeOpinion: Limit(days: 30, working: false)
            case .inspectionResult: Limit(days: 30, working: true)
            default: nil
            }
        }
    }

    public struct Limit: Equatable, Sendable {
        public let days: Int
        /// Working days (Monday–Friday less the holidays) instead of calendar days.
        public let working: Bool
    }

    public enum Result: String, Codable, Sendable {
        case passed, failed
    }

    /// One thing that happened. A failed round stays in the list; the next request is another event.
    public struct Event: Codable, Equatable, Sendable {
        public var step: Step
        /// `yyyy-MM-dd` (Bangkok).
        public var day: String
        public var result: Result?
        public var note: String

        public init(step: Step, day: String, result: Result? = nil, note: String = "") {
            self.step = step; self.day = day; self.result = result; self.note = note
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            step = try c.decode(Step.self, forKey: .step)
            day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
            result = try? c.decodeIfPresent(Result.self, forKey: .result)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        }
    }

    public struct Record: Codable, Equatable, Sendable {
        /// In the order they were recorded.
        public var events: [Event]
        /// Whether the utility wants พค.2 before it connects (step 10); nil = not known yet.
        public var utilityWantsPK2: Bool?

        public init(events: [Event] = [], utilityWantsPK2: Bool? = nil) {
            self.events = events; self.utilityWantsPK2 = utilityWantsPK2
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // an event of a step this build doesn't know is dropped, not the whole record
            events = (try? c.decodeIfPresent([Lossy].self, forKey: .events))?.compactMap(\.event) ?? []
            utilityWantsPK2 = try? c.decodeIfPresent(Bool.self, forKey: .utilityWantsPK2)
        }

        private struct Lossy: Decodable {
            let event: Event?
            init(from decoder: Decoder) throws { event = try? Event(from: decoder) }
        }

        public mutating func add(_ step: Step, day: String, result: Result? = nil, note: String = "") {
            events.append(Event(step: step, day: day, result: step.hasResult ? (result ?? .passed) : nil, note: note))
        }

        /// How many times the utility answered "not passed" at this step.
        public func failedRounds(_ step: Step) -> Int {
            events.filter { $0.step == step && $0.result == .failed }.count
        }
    }

    /// What the flow reads from outside the record.
    public struct Context: Equatable, Sendable {
        /// The day installation finished in the MP plan, when it has; the team can also record it here.
        public var installDone: String?
        /// `yyyy-MM-dd` days that don't count as working days.
        public var holidays: Set<String>

        public init(installDone: String? = nil, holidays: Set<String> = []) {
            self.installDone = installDone; self.holidays = holidays
        }
    }

    public enum State: Equatable, Sendable {
        case done(day: String)
        /// Ours to do now.
        case open
        /// The step's party has it; `due` is the last day of its time limit.
        case waiting(since: String, due: String?)
        /// An earlier step isn't done.
        case blocked
        /// Doesn't apply, or was passed over (the team never learned the day).
        case notNeeded

        public var isDone: Bool { if case .done = self { true } else { false } }
    }

    // MARK: States

    public static func states(_ r: Record, _ ctx: Context = Context()) -> [Step: State] {
        var s: [Step: State] = [:]
        func last(_ step: Step) -> (index: Int, event: Event)? {
            r.events.indices.last { r.events[$0].step == step }.map { ($0, r.events[$0]) }
        }
        func done(_ step: Step) -> Bool { s[step]?.isDone ?? false }
        func day(_ step: Step) -> String { if case .done(let d) = s[step] { d } else { "" } }
        /// A step of another party, known only by its day.
        func theirs(_ step: Step, after asked: Step, skippedBy later: Step? = nil) {
            if let e = last(step)?.event { s[step] = .done(day: e.day) }
            else if let later, last(later) != nil { s[step] = .notNeeded }
            else if done(asked) { s[step] = .waiting(since: day(asked), due: due(step, from: day(asked), ctx)) }
            else { s[step] = .blocked }
        }
        /// A request of ours and the utility's answer, which may send it round again.
        func pair(_ request: Step, _ result: Step, ready: Bool) {
            let rq = last(request), rs = last(result)
            if let rq, rs == nil || rs!.index < rq.index {
                s[request] = .done(day: rq.event.day)
                s[result] = .waiting(since: rq.event.day, due: due(result, from: rq.event.day, ctx))
            } else if let rs, rs.event.result != .failed {
                s[request] = .done(day: rq?.event.day ?? rs.event.day)
                s[result] = .done(day: rs.event.day)
            } else {
                s[request] = ready ? .open : .blocked
                s[result] = .blocked
            }
        }

        pair(.designRequest, .designResult, ready: true)
        if let d = last(.install)?.event.day ?? ctx.installDone { s[.install] = .done(day: d) }
        else { s[.install] = done(.designResult) ? .open : .blocked }

        if let e = last(.pk2Request)?.event { s[.pk2Request] = .done(day: e.day) }
        else { s[.pk2Request] = done(.install) ? .open : .blocked }
        theirs(.ercToDede, after: .pk2Request, skippedBy: .pk2Signed)
        theirs(.dedeOpinion, after: .ercToDede, skippedBy: .pk2Signed)
        theirs(.pk2Signed, after: .pk2Request)

        pair(.inspectionRequest, .inspectionResult, ready: done(.install))
        theirs(.utilityToERC, after: .inspectionResult, skippedBy: .exemptionResult)

        if r.utilityWantsPK2 == false { s[.pk2ToUtility] = .notNeeded }
        else if let e = last(.pk2ToUtility)?.event { s[.pk2ToUtility] = .done(day: e.day) }
        else { s[.pk2ToUtility] = done(.pk2Signed) && done(.inspectionResult) ? .open : .blocked }

        if let e = last(.cod)?.event { s[.cod] = .done(day: e.day) }
        else if done(.inspectionResult), r.utilityWantsPK2 != true || done(.pk2ToUtility) {
            s[.cod] = .waiting(since: max(day(.inspectionResult), day(.pk2ToUtility)), due: nil)
        } else { s[.cod] = .blocked }

        if let e = last(.exemptionResult)?.event { s[.exemptionResult] = .done(day: e.day) }
        else if done(.inspectionResult) || done(.pk2Signed) {
            s[.exemptionResult] = .waiting(since: max(day(.inspectionResult), day(.pk2Signed)), due: nil)
        } else { s[.exemptionResult] = .blocked }
        return s
    }

    /// The steps in play now: ours to do, or with another party. Empty once the exemption result is in.
    public static func current(_ r: Record, _ ctx: Context = Context()) -> [Step] {
        let s = states(r, ctx)
        if s[.exemptionResult]?.isDone == true, s[.cod]?.isDone == true { return [] }
        return Step.allCases.filter {
            switch s[$0] {
            case .open, .waiting: true
            default: false
            }
        }
    }

    /// The utility can connect: its inspection passed, and it has พค.2 where it asked for it.
    public static func canConnect(_ r: Record, _ ctx: Context = Context()) -> Bool {
        let s = states(r, ctx)
        switch s[.cod] {
        case .done, .waiting: return true
        default: return false
        }
    }

    public enum Basis: Equatable, Sendable {
        case pk2, utilityLetter
    }

    /// What the ERC has for the exemption result: พค.2 or the utility's letter, either one.
    public static func exemptionBasis(_ r: Record) -> Basis? {
        if r.events.contains(where: { $0.step == .pk2Signed }) { return .pk2 }
        if r.events.contains(where: { $0.step == .utilityToERC }) { return .utilityLetter }
        return nil
    }

    // MARK: Waits

    /// A step that another party has, with a time limit running.
    public struct Wait: Equatable, Sendable {
        public var step: Step
        public var since: String
        public var due: String
        /// Days left as the step counts them; negative once the limit has passed.
        public var left: Int

        public var unit: String { step.limit?.working == true ? "วันทำการ" : "วัน" }
        /// `เหลือ 3 วันทำการ`, `ครบกำหนดวันนี้`, `เกินกำหนด 2 วัน`.
        public var text: String {
            left > 0 ? "เหลือ \(left) \(unit)" : left == 0 ? "ครบกำหนดวันนี้" : "เกินกำหนด \(-left) \(unit)"
        }
        /// `รอผลพิจารณาแบบและระบบไฟฟ้า`.
        public var title: String { step.party == .dede ? "รอความเห็น พพ. (พค.2)" : "รอ" + step.title }
    }

    /// The waiting steps that have a time limit, in the flow's order.
    public static func waits(_ r: Record, _ ctx: Context = Context(), today: Date = .now) -> [Wait] {
        let s = states(r, ctx)
        return Step.allCases.compactMap { step in
            guard case .waiting(let since, let due?) = s[step], let left = daysLeft(step, due: due, on: today, ctx) else { return nil }
            return Wait(step: step, since: since, due: due, left: left)
        }
    }

    /// One line for the job's card: what is ours to do, else who has it.
    public static func headline(_ r: Record, _ ctx: Context = Context()) -> String {
        let s = states(r, ctx), now = current(r, ctx)
        func name(_ step: Step) -> String { step.number.map { "ข้อ \($0) \(step.title)" } ?? step.title }
        if now.isEmpty { return "ครบทุกขั้นแล้ว" }
        if let ours = now.first(where: { s[$0] == .open }) { return "ถึงคิวทีมเรา: " + name(ours) }
        return now.first.map { "รอ\($0.party.title): " + name($0) } ?? ""
    }

    // MARK: Days

    public static func day(_ date: Date) -> String {
        let c = MasterSchedule.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(_ day: String) -> Date? {
        let n = day.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3 else { return nil }
        return MasterSchedule.calendar.date(from: DateComponents(year: n[0], month: n[1], day: n[2]))
    }

    static func isWorking(_ date: Date, _ ctx: Context) -> Bool {
        let weekday = MasterSchedule.calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7 && !ctx.holidays.contains(day(date))
    }

    /// The last day of a step's time limit, counted from the day after `asked`.
    public static func due(_ step: Step, from asked: String, _ ctx: Context = Context()) -> String? {
        guard let limit = step.limit, var d = date(asked) else { return nil }
        let cal = MasterSchedule.calendar
        var left = limit.days
        // bounded: a year of holidays can't loop for ever
        var guardDays = 0
        while left > 0, guardDays < 2000 {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { return nil }
            d = next
            guardDays += 1
            if !limit.working || isWorking(d, ctx) { left -= 1 }
        }
        return day(d)
    }

    /// The day `n` days before `day`, counted in working days where the step's limit is.
    public static func day(_ day: String, before n: Int, working: Bool, _ ctx: Context = Context()) -> String? {
        guard var d = date(day) else { return nil }
        var left = n, guardDays = 0
        while left > 0, guardDays < 2000 {
            guard let prev = MasterSchedule.calendar.date(byAdding: .day, value: -1, to: d) else { return nil }
            d = prev
            guardDays += 1
            if !working || isWorking(d, ctx) { left -= 1 }
        }
        return self.day(d)
    }

    /// Days left until `due` as the step counts them (working or calendar); negative once it has passed.
    public static func daysLeft(_ step: Step, due: String, on today: Date = .now, _ ctx: Context = Context()) -> Int? {
        guard let end = date(due), let start = date(day(today)) else { return nil }
        let cal = MasterSchedule.calendar
        if step.limit?.working != true { return cal.dateComponents([.day], from: start, to: end).day }
        let (a, b, sign) = start <= end ? (start, end, 1) : (end, start, -1)
        var n = 0, d = a
        while d < b, let next = cal.date(byAdding: .day, value: 1, to: d) {
            d = next
            if isWorking(d, ctx) { n += 1 }
        }
        return n * sign
    }
}

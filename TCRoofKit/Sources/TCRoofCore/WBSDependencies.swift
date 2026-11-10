import Foundation

public extension MasterSchedule {
    /// A precedence link (PMBOK §6.3.2.1): this row after `predecessor`, `lagDays` working days apart. Finish-to-start
    /// by default, as every plan before REV 11 had; the workbook's install tasks also use start-to-start and
    /// finish-to-finish (`2.1 SS+3, 2.1 FF+2`).
    struct WBSDependency: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            /// Starts after the predecessor finishes: lag 0 starts the next working day.
            case finishToStart = "FS"
            /// Starts `lagDays` working days after the predecessor starts: lag 0 starts the same day.
            case startToStart = "SS"
            /// Finishes no earlier than `lagDays` working days after the predecessor finishes: lag 0 the same day.
            case finishToFinish = "FF"
        }

        public var predecessor: String
        /// Whole working days, counted as `type` says.
        public var lagDays: Int
        public var type: Kind

        public init(predecessor: String, lagDays: Int = 0, type: Kind = .finishToStart) {
            self.predecessor = predecessor
            self.lagDays = lagDays
            self.type = type
        }

        /// `2.1.1 +2 วัน` for finish-to-start (as before REV 11), `2.1 SS+3` / `2.1 FF+2` as the workbook writes them.
        public var label: String {
            switch type {
            case .finishToStart: return predecessor + (lagDays == 0 ? "" : " +\(lagDays) วัน")
            case .startToStart, .finishToFinish: return predecessor + " " + type.rawValue + "+\(lagDays)"
            }
        }

        private enum CodingKeys: String, CodingKey { case predecessor, lagDays, type }

        // Plans saved before REV 11 have no `type`: they are finish-to-start, and a finish-to-start link is written
        // without one, so those plans' JSON (sync, the plan file's snapshot) stays the same.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            predecessor = try c.decode(String.self, forKey: .predecessor)
            lagDays = try c.decode(Int.self, forKey: .lagDays)
            type = (try? c.decodeIfPresent(Kind.self, forKey: .type)) ?? .finishToStart
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(predecessor, forKey: .predecessor)
            try c.encode(lagDays, forKey: .lagDays)
            if type != .finishToStart { try c.encode(type, forKey: .type) }
        }
    }
}

/// Opt-in WBS forecasting. Existing dates are release constraints; only explicitly linked rows move later.
/// A link joins two sub-tasks or two task lines (`2.3` after `2.1`, as the workbook links them); a linked task line's
/// sub-tasks follow it, keeping their place in its span, and can't be linked themselves. Parts (`2`) and rows marked
/// irrelevant cannot be endpoints. Nonworking dates are supplied by the plan.
public enum WBSDependencies {
    public enum Issue: Equatable, Sendable {
        case duplicateCode(String)
        case missingPredecessor(task: String, predecessor: String)
        case invalidEndpoint(String)
        case invalidDates(String)
        case negativeLag(task: String, predecessor: String)
        case duplicateLink(task: String, predecessor: String)
        /// A sub-task linked while its task line is linked too.
        case linkedInsideTask(task: String, sub: String)
        case invalidLag(task: String, predecessor: String)
        case noWorkingDays
        case cycle([String])

        public var message: String {
            switch self {
            case .duplicateCode(let code): return "รหัส WBS ซ้ำ: \(code)"
            case .missingPredecessor(let task, let predecessor): return "\(task): ไม่พบงานก่อนหน้า \(predecessor)"
            case .invalidEndpoint(let code): return "\(code): เลือกงานย่อยที่เกี่ยวข้องกับสถานีนี้"
            case .invalidDates(let code): return "\(code): ตรวจสอบวันที่และระยะเวลาของงาน"
            case .negativeLag(let task, let predecessor): return "\(task): วันรอหลัง \(predecessor) ต้องไม่ติดลบ"
            case .duplicateLink(let task, let predecessor): return "\(task): งานก่อนหน้า \(predecessor) ซ้ำ"
            case .linkedInsideTask(let task, let sub): return "\(sub): งาน \(task) ผูกไว้ทั้งงานแล้ว ผูกงานย่อยแยกไม่ได้"
            case .invalidLag(let task, let predecessor): return "\(task): วันรอหลัง \(predecessor) ต้องไม่เกิน 3,650 วันทำงาน"
            case .noWorkingDays: return "กำหนดวันทำงานของโครงการอย่างน้อยหนึ่งวันต่อสัปดาห์"
            case .cycle(let codes): return "งานก่อนหน้าวนกลับ: " + codes.joined(separator: " → ")
            }
        }
    }

    public struct Forecast: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let float: Int
        public var critical: Bool { float == 0 }
    }

    public struct Result: Equatable, Sendable {
        public let forecasts: [String: Forecast]
        public let issues: [Issue]
        public var isValid: Bool { issues.isEmpty }
    }

    public static func schedule(_ items: [MasterSchedule.WorkItem], nonWorking: Set<Date> = [],
                                settings: RoutineReport.Settings? = nil,
                                calendar cal: Calendar = MasterSchedule.calendar) -> Result {
        guard items.contains(where: { !($0.dependencies ?? []).isEmpty }) else { return Result(forecasts: [:], issues: []) }
        var issues: [Issue] = []
        if let settings, settings.workingWeekdays.intersection(Set(1...7)).isEmpty { issues.append(.noWorkingDays) }
        var byCode: [String: MasterSchedule.WorkItem] = [:]
        for item in items {
            if byCode[item.code] != nil { issues.append(.duplicateCode(item.code)) }
            byCode[item.code] = item
        }
        let parents = items.parentCodes
        func eligible(_ item: MasterSchedule.WorkItem) -> Bool {
            !item.notForThisStation && (!parents.contains(item.code) || isTaskLine(item.code))
        }
        var linked: Set<String> = []
        for item in items where !(item.dependencies ?? []).isEmpty {
            linked.insert(item.code)
            if !eligible(item) { issues.append(.invalidEndpoint(item.code)) }
            var seen: Set<String> = []
            for link in item.dependencies ?? [] {
                linked.insert(link.predecessor)
                if !seen.insert(link.predecessor + " " + link.type.rawValue).inserted { issues.append(.duplicateLink(task: item.code, predecessor: link.predecessor)) }
                if link.lagDays < 0 { issues.append(.negativeLag(task: item.code, predecessor: link.predecessor)) }
                if link.lagDays > 3650 { issues.append(.invalidLag(task: item.code, predecessor: link.predecessor)) }
                guard let predecessor = byCode[link.predecessor] else {
                    issues.append(.missingPredecessor(task: item.code, predecessor: link.predecessor)); continue
                }
                if !eligible(predecessor) { issues.append(.invalidEndpoint(predecessor.code)) }
            }
        }
        let nodes = items.filter { eligible($0) && $0.baselineStart != nil && $0.baselineEnd != nil }
        let nodeCodes = Set(nodes.map(\.code))
        for code in linked.sorted() where byCode[code] != nil && !nodeCodes.contains(code) && eligible(byCode[code]!) {
            issues.append(.invalidDates(code))
        }
        for item in nodes {
            let a = item.baselineStart!, b = item.baselineEnd!
            if !a.timeIntervalSince1970.isFinite || !b.timeIntervalSince1970.isFinite
                || a < .distantPast || b > .distantFuture || b < a || !(0...3650).contains(item.days ?? 0)
                || (cal.dateComponents([.day], from: a, to: b).day ?? Int.max) > 36500 {
                issues.append(.invalidDates(item.code))
            }
        }
        let linkedLines = linked.filter { isTaskLine($0) && parents.contains($0) }
        for code in linked.sorted() {
            if let line = linkedLines.first(where: { code.hasPrefix($0 + ".") }) { issues.append(.linkedInsideTask(task: line, sub: code)) }
        }
        guard issues.isEmpty else { return Result(forecasts: [:], issues: issues) }

        // DFS reports the actual cycle, rather than incorrectly labelling its blocked successors as cyclic.
        var visited: Set<String> = [], visiting: Set<String> = []
        var stack: [String] = [], order: [String] = []
        func visit(_ code: String) {
            guard issues.isEmpty, !visited.contains(code) else { return }
            if visiting.contains(code) {
                let first = stack.firstIndex(of: code) ?? 0
                issues.append(.cycle(Array(stack[first...]) + [code])); return
            }
            visiting.insert(code); stack.append(code)
            for link in byCode[code]?.dependencies ?? [] { visit(link.predecessor) }
            stack.removeLast(); visiting.remove(code); visited.insert(code); order.append(code)
        }
        for code in nodeCodes.sorted() { visit(code) }
        guard issues.isEmpty else { return Result(forecasts: [:], issues: issues) }

        let off = Set(nonWorking.map { cal.startOfDay(for: $0) })
        let holidays = settings.map { Set($0.holidays).union(PublicHolidays.days) } ?? []
        var offCache: [Date: Bool] = [:]
        func isOff(_ day: Date) -> Bool {
            if let cached = offCache[day] { return cached }
            if off.contains(day) { return true }
            guard let settings else { return false }
            let key = RoutineReport.dayKey(day)
            let value = !settings.workingWeekdays.contains(cal.component(.weekday, from: day)) || holidays.contains(key)
            offCache[day] = value
            return value
        }
        var moveCache: [Date: [Int: Date]] = [:]
        func move(_ date: Date, _ days: Int) -> Date {
            if let cached = moveCache[date]?[days] { return cached }
            var d = date, left = abs(days)
            while left > 0 {
                d = cal.date(byAdding: .day, value: days < 0 ? -1 : 1, to: d)!
                if !isOff(d) { left -= 1 }
            }
            moveCache[date, default: [:]][days] = d
            return d
        }
        func workingStart(_ date: Date) -> Date {
            var d = date
            while isOff(d) { d = cal.date(byAdding: .day, value: 1, to: d)! }
            return d
        }
        // A prefix count avoids walking the same calendar span for every one of the workbook's 130 rows.
        let first = nodes.compactMap(\.baselineStart).map { cal.startOfDay(for: $0) }.min()!
        var indexedDay = cal.date(byAdding: .day, value: -1, to: first)!
        var counts: [Date: Int] = [indexedDay: 0]
        var workingCount = 0
        func countThrough(_ date: Date) -> Int {
            while indexedDay < date {
                indexedDay = cal.date(byAdding: .day, value: 1, to: indexedDay)!
                if !isOff(indexedDay) { workingCount += 1 }
                counts[indexedDay] = workingCount
            }
            return counts[date] ?? 0
        }
        func workingDays(_ start: Date, _ end: Date) -> Int {
            guard start <= end else { return 0 }
            return countThrough(end) - countThrough(cal.date(byAdding: .day, value: -1, to: start)!)
        }
        var starts: [String: Date] = [:], ends: [String: Date] = [:], durations: [String: Int] = [:]
        var successors: [String: [(code: String, link: MasterSchedule.WBSDependency)]] = [:]
        for code in order {
            let item = byCode[code]!
            let a = cal.startOfDay(for: item.baselineStart!), b = cal.startOfDay(for: item.baselineEnd!)
            let links = item.dependencies ?? []
            var start = a
            var finish: Date?
            for link in links {
                switch link.type {
                case .finishToStart: start = max(start, move(ends[link.predecessor]!, link.lagDays + 1))
                case .startToStart: start = max(start, move(starts[link.predecessor]!, link.lagDays))
                case .finishToFinish:
                    let f = move(ends[link.predecessor]!, link.lagDays)
                    finish = finish.map { max($0, f) } ?? f
                }
                successors[link.predecessor, default: []].append((code, link))
            }
            let duration = max(item.days ?? workingDays(a, b), 1)
            var end: Date
            if links.isEmpty { end = b }
            else {
                start = workingStart(start); end = move(start, duration - 1)
                // a finish-to-finish link stretches the row to finish with its predecessor, as the workbook does
                if let finish, finish > end { end = workingStart(finish) }
            }
            starts[code] = start; ends[code] = end
            durations[code] = max(workingDays(start, end), 1)
        }
        let finish = ends.values.max()!
        var latestStarts: [String: Date] = [:], latestEnds: [String: Date] = [:], forecasts: [String: Forecast] = [:]
        for code in order.reversed() {
            let latestEnd = (successors[code] ?? []).map { s -> Date in
                switch s.link.type {
                case .finishToStart: return move(latestStarts[s.code]!, -(s.link.lagDays + 1))
                case .startToStart: return move(move(latestStarts[s.code]!, -s.link.lagDays), durations[code]! - 1)
                case .finishToFinish: return move(latestEnds[s.code]!, -s.link.lagDays)
                }
            }.min() ?? finish
            let latestStart = move(latestEnd, -(durations[code]! - 1))
            latestStarts[code] = latestStart; latestEnds[code] = latestEnd
            let slack = max(workingDays(starts[code]!, latestStart) - (isOff(starts[code]!) ? 0 : 1), 0)
            forecasts[code] = Forecast(start: starts[code]!, end: ends[code]!, float: slack)
        }
        // A linked task line's sub-tasks keep their place in its span (the workbook's `N + ROUND((O − N) × share)`).
        for line in linkedLines {
            guard let forecast = forecasts[line], let item = byCode[line],
                  let a = item.baselineStart.map({ cal.startOfDay(for: $0) }), let b = item.baselineEnd.map({ cal.startOfDay(for: $0) }) else { continue }
            let span = Double(max(cal.dateComponents([.day], from: a, to: b).day ?? 0, 0))
            let newSpan = Double(max(cal.dateComponents([.day], from: forecast.start, to: forecast.end).day ?? 0, 0))
            func place(_ d: Date) -> Date {
                let offset = Double(cal.dateComponents([.day], from: a, to: cal.startOfDay(for: d)).day ?? 0)
                let share = span > 0 ? min(max(offset / span, 0), 1) : 0
                return min(workingStart(cal.date(byAdding: .day, value: Int((newSpan * share).rounded()), to: forecast.start)!), forecast.end)
            }
            for sub in items where sub.code.hasPrefix(line + ".") && !sub.notForThisStation {
                guard let s = sub.baselineStart, let e = sub.baselineEnd else { continue }
                let start = place(s)
                forecasts[sub.code] = Forecast(start: start, end: max(place(e), start), float: forecast.float)
            }
        }
        return Result(forecasts: forecasts, issues: [])
    }

    /// `2.1`: a task line (one MP task), the level a workbook links.
    public static func isTaskLine(_ code: String) -> Bool { code.split(separator: ".").count == 2 }

    // MARK: the workbook's links

    /// The links a REV 11 plan file writes in `งานก่อนหน้า` (from the `DEP_*` lags on its `สมมติฐาน` sheet):
    /// `2.1 SS+3, 2.1 FF+2`, `Master Plan, FS 2.1–2.9+0`, `Master Plan, FS 2.2, 2.3+0`. Only that typed notation is
    /// read; the sheet's other words (`ย้อนจาก 2.10 (60 วัน)`, `Master Plan`, `3.2.7, 3.2.6`) stay prose.
    public static func parse(_ text: String) -> [MasterSchedule.WBSDependency] {
        let code = #"\d+(?:\.\d+)+"#
        let item = code + #"(?:\s*[–-]\s*"# + code + ")?"
        var links: [MasterSchedule.WBSDependency] = []
        let ns = text as NSString
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            (try? NSRegularExpression(pattern: pattern))?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        }
        // `FS <list>+n`: every row of the list, ranges expanded (`2.1–2.9`)
        var covered: [NSRange] = []
        for m in matches(#"(?<![\d.])FS\s+("# + item + #"(?:\s*,\s*"# + item + #")*)\s*([+-]\d+)(?![\d.])"#) {
            covered.append(m.range)
            guard let lag = Int(ns.substring(with: m.range(at: 2))) else { continue }
            for part in ns.substring(with: m.range(at: 1)).split(separator: ",") {
                for predecessor in expand(part.trimmingCharacters(in: .whitespaces)) {
                    links.append(.init(predecessor: predecessor, lagDays: lag))
                }
            }
        }
        for m in matches(#"(?<![\d.])("# + code + #")\s+(SS|FF|FS)\s*([+-]\d+)(?![\d.])"#)
        where !covered.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            guard let type = MasterSchedule.WBSDependency.Kind(rawValue: ns.substring(with: m.range(at: 2))),
                  let lag = Int(ns.substring(with: m.range(at: 3))) else { continue }
            links.append(.init(predecessor: ns.substring(with: m.range(at: 1)), lagDays: lag, type: type))
        }
        return links
    }

    /// `2.1–2.9` → 2.1 … 2.9 (the same parent); a single code as it is.
    static func expand(_ text: String) -> [String] {
        let ends = text.split { $0 == "–" || $0 == "-" }.map { $0.trimmingCharacters(in: .whitespaces) }
        guard ends.count == 2, let dot = ends[0].lastIndex(of: "."), let dot2 = ends[1].lastIndex(of: "."),
              ends[0][..<dot] == ends[1][..<dot2],
              let from = Int(ends[0][ends[0].index(after: dot)...]), let to = Int(ends[1][ends[1].index(after: dot2)...]),
              from <= to, to - from < 100 else { return ends.count == 1 ? ends : [] }
        return (from...to).map { String(ends[0][..<dot]) + ".\($0)" }
    }

    /// The plan file's typed links put on its rows, for a file the app never saved links into. A link to or from a row
    /// this station leaves out (`(ไม่ต้อง…)`), a part, a missing row or one without dates is dropped, so one
    /// station's case doesn't stop the whole plan forecasting; nil when the file has none.
    public static func fromWorkbook(_ items: [MasterSchedule.WorkItem]) -> [MasterSchedule.WorkItem]? {
        let parents = items.parentCodes
        let byCode = Dictionary(items.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        func usable(_ code: String) -> Bool {
            guard let item = byCode[code] else { return false }
            return !item.notForThisStation && item.baselineStart != nil && item.baselineEnd != nil
                && (!parents.contains(code) || isTaskLine(code))
        }
        var found = false
        let linked = items.map { item -> MasterSchedule.WorkItem in
            guard let text = item.predecessor, usable(item.code) else { return item }
            var seen: Set<String> = []
            let links = parse(text).filter { $0.predecessor != item.code && $0.lagDays >= 0 && usable($0.predecessor)
                && seen.insert($0.predecessor + " " + $0.type.rawValue).inserted }
            guard !links.isEmpty else { return item }
            found = true
            var row = item
            row.dependencies = links
            return row
        }
        return found ? linked : nil
    }
}

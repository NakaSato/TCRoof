import Foundation

public extension MasterSchedule {
    struct WBSDependency: Codable, Equatable, Sendable {
        public var predecessor: String
        /// Whole working days between the predecessor's finish and this row's start. Zero starts next working day.
        public var lagDays: Int
        public init(predecessor: String, lagDays: Int = 0) {
            self.predecessor = predecessor
            self.lagDays = lagDays
        }
    }
}

/// Opt-in WBS forecasting. Existing dates are release constraints; only explicitly linked rows move later.
/// Summary rows and rows marked irrelevant cannot be dependency endpoints. Nonworking dates are supplied by the plan.
public enum WBSDependencies {
    public enum Issue: Equatable, Sendable {
        case duplicateCode(String)
        case missingPredecessor(task: String, predecessor: String)
        case invalidEndpoint(String)
        case invalidDates(String)
        case negativeLag(task: String, predecessor: String)
        case duplicateLink(task: String, predecessor: String)
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
        func eligible(_ item: MasterSchedule.WorkItem) -> Bool { !parents.contains(item.code) && !item.notForThisStation }
        var linked: Set<String> = []
        for item in items where !(item.dependencies ?? []).isEmpty {
            linked.insert(item.code)
            if !eligible(item) { issues.append(.invalidEndpoint(item.code)) }
            var seen: Set<String> = []
            for link in item.dependencies ?? [] {
                linked.insert(link.predecessor)
                if !seen.insert(link.predecessor).inserted { issues.append(.duplicateLink(task: item.code, predecessor: link.predecessor)) }
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
        var successors: [String: [(code: String, lag: Int)]] = [:]
        for code in order {
            let item = byCode[code]!
            let a = cal.startOfDay(for: item.baselineStart!), b = cal.startOfDay(for: item.baselineEnd!)
            let links = item.dependencies ?? []
            var start = a
            for link in links {
                start = max(start, move(ends[link.predecessor]!, link.lagDays + 1))
                successors[link.predecessor, default: []].append((code, link.lagDays))
            }
            let duration = max(item.days ?? workingDays(a, b), 1)
            let end: Date
            if links.isEmpty { end = b }
            else { start = workingStart(start); end = move(start, duration - 1) }
            starts[code] = start; ends[code] = end
            durations[code] = max(workingDays(start, end), 1)
        }
        let finish = ends.values.max()!
        var latestStarts: [String: Date] = [:], forecasts: [String: Forecast] = [:]
        for code in order.reversed() {
            let latestEnd = (successors[code] ?? []).map { move(latestStarts[$0.code]!, -($0.lag + 1)) }.min() ?? finish
            let latestStart = move(latestEnd, -(durations[code]! - 1))
            latestStarts[code] = latestStart
            let slack = max(workingDays(starts[code]!, latestStart) - (isOff(starts[code]!) ? 0 : 1), 0)
            forecasts[code] = Forecast(start: starts[code]!, end: ends[code]!, float: slack)
        }
        return Result(forecasts: forecasts, issues: [])
    }
}

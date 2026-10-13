import Foundation

/// One post of the home's project feed (docs/ui/tcroof-home-iphone-v3). Nobody writes a post: `FeedBuilder` makes each
/// one from a record the app already has.
public struct FeedPost: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case progress, waitingInspector, testResult, issue, summary

        public var badge: String {
            switch self {
            case .progress: "รายงานวันนี้"
            case .waitingInspector: "รอผู้ตรวจ"
            case .testResult: "อัตโนมัติ"
            case .issue: "ปัญหา"
            case .summary: "สรุปวันนี้"
            }
        }

        public var tone: Tone {
            switch self {
            case .progress, .summary: .blue
            case .waitingInspector: .orange
            case .testResult: .green
            case .issue: .red
            }
        }

        /// The link that opens the source record.
        public var link: String {
            switch self {
            case .progress: "ดูรายงาน"
            case .testResult: "ดูผลทดสอบ"
            case .waitingInspector, .issue: "ดูงาน"
            case .summary: "ดูสรุป"
            }
        }
    }

    public enum Tone: Sendable { case blue, green, orange, red }
    public enum Project: String, Sendable { case pwa, home }

    /// A chip over the photo: `+6% วันนี้`, `38% / แผน 50%` (red when behind the plan).
    public struct Chip: Equatable, Sendable {
        public var text: String
        public var tone: Tone
        public init(_ text: String, _ tone: Tone) { self.text = text; self.tone = tone }
    }

    /// A stat tile of a system post: `8/12` over `ส่งรายงาน`.
    public struct Stat: Equatable, Sendable {
        public var value: String
        public var label: String
        public var tone: Tone
        public init(_ value: String, _ label: String, _ tone: Tone) { self.value = value; self.label = label; self.tone = tone }
    }

    /// The box under an issue post's text.
    public struct Issue: Equatable, Sendable {
        public var owner: String
        public var due: Date?
        public var fixed: Bool
        /// False while the source record can't be closed yet (a punch needs a photo of the fix first).
        public var canFix: Bool
        public init(owner: String, due: Date? = nil, fixed: Bool, canFix: Bool = true) {
            self.owner = owner; self.due = due; self.fixed = fixed; self.canFix = canFix
        }
    }

    /// The record a post came from; `project` is the station's id.
    public enum Source: Equatable, Sendable {
        case dailyReport(project: String, day: Date)
        case test(project: String, id: String)
        case problem(project: String, id: UUID)
        case punch(project: String, id: String)
        case summary(day: Date)
    }

    public var id: String
    public var kind: Kind
    /// Nil on a post about every project (the daily summary).
    public var project: Project?
    public var team: String
    /// Who signed the record, when it names one; a post by the viewer raises no notification.
    public var recorder: String
    /// The avatar's letters.
    public var initials: String
    public var who: String
    public var place: String
    public var date: Date
    public var text: String
    /// The record's photos, as the ids the caller gave.
    public var photos: [String]
    public var chips: [Chip]
    public var stats: [Stat]
    public var issue: Issue?
    public var source: Source
    /// The summary on the day it is made: it stays on top.
    public var pinned: Bool
    /// Acknowledgements the post starts with (sample posts only).
    public var seedAcks: Int

    public init(id: String, kind: Kind, project: Project?, team: String = "", recorder: String = "", initials: String, who: String, place: String,
                date: Date, text: String, photos: [String] = [], chips: [Chip] = [], stats: [Stat] = [], issue: Issue? = nil,
                source: Source, pinned: Bool = false, seedAcks: Int = 0) {
        self.id = id; self.kind = kind; self.project = project; self.team = team; self.recorder = recorder; self.initials = initials; self.who = who
        self.place = place; self.date = date; self.text = text; self.photos = photos; self.chips = chips; self.stats = stats
        self.issue = issue; self.source = source; self.pinned = pinned; self.seedAcks = seedAcks
    }
}

/// The feed's filter chips: `ทั้งหมด` · `กปภ.` · `งานบ้าน` · `ทีมของฉัน`.
public enum FeedFilter: String, CaseIterable, Identifiable, Sendable {
    case all, pwa, home, mine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "ทั้งหมด"
        case .pwa: "กปภ."
        case .home: "งานบ้าน"
        case .mine: "ทีมของฉัน"
        }
    }
}

/// Turns the day's records into the project feed. Pure: the app passes its jobs in as `Station`s.
public enum FeedBuilder {
    public static var calendar: Calendar { RoutineReport.calendar }
    /// The daily summary is made at this hour, the daily report's deadline.
    public static let summaryHour = 18
    public static let windowDays = 7

    /// A daily report with what its install log knows about it.
    public struct Report: Equatable, Sendable {
        public var daily: RoutineReport.Daily
        public var signedAt: Date?
        public var inspectorAckAt: Date?
        public var recorder: String
        public var photos: [String]
        public init(_ daily: RoutineReport.Daily, signedAt: Date?, inspectorAckAt: Date? = nil, recorder: String = "", photos: [String] = []) {
            self.daily = daily; self.signedAt = signedAt; self.inspectorAckAt = inspectorAckAt; self.recorder = recorder; self.photos = photos
        }
    }

    /// A finished test: how many points passed, and up to two more tiles.
    public struct Test: Equatable, Sendable {
        public var id: String
        public var date: Date
        public var title: String
        public var unit: String
        public var passed: Int
        public var total: Int
        public var extra: [FeedPost.Stat]
        public init(id: String, date: Date, title: String, unit: String, passed: Int, total: Int, extra: [FeedPost.Stat] = []) {
            self.id = id; self.date = date; self.title = title; self.unit = unit; self.passed = passed; self.total = total; self.extra = extra
        }
    }

    /// One project with the records that make posts.
    public struct Station: Equatable, Sendable {
        public var id: String
        public var code: String
        public var name: String
        public var project: FeedPost.Project
        public var team: String
        public var mpNumber: Int?
        public var installStart: Date
        public var installDays: Int
        public var settings = RoutineReport.Settings()
        public var plan: [MasterSchedule.PlannedTask] = []
        public var reports: [Report] = []
        public var tests: [Test] = []
        public var punches: [HomePunch] = []
        /// The installer on the home job's work order, who fixes its punch list.
        public var contractor = ""

        public init(id: String, code: String, name: String, project: FeedPost.Project, team: String, mpNumber: Int? = nil,
                    installStart: Date, installDays: Int) {
            self.id = id; self.code = code; self.name = name; self.project = project; self.team = team
            self.mpNumber = mpNumber; self.installStart = installStart; self.installDays = installDays
        }

        /// "MP 189 ทุ่งน้อย", or the job code.
        public var label: String {
            guard project == .pwa else { return code }
            return [mpNumber.map { "MP \($0)" } ?? code, name].filter { !$0.isEmpty }.joined(separator: " ")
        }

        var signed: [Report] { reports.filter { $0.signedAt != nil }.sorted { $0.daily.date < $1.daily.date } }
        var dailies: [RoutineReport.Daily] { signed.map(\.daily) }

        /// 1-based install day on `date`, nil outside the install window.
        func installDay(on date: Date) -> Int? {
            let cal = FeedBuilder.calendar
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: installStart), to: cal.startOfDay(for: date)).day ?? -1
            return (0..<max(installDays, 1)).contains(n) ? n + 1 : nil
        }

        /// Whole-station percent through `date`: the plan's weights over each task's reported percent; without a plan,
        /// the mean of the lines' latest percents.
        func overall(through date: Date) -> Double {
            let weighted = plan.filter { $0.weight > 0 }
            if !weighted.isEmpty {
                return weighted.reduce(0) { sum, p in
                    sum + p.weight * (RoutineReport.taskPercent(p.task, reports: dailies, through: date, settings: settings) ?? 0) / 100
                }
            }
            var latest: [String: Double] = [:]
            for r in dailies where RoutineReport.day(r.date) <= RoutineReport.day(date) {
                for l in r.progress { latest[l.key] = l.percent }
            }
            return latest.isEmpty ? 0 : latest.values.reduce(0, +) / Double(latest.count)
        }
    }

    // MARK: Posts

    /// Every post of the last `days` days up to `now`: today's summary first, then newest first.
    public static func posts(_ stations: [Station], now: Date, days: Int = windowDays) -> [FeedPost] {
        let from = RoutineReport.add(RoutineReport.day(now), -(max(days, 1) - 1))
        var all: [FeedPost] = []
        for s in stations {
            all += reportPosts(s) + testPosts(s) + problemPosts(s) + punchPosts(s)
        }
        all += summaries(stations, from: from, now: now)
        return all.filter { $0.date >= from && $0.date <= now }
            .sorted { $0.pinned != $1.pinned ? $0.pinned : $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
    }

    static func reportPosts(_ s: Station) -> [FeedPost] {
        let dailies = s.dailies
        return s.signed.compactMap { r in
            guard let signedAt = r.signedAt else { return nil }
            let d = r.daily
            let done = RoutineReport.workDone(d, in: dailies)
            let main = done.max { $0.delta < $1.delta }
            var text = done.map { "\($0.line.title) \(RoutineReport.percent($0.line.percent))" }.joined(separator: " · ")
            if text.isEmpty { text = d.stopReason.isEmpty ? "ส่งรายงานประจำวันแล้ว" : "หยุดงาน: " + d.stopReason }
            var chips: [FeedPost.Chip] = []
            if let main {
                chips.append(.init("+\(RoutineReport.percent(main.delta)) วันนี้", .green))
                if let task = main.line.task, s.plan.contains(where: { $0.task == task && $0.weight > 0 }),
                   let actual = RoutineReport.taskPercent(task, reports: dailies, through: d.date, settings: s.settings),
                   let planned = MasterSchedule.status(plan: s.plan, actual: .init(), through: d.date).plannedByTask[task] {
                    chips.append(.init("\(RoutineReport.percent(actual)) / แผน \(RoutineReport.percent(planned))", actual + 1e-9 < planned ? .red : .green))
                }
            }
            // a line finished today that the inspector has not acknowledged yet
            let finished = done.contains { $0.line.percent >= 100 }
            let task = main?.line.task.map { "\($0.code) \($0.title)" }
            return FeedPost(id: "daily-\(s.id)-\(RoutineReport.dayKey(d.date))",
                            kind: finished && r.inspectorAckAt == nil ? .waitingInspector : .progress,
                            project: s.project, team: s.team, recorder: r.recorder, initials: initials(team: s.team),
                            who: who(s.team, r.recorder), place: [s.label, task].compactMap { $0 }.joined(separator: " · "),
                            date: signedAt, text: text, photos: r.photos, chips: chips,
                            source: .dailyReport(project: s.id, day: d.date))
        }
    }

    static func testPosts(_ s: Station) -> [FeedPost] {
        s.tests.map { t in
            let ok = t.passed >= t.total
            let text = ok ? "\(t.title) ผ่านครบ \(t.total) \(t.unit)" : "\(t.title) ผ่าน \(t.passed) จาก \(t.total) \(t.unit)"
            let stats = [FeedPost.Stat("\(t.passed)/\(t.total)", "\(t.unit)ผ่าน", ok ? .green : .red)] + t.extra.prefix(2)
            return FeedPost(id: "test-\(s.id)-\(t.id)", kind: .testResult, project: s.project, team: s.team, initials: "TC",
                            who: "TCRoof", place: s.label, date: t.date, text: text, stats: stats,
                            source: .test(project: s.id, id: t.id))
        }
    }

    /// Problems of the signed daily reports, each in its latest state and dated by the report that raised it.
    static func problemPosts(_ s: Station) -> [FeedPost] {
        let signed = s.signed
        let (open, closed) = RoutineReport.problems(signed.map(\.daily))
        return (open + closed).compactMap { p in
            guard let first = signed.first(where: { $0.daily.problems.contains { $0.id == p.id } }), let at = first.signedAt else { return nil }
            let owner = s.settings.siteEngineer.isEmpty ? first.recorder : s.settings.siteEngineer
            let text = p.solution.isEmpty ? p.description : p.description + " — " + p.solution
            return FeedPost(id: "problem-\(s.id)-\(p.id.uuidString)", kind: .issue, project: s.project, team: s.team,
                            recorder: first.recorder, initials: initials(team: s.team), who: who(s.team, first.recorder), place: place(s, on: first.daily.date),
                            date: at, text: text, issue: .init(owner: owner, fixed: p.closed),
                            source: .problem(project: s.id, id: p.id))
        }
    }

    /// The home job's punch list. A punch made before `raised` was kept is dated by its due date.
    static func punchPosts(_ s: Station) -> [FeedPost] {
        s.punches.compactMap { p in
            guard !p.title.trimmingCharacters(in: .whitespaces).isEmpty, let at = p.raised ?? p.due ?? p.closed else { return nil }
            let text = p.location.isEmpty ? p.title : p.title + " · " + p.location
            return FeedPost(id: "punch-\(s.id)-\(p.id)", kind: .issue, project: s.project, team: s.team,
                            initials: initials(team: s.team), who: who(s.team, s.project == .home ? "งานบ้าน" : ""), place: place(s, on: at),
                            date: at, text: text, photos: p.isOpen ? p.before : p.after,
                            issue: .init(owner: s.contractor, due: p.due, fixed: !p.isOpen, canFix: p.canClose),
                            source: .punch(project: s.id, id: p.id))
        }
    }

    // MARK: Daily summary

    /// The latest summary only: today's once 18:00 has passed, until then the last day's that has one. A summary is
    /// made when a station was due a report or sent one, or an issue is open.
    static func summaries(_ stations: [Station], from: Date, now: Date) -> [FeedPost] {
        var day = RoutineReport.day(now)
        while day >= RoutineReport.day(from) {
            defer { day = RoutineReport.add(day, -1) }
            guard let at = calendar.date(bySettingHour: summaryHour, minute: 0, second: 0, of: day), at <= now,
                  let s = summary(stations, day: day, now: now) else { continue }
            return [FeedPost(id: "summary-\(RoutineReport.dayKey(day))", kind: .summary, project: nil, initials: "TC", who: "TCRoof",
                             place: "ทุกโครงการ", date: at, text: s.text, stats: s.stats, source: .summary(day: day),
                             pinned: calendar.isDate(day, inSameDayAs: now))]
        }
        return []
    }

    /// The numbers of one day: reports sent over stations due one, the mean progress of those stations that day, and
    /// the issues raised by that day that are still open.
    public static func summary(_ stations: [Station], day: Date, now: Date) -> (text: String, stats: [FeedPost.Stat], sent: Int, due: Int, delta: Double, open: Int)? {
        let key = RoutineReport.dayKey(day)
        func sent(_ s: Station) -> Bool { s.signed.contains { RoutineReport.dayKey($0.daily.date) == key } }
        let counted = stations.filter { s in
            s.project == .pwa && (sent(s) || (s.installDay(on: day) != nil && RoutineReport.isWorkingDay(day, settings: s.settings)))
        }
        let open = stations.flatMap { s in (problemPosts(s) + punchPosts(s)).map { (s, $0) } }
            .filter { $0.1.issue?.fixed == false && RoutineReport.day($0.1.date) <= RoutineReport.day(day) }
        guard !counted.isEmpty || !open.isEmpty else { return nil }
        let n = counted.filter(sent).count
        let delta = counted.isEmpty ? 0 : counted.reduce(0) { $0 + $1.overall(through: day) - $1.overall(through: RoutineReport.add(day, -1)) } / Double(counted.count)
        let c = calendar.dateComponents([.month, .day], from: day)
        var text = "สรุปวันที่ \(c.day ?? 0) \(RoutineReport.thaiMonthsShort[(c.month ?? 1) - 1]) — ส่งรายงานแล้ว \(n)/\(counted.count) สถานี กปภ. ความคืบหน้ารวม \(signed(delta))"
        if !open.isEmpty {
            var seen: [String] = []
            for (s, _) in open where !seen.contains(s.id) { seen.append(s.id) }
            let names = seen.prefix(2).compactMap { id in stations.first { $0.id == id } }.map { ($0.project == .home ? "งานบ้าน " : "") + $0.label }
            text += " ปัญหาค้าง \(open.count) เรื่อง (\(names.joined(separator: ", "))\(seen.count > 2 ? " …" : ""))"
        }
        let stats = [FeedPost.Stat("\(n)/\(counted.count)", "ส่งรายงาน", .blue),
                     FeedPost.Stat(signed(delta), "ความคืบหน้ารวม", delta < 0 ? .red : .green),
                     FeedPost.Stat("\(open.count)", "ปัญหาค้าง", open.isEmpty ? .green : .red)]
        return (text, stats, n, counted.count, delta, open.count)
    }

    // MARK: Filter

    /// The summary shows under every filter. `myTeams` are the teams `ทีมของฉัน` keeps.
    public static func filter(_ posts: [FeedPost], by filter: FeedFilter, myTeams: Set<String> = [], hidden: Set<String> = []) -> [FeedPost] {
        posts.filter { p in
            guard !hidden.contains(p.id) else { return false }
            if p.kind == .summary { return true }
            switch filter {
            case .all: return true
            case .pwa: return p.project == .pwa
            case .home: return p.project == .home
            case .mine: return myTeams.contains(p.team)
            }
        }
    }

    public static func counts(_ posts: [FeedPost], myTeams: Set<String> = [], hidden: Set<String> = []) -> [FeedFilter: Int] {
        Dictionary(uniqueKeysWithValues: FeedFilter.allCases.map { ($0, filter(posts, by: $0, myTeams: myTeams, hidden: hidden).count) })
    }

    // MARK: Text

    /// `5 คนรับทราบ`, or `คุณและอีก 5 คนรับทราบ` once the viewer is one of them.
    public static func ackLine(count: Int, mine: Bool) -> String {
        let others = mine ? max(count - 1, 0) : count
        if mine { return others == 0 ? "คุณรับทราบแล้ว" : "คุณและอีก \(others) คนรับทราบ" }
        return others == 0 ? "ยังไม่มีคนรับทราบ" : "\(others) คนรับทราบ"
    }

    /// `25 นาที`, `3 ชม.`, then the date; the summary shows the time it was made.
    public static func when(_ post: FeedPost, now: Date) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: post.date)
        let date = "\(c.day ?? 0) \(RoutineReport.thaiMonthsShort[(c.month ?? 1) - 1])"
        if post.kind == .summary {
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            return calendar.isDate(post.date, inSameDayAs: now) ? time : date + " " + time
        }
        let mins = Int(now.timeIntervalSince(post.date) / 60)
        if mins < 1 { return "เมื่อสักครู่" }
        if mins < 60 { return "\(mins) นาที" }
        if mins < 24 * 60 { return "\(mins / 60) ชม." }
        return date
    }

    /// `13 ต.ค.`
    public static func shortDate(_ d: Date) -> String {
        let c = calendar.dateComponents([.month, .day], from: d)
        return "\(c.day ?? 0) \(RoutineReport.thaiMonthsShort[(c.month ?? 1) - 1])"
    }

    /// The avatar letter of a team: "1" for TCR01, else the name's first letter.
    public static func initials(team: String) -> String {
        let digits = team.reversed().prefix { $0.isNumber }.reversed().drop { $0 == "0" }
        if !digits.isEmpty { return String(digits) }
        return team.first.map { String($0).uppercased() } ?? "TC"
    }

    static func who(_ team: String, _ detail: String) -> String {
        [team.isEmpty ? nil : "ทีม " + team, detail.isEmpty ? nil : detail].compactMap { $0 }.joined(separator: " · ")
    }

    /// "TC-0012 · ติดตั้ง Day 2/5" inside the install window, else the station's label.
    static func place(_ s: Station, on date: Date) -> String {
        guard let n = s.installDay(on: date) else { return s.label }
        return "\(s.label) · ติดตั้ง Day \(n)/\(max(s.installDays, 1))"
    }

    /// "+2%", "-1.5%", "0%".
    static func signed(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return (r > 0 ? "+" : "") + RoutineReport.percent(r)
    }

    // MARK: Issue round trip

    /// Marks the problem fixed or open again in the latest report that carries it, the one `RoutineReport.problems`
    /// reads; earlier reports keep what was true on their day. Returns false when no report has it.
    public static func setProblem(_ id: UUID, fixed: Bool, in reports: inout [RoutineReport.Daily]) -> Bool {
        let carrying = reports.indices.filter { r in reports[r].problems.contains { $0.id == id } }
        guard let r = carrying.max(by: { reports[$0].date < reports[$1].date }),
              let p = reports[r].problems.firstIndex(where: { $0.id == id }) else { return false }
        reports[r].problems[p].closed = fixed
        return true
    }

    /// Closes or reopens the punch. Closing is refused until it has a photo of the fix.
    public static func setPunch(_ id: String, fixed: Bool, in site: inout HomeSite, at date: Date) -> Bool {
        guard let i = site.punches.firstIndex(where: { $0.id == id }) else { return false }
        if fixed {
            guard site.punches[i].canClose else { return false }
            site.punches[i].closed = date
        } else {
            site.punches[i].closed = nil
        }
        return true
    }
}

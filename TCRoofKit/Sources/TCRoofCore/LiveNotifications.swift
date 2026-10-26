import Foundation

// The live notification cases: install days, the MP plan, and the project feed's events as they happen.
// Their ids are the bell's ids (an install day's `install-<jobKey>-<yyyy-MM-dd>`, a feed post's own id).

// MARK: - Install days

public enum InstallNotification {
    public static let lead: TimeInterval = 30 * 60

    /// Id of an install day, the same as the bell's.
    public static func id(jobKey: String, day: Date) -> String { "install-\(jobKey)-\(ISODate.string(day))" }

    /// `ติดตั้ง Day 2/5`, 30 min before that day's start.
    public static func day(jobKey: String, name: String, team: String, day n: Int, of total: Int, start: Date) -> NotificationPlan {
        NotificationPlan(id: id(jobKey: jobKey, day: start), type: .install, title: "ติดตั้ง Day \(n)/\(total)", body: name,
                         sub: [team.isEmpty ? "" : "ทีม \(team)", "เริ่ม \(ThaiDate.time(start))"].filter { !$0.isEmpty }.joined(separator: " | "),
                         fire: .at(start.addingTimeInterval(-lead)), info: [NotificationInfo.job: jobKey])
    }

    /// `เริ่มติดตั้งพรุ่งนี้`, 18:00 on the eve of day 1.
    public static func eve(jobKey: String, name: String, team: String, days: Int, start: Date,
                           calendar cal: Calendar = Calendar.current) -> NotificationPlan? {
        guard let before = cal.date(byAdding: .day, value: -1, to: start),
              let at = cal.date(bySettingHour: 18, minute: 0, second: 0, of: before) else { return nil }
        let sub = [team.isEmpty ? "" : "ทีม \(team)", "\(max(days, 1)) วัน", "เริ่ม \(ThaiDate.time(start))"].filter { !$0.isEmpty }
        return NotificationPlan(id: "install-eve-\(jobKey)-\(ISODate.string(start))", type: .install, title: "เริ่มติดตั้งพรุ่งนี้", body: name,
                                sub: sub.joined(separator: " | "), fire: .at(at), info: [NotificationInfo.job: jobKey])
    }

    /// The eve reminder and the install days whose reminder is still ahead and fires before the end of tomorrow.
    public static func plans(jobKey: String, name: String, team: String, start: Date, days: Int, now: Date,
                             calendar cal: Calendar = Calendar.current) -> [NotificationPlan] {
        let total = max(days, 1)
        guard let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) else { return [] }
        var out = [eve(jobKey: jobKey, name: name, team: team, days: total, start: start, calendar: cal)].compactMap { $0 }
        for i in 0..<total {
            guard let at = cal.date(byAdding: .day, value: i, to: start) else { continue }
            out.append(day(jobKey: jobKey, name: name, team: team, day: i + 1, of: total, start: at))
        }
        return out.filter { $0.fireDate(now: now) > now && $0.fireDate(now: now) < end }
    }
}

// MARK: - MP plan

public enum MPNotification {
    /// `เริ่มงานพรุ่งนี้ตามแผน MP` at 17:00 when tasks start tomorrow, and `ช้ากว่าแผน MP` at 08:00 on next week's
    /// Monday while this week's recorded progress is under the plan.
    public static func plans(jobKey: String, station: String, plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual,
                             now: Date, calendar cal: Calendar = MasterSchedule.calendar) -> [NotificationPlan] {
        var out: [NotificationPlan] = []
        let today = cal.startOfDay(for: now)
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
           let at = cal.date(bySettingHour: 17, minute: 0, second: 0, of: today), at > now {
            let starting = plan.filter { $0.start.map { cal.isDate($0, inSameDayAs: tomorrow) } ?? false }
            if !starting.isEmpty {
                let names = starting.prefix(2).map { "\($0.task.code) \($0.task.title)" }.joined(separator: " | ")
                out.append(NotificationPlan(id: "mp-start-\(jobKey)-\(MasterSchedule.Actual.key(tomorrow, calendar: cal))-\(starting[0].task.rawValue)",
                                            type: .mp, title: "เริ่มงานพรุ่งนี้ตามแผน MP", body: station,
                                            sub: names + (starting.count > 2 ? " +\(starting.count - 2)" : ""), fire: .at(at),
                                            info: [NotificationInfo.job: jobKey]))
            }
        }
        let status = MasterSchedule.status(plan: plan, actual: actual, through: now, calendar: cal)
        let week = MasterSchedule.weekStart(now, calendar: cal)
        if status.planned > 0, status.actual < 100, status.variance <= -0.5,
           let monday = cal.date(byAdding: .day, value: 8, to: week),
           let at = cal.date(bySettingHour: 8, minute: 0, second: 0, of: monday) {
            out.append(NotificationPlan(id: "mp-behind-\(jobKey)-\(MasterSchedule.Actual.key(week, calendar: cal))", type: .mp,
                                        title: "ช้ากว่าแผน MP \(RoutineReport.percent(-status.variance))", body: station,
                                        sub: "จริง \(RoutineReport.percent(status.actual)) / แผน \(RoutineReport.percent(status.planned)) | แตะเพื่อบันทึกความก้าวหน้า",
                                        fire: .at(at), info: [NotificationInfo.job: jobKey]))
        }
        return out
    }
}

// MARK: - ERC flow

public enum ERCNotification {
    /// How many days before a time limit ends the reminder comes.
    public static let lead = 3

    /// For each step the utility or DEDE has: `ใกล้ครบกำหนด` at 08:00 three days before its time limit ends (working
    /// days where the limit counts them) and `เกินกำหนด` at 08:00 the day after. Posted as MP plan notifications, so a
    /// tap opens the job.
    public static func plans(jobKey: String, station: String, record: ERCFlow.Record, context: ERCFlow.Context = .init(),
                             now: Date, calendar cal: Calendar = MasterSchedule.calendar) -> [NotificationPlan] {
        func at8(_ day: String?, plus days: Int = 0) -> Date? {
            guard let d = day.flatMap(ERCFlow.date), let shifted = cal.date(byAdding: .day, value: days, to: d) else { return nil }
            return cal.date(bySettingHour: 8, minute: 0, second: 0, of: shifted)
        }
        var out: [NotificationPlan] = []
        for wait in ERCFlow.waits(record, context, today: now) {
            let working = wait.step.limit?.working == true
            let sub = "\(wait.step.party.title) | ลำดับ กกพ. ข้อ \(wait.number ?? 0) | ครบกำหนด \(ERCFlow.date(wait.due).map(RoutineReport.thaiDate) ?? wait.due)"
            if let at = at8(ERCFlow.day(wait.due, before: lead, working: working, context)), at > now {
                out.append(NotificationPlan(id: "erc-soon-\(jobKey)-\(wait.step.rawValue)-\(wait.due)", type: .mp,
                                            title: "\(wait.title) เหลือ \(lead) \(wait.unit)", body: station, sub: sub,
                                            fire: .at(at), info: [NotificationInfo.job: jobKey]))
            }
            if let at = at8(wait.due, plus: 1), at > now {
                out.append(NotificationPlan(id: "erc-over-\(jobKey)-\(wait.step.rawValue)-\(wait.due)", type: .mp,
                                            title: "\(wait.title) เกินกำหนดแล้ว", body: station, sub: sub + " | ติดตามกับ\(wait.step.party.title)",
                                            fire: .at(at), info: [NotificationInfo.job: jobKey]))
            }
        }
        return out
    }
}

// MARK: - Project feed

/// A feed post as a notification, with the post's id: a report sent, work waiting for the inspector, a test result,
/// a new issue, and the daily summary.
public enum FeedNotification {
    /// A post older than this when it is first seen raises nothing (the app was closed for days).
    public static let window: TimeInterval = 24 * 3600
    /// At most this many at once.
    public static let burst = 5

    public static func type(_ kind: FeedPost.Kind) -> NotificationType {
        switch kind {
        case .progress, .testResult, .summary: .feed
        case .waitingInspector: .inspect
        case .issue: .issue
        }
    }

    public static func title(_ kind: FeedPost.Kind) -> String {
        switch kind {
        case .progress: "ส่งรายงานประจำวันแล้ว"
        case .waitingInspector: "งานเสร็จ รอผู้ตรวจ"
        case .testResult: "ผลทดสอบ"
        case .issue: "ปัญหาใหม่"
        case .summary: "สรุปวันนี้"
        }
    }

    public static func plan(_ post: FeedPost, fire: NotificationPlan.Fire = .after(1)) -> NotificationPlan {
        var info: [String: String] = [:]
        switch post.source {
        case .dailyReport(let job, let day):
            info = [NotificationInfo.job: job, NotificationInfo.record: post.kind == .waitingInspector ? "inspect" : "daily",
                    NotificationInfo.day: ISO.string(day)]
        case .test(let job, _): info = [NotificationInfo.job: job, NotificationInfo.record: "test"]
        case .problem(let job, _): info = [NotificationInfo.job: job, NotificationInfo.record: "problem"]
        case .punch(let job, _): info = [NotificationInfo.job: job, NotificationInfo.record: "punch"]
        case .summary: info = [NotificationInfo.record: "summary"]
        }
        let summary = post.kind == .summary
        return NotificationPlan(id: post.id, type: type(post.kind), title: title(post.kind), body: summary ? post.text : post.place,
                                sub: summary ? "" : post.text, fire: fire, info: info)
    }

    /// The posts to announce now: not seen before, made in the last day, not the viewer's own, and not an issue
    /// that is already fixed. The summary is scheduled instead (`summary`). Newest first, `burst` at most.
    public static func fresh(_ posts: [FeedPost], seen: Set<String>, me: String, now: Date) -> [NotificationPlan] {
        posts.filter { p in
            guard p.kind != .summary, !seen.contains(p.id), p.date <= now, now.timeIntervalSince(p.date) <= window else { return false }
            if !me.isEmpty, p.recorder == me { return false }
            return p.issue?.fixed != true
        }
        .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        .prefix(burst).map { plan($0) }
    }

    /// `สรุปวันนี้` at 18:00 with today's numbers so far; nil once 18:00 has passed or the day has nothing to sum up.
    public static func summary(_ stations: [FeedBuilder.Station], now: Date) -> NotificationPlan? {
        let cal = FeedBuilder.calendar
        let day = cal.startOfDay(for: now)
        guard let at = cal.date(bySettingHour: FeedBuilder.summaryHour, minute: 0, second: 0, of: day), at > now,
              let s = FeedBuilder.summary(stations, day: day, now: now) else { return nil }
        return NotificationPlan(id: "summary-\(RoutineReport.dayKey(day))", type: .feed, title: title(.summary), body: s.text, sub: "",
                                fire: .at(at), info: [NotificationInfo.record: "summary"])
    }

    /// `ครบกำหนดแก้วันนี้` at 08:00 on the due day of each open issue whose reminder is still ahead.
    public static func due(_ posts: [FeedPost], now: Date, calendar cal: Calendar = FeedBuilder.calendar) -> [NotificationPlan] {
        posts.compactMap { p in
            guard let issue = p.issue, !issue.fixed, let due = issue.due,
                  let at = cal.date(bySettingHour: 8, minute: 0, second: 0, of: due), at > now else { return nil }
            var out = Self.plan(p, fire: .at(at))
            out.id = "due-\(p.id)"
            out.title = "ครบกำหนดแก้วันนี้"
            return out
        }
    }

    /// Where a feed notification leads, as the post's own link does.
    public static func link(_ info: [String: String]) -> DeepLink {
        let job = info[NotificationInfo.job] ?? ""
        switch info[NotificationInfo.record] {
        case "summary": return .records
        case _ where job.isEmpty: return .home
        case "daily": return ISO.date(info[NotificationInfo.day]).map { .daily(job: job, day: $0) } ?? .job(job: job)
        case "test": return .inspection(job: job)
        case "punch": return .homework(job: job)
        default: return .job(job: job)
        }
    }
}

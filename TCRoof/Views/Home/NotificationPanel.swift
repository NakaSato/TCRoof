import SwiftUI
import TCRoofCore
import TCRoofUI

/// One notification of the bell. `id` stays the same while the event does, so "read" survives relaunches.
struct AppNotification: Identifiable {
    enum Kind: Equatable {
        case survey, install, syncPending, saved
        /// A tool due for calibration, today's daily report not sent by 17:00, and a post of the project feed.
        case calibration, report, feed(FeedPost.Kind)
        /// A manager's decision on this person's expense claim.
        case claim(approved: Bool)
    }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let date: Date
    /// The job of a survey appointment, for the iPhone row's tap action.
    var job: Job? = nil
    /// The screen the row opens, the same one its system notification does.
    var link: DeepLink? = nil
    /// Counted under `ต้องทำ`.
    var todo = false
    /// "อีก 9 ชม." for an appointment still ahead; otherwise the time (today) or date and time (earlier).
    var timeText: String {
        if kind == .survey, date > .now {
            let mins = Int(date.timeIntervalSinceNow / 60)
            return mins >= 60 ? "อีก \(mins / 60) ชม." : "อีก \(max(mins, 1)) นาที"
        }
        // a calibration row is about a day, not a time
        if kind == .calibration { return "" }
        return date.isToday ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : ThaiFormat.dayMonthTime.string(from: date)
    }
    var isToday: Bool { date.isToday || kind == .survey || kind == .install || kind == .syncPending || kind == .calibration }

    /// Today's survey appointments and install days, a daily report still owed after 17:00, tools due for calibration,
    /// the project feed's posts of today and yesterday, survey reports still waiting to sync, and Drive saves of the
    /// last 7 days. Ids are the system notifications' (`NotificationPlan.bellID`).
    @MainActor static func list(jobs: [Job], survey: SurveyModel, posts: [FeedPost] = [], tools: [Instrument] = []) -> [AppNotification] {
        let day = ISODate.string(.now)
        var out: [AppNotification] = []
        for job in jobs {
            let key = job.syncID ?? job.code
            if job.surveyDate.isToday {
                out.append(.init(id: "survey-\(key)-\(day)", kind: .survey,
                                 title: "นัดสำรวจ " + job.surveyDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)),
                                 detail: [job.code, job.projectName, job.address].filter { !$0.isEmpty }.joined(separator: " | "),
                                 date: job.surveyDate, job: job))
            }
            if let d = job.installDay(on: .now) {
                out.append(.init(id: "install-\(key)-\(day)", kind: .install, title: "ติดตั้ง Day \(d)/\(job.installDays)",
                                 detail: "\(job.code) | ทีม \(job.team.rawValue) | \(job.capacityKW.plain) kWp | จ.\(job.province)",
                                 date: Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: job.installStart),
                                                             minute: Calendar.current.component(.minute, from: job.installStart), second: 0, of: .now) ?? .now))
                if let owed = dailyReportOwed(job, key: key, day: day) { out.append(owed) }
            }
        }
        out += tools.compactMap(calibration)
        let yesterday = Date.now.startOfDay.adding(days: -1)
        out += posts.filter { $0.date >= yesterday }.map(feed)
        let pending = survey.jobsToSync
        if let latest = pending.map(\.updated).max() {
            // a new id whenever the count changes, so a fresh backlog shows as unread again
            out.append(.init(id: "sync-\(day)-\(pending.count)", kind: .syncPending, title: "รอซิงก์ \(pending.count) งาน",
                             detail: "ยังไม่ได้บันทึกขึ้นคลาวด์ | แตะเพื่อซิงก์ตอนมีสัญญาณ", date: latest))
        }
        let weekAgo = Date.now.adding(days: -7)
        for j in survey.jobs {
            guard let saved = j.drive?.lastSaved, saved > weekAgo else { continue }
            let name = [j.docNo.isEmpty ? "" : "NO.\(j.docNo)", j.projectName].filter { !$0.isEmpty }.joined(separator: " ")
            out.append(.init(id: "saved-\(j.id.uuidString)-\(saved.millis)", kind: .saved, title: "บันทึกขึ้น Drive แล้ว",
                             detail: "\(name.isEmpty ? "งานสำรวจ" : name) | \(j.photoCount) ภาพ", date: saved))
        }
        out += ClaimReviews.shared.recent.map(claim)
        return out.sorted { a, b in a.isToday != b.isToday ? a.isToday : a.date > b.date }
    }

    /// A claim decision of the last 7 days; one sent back is to do.
    @MainActor private static func claim(_ r: TravelClaim.Review) -> AppNotification {
        let plan = ClaimNotification.plan(r)
        return .init(id: plan.bellID, kind: .claim(approved: r.decision == .approved), title: plan.title,
                     detail: plan.body + " | " + plan.sub, date: Date(timeIntervalSince1970: Double(r.reviewedAt) / 1000),
                     link: .claims(month: r.month), todo: r.decision == .returned)
    }

    /// `ยังไม่ได้ส่งรายงานประจำวัน` once 17:00 has passed on a working install day whose report isn't signed.
    @MainActor private static func dailyReportOwed(_ job: Job, key: String, day: String) -> AppNotification? {
        let now = Date.now
        guard let at = RoutineReport.calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now), at <= now,
              RoutineReport.isWorkingDay(now, settings: job.routineSettings), job.dailyState(on: now) != .signed else { return nil }
        return .init(id: "report-daily-\(key)-\(day)", kind: .report, title: "ยังไม่ได้ส่งรายงานประจำวัน", detail: job.stationName, date: at,
                     link: .dailyReport(job: key), todo: true)
    }

    private static func calibration(_ tool: Instrument) -> AppNotification? {
        let state = tool.calibration(on: .now)
        guard state.needsAction, let due = tool.calibrationDue else { return nil }
        var overdue = false
        if case .overdue = state { overdue = true }
        return .init(id: ToolNotification.calibrationBellID(toolID: tool.id, due: due), kind: .calibration,
                     title: overdue ? "เกินกำหนดสอบเทียบ" : "ใกล้ครบกำหนดสอบเทียบ",
                     detail: [tool.name, tool.kind].filter { !$0.isEmpty }.joined(separator: " ") + " | " + state.title,
                     date: Date.now.startOfDay, link: .toolRecord(tool: tool.id), todo: true)
    }

    private static func feed(_ post: FeedPost) -> AppNotification {
        let fixed = post.issue?.fixed == true
        let type = FeedNotification.type(post.kind)
        return .init(id: post.id, kind: .feed(post.kind), title: fixed ? "ปัญหา | แก้แล้ว" : FeedNotification.title(post.kind),
                     detail: post.kind == .summary ? post.text : post.place + " | " + post.text, date: post.date,
                     link: DeepLink.route(type: type, action: nil, info: FeedNotification.plan(post).info),
                     todo: (post.issue != nil && !fixed) || post.kind == .waitingInspector)
    }
}

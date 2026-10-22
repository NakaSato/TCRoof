import Foundation

// System notifications (docs/ui/tcroof-notifications-iphone): what TCRoof posts through UserNotifications.
// Plain values here; the app turns a `NotificationPlan` into a `UNNotificationRequest`.

/// One notification type, also its `UNNotificationCategory` id and thread id.
public enum NotificationType: String, CaseIterable, Sendable {
    case survey, queue, late, cal, sync, done, report
    /// Live cases (`LiveNotifications.swift`): install days, the MP plan, and the project feed's events.
    case install, mp, feed, issue, inspect
    /// A manager's decision on the person's expense claim (`ClaimNotification`).
    case claim

    /// The coloured word after `TCROOF |` on the board.
    public var category: String {
        switch self {
        case .survey: "สำรวจ"
        case .queue: "เครื่องมือ"
        case .late: "ด่วน"
        case .cal: "สอบเทียบ"
        case .sync: "ซิงก์"
        case .done: "ส่งออก"
        case .report: "รายงาน"
        case .install: "ติดตั้ง"
        case .mp: "แผน MP"
        case .feed: "ความคืบหน้า"
        case .issue: "ปัญหา"
        case .inspect: "รอผู้ตรวจ"
        case .claim: "เบิกจ่าย"
        }
    }

    public enum Level: Sendable { case passive, active, timeSensitive }
    public var level: Level {
        switch self {
        case .late: .timeSensitive
        case .survey, .queue, .report, .install, .mp, .feed, .issue, .inspect, .claim: .active
        case .cal, .sync, .done: .passive
        }
    }

    /// No sound: iOS shows no banner for a passive notification, so the feed's posts are active but quiet.
    public var silent: Bool { self == .feed }

    public var actions: [NotificationAction] {
        switch self {
        case .survey: [.navigate, .openSurvey, .remind10Minutes]
        case .queue: [.pickUp, .viewQueue, .leaveQueue]
        case .late: [.returnTool, .extendDay, .callWaiting]
        case .cal: [.toolRecord, .remind7Days]
        case .sync: [.syncNow, .viewPending]
        case .done: [.openDrive, .shareLink]
        case .install: [.navigate]
        case .report, .mp, .feed, .issue, .inspect, .claim: []
        }
    }

    public var group: NotificationGroup {
        switch self {
        case .survey: .survey
        case .queue, .late: .tools
        case .cal: .calibration
        case .sync, .done: .syncExport
        case .report: .report
        case .install, .mp: .plan
        case .feed, .issue, .inspect: .feed
        case .claim: .claim
        }
    }
}

/// A switch in Settings › การแจ้งเตือน.
public enum NotificationGroup: String, CaseIterable, Sendable {
    case survey, tools, calibration, syncExport, report, plan, feed, claim

    public var title: String {
        switch self {
        case .survey: "นัดสำรวจ"
        case .tools: "คิวและกำหนดคืนเครื่องมือ"
        case .calibration: "สอบเทียบ"
        case .syncExport: "ซิงก์และส่งออก"
        case .report: "รายงานประจำ"
        case .plan: "วันติดตั้งและแผน MP"
        case .feed: "ความคืบหน้าโครงการ"
        case .claim: "ผลอนุมัติใบเบิก"
        }
    }

    public var types: [NotificationType] { NotificationType.allCases.filter { $0.group == self } }
    /// UserDefaults key; a missing value means on.
    public var defaultsKey: String { "notifications.on.\(rawValue)" }
}

/// A long-press quick action. `rawValue` is the `UNNotificationAction` identifier.
public enum NotificationAction: String, CaseIterable, Sendable {
    case navigate, openSurvey, remind10Minutes
    case pickUp, viewQueue, leaveQueue
    case returnTool, extendDay, callWaiting
    case toolRecord, remind7Days
    case syncNow, viewPending
    case openDrive, shareLink

    public var title: String {
        switch self {
        case .navigate: "นำทาง"
        case .openSurvey: "เปิดแบบสำรวจ"
        case .remind10Minutes: "เตือนอีก 10 นาที"
        case .pickUp: "รับเครื่อง | ถ่ายภาพตอนยืม"
        case .viewQueue: "ดูคิว"
        case .leaveQueue: "สละคิว"
        case .returnTool: "คืนอุปกรณ์"
        case .extendDay: "ขอขยายเวลา 1 วัน"
        case .callWaiting: "โทรหาผู้รอคิว"
        case .toolRecord: "เปิดทะเบียนเครื่อง"
        case .remind7Days: "เตือนอีก 7 วัน"
        case .syncNow: "ซิงก์ตอนนี้"
        case .viewPending: "ดูรายการ"
        case .openDrive: "เปิดใน Drive"
        case .shareLink: "แชร์ลิงก์"
        }
    }

    /// SF Symbol from icons/README.md.
    public var symbol: String {
        switch self {
        case .navigate: "mappin.and.ellipse"
        case .openSurvey: "list.clipboard"
        case .remind10Minutes, .extendDay, .remind7Days: "clock"
        case .pickUp: "camera"
        case .viewQueue, .viewPending: "list.bullet"
        case .leaveQueue: "xmark"
        case .returnTool: "arrow.uturn.backward"
        case .callWaiting: "phone"
        case .toolRecord: "briefcase"
        case .syncNow: "arrow.triangle.2.circlepath"
        case .openDrive: "cloud"
        case .shareLink: "square.and.arrow.up"
        }
    }

    public enum Mode: Sendable { case foreground, background, destructive }
    public var mode: Mode {
        switch self {
        case .remind10Minutes, .remind7Days, .syncNow: .background
        case .leaveQueue: .destructive
        default: .foreground
        }
    }
}

/// Keys of `NotificationPlan.info` (the request's `userInfo`).
public enum NotificationInfo {
    /// The matching `AppNotification` id of the bell.
    public static let bell = "bell"
    public static let job = "job"
    public static let tool = "tool"
    public static let toolName = "toolName"
    public static let toolKind = "toolKind"
    public static let due = "due"
    public static let appointment = "appointment"
    public static let phone = "phone"
    public static let url = "url"
    /// Which routine report a `report` notification is about: "daily" or "request".
    public static let kind = "kind"
    /// The record a feed notification opens: "daily", "inspect", "test", "problem", "punch" or "summary".
    public static let record = "record"
    /// The day of that daily report (`ISO`).
    public static let day = "day"
    /// The month of a claim decision ("2026-10").
    public static let month = "month"
}

/// One local notification to post.
public struct NotificationPlan: Equatable, Sendable {
    public enum Fire: Equatable, Sendable {
        case at(Date), after(TimeInterval)
        public func date(now: Date) -> Date {
            switch self {
            case .at(let d): d
            case .after(let s): now.addingTimeInterval(s)
            }
        }
    }

    public var id: String
    public var type: NotificationType
    public var title: String
    public var body: String
    public var sub: String
    public var fire: Fire
    public var info: [String: String]

    public init(id: String, type: NotificationType, title: String, body: String, sub: String, fire: Fire, info: [String: String] = [:]) {
        self.id = id; self.type = type; self.title = title; self.body = body; self.sub = sub; self.fire = fire
        self.info = info.merging([NotificationInfo.bell: id]) { old, _ in old }
    }

    /// `content.body`: the body, then the sub line.
    public var text: String { sub.isEmpty ? body : body + "\n" + sub }
    public var bellID: String { info[NotificationInfo.bell] ?? id }

    public func fireDate(now: Date) -> Date { fire.date(now: now) }
}

// MARK: - Survey | sync | Drive

public extension NotificationPlan {
    /// The reminder before an appointment (docs/specs/calendar-travel-expenses-swift.md §A3: 1 hour).
    static let surveyLead: TimeInterval = 60 * 60
    static let syncPendingID = "sync-pending"

    /// Id of a survey appointment, the same as the bell's: `survey-<jobKey>-<yyyy-MM-dd>`.
    static func surveyID(jobKey: String, appointment: Date) -> String { "survey-\(jobKey)-\(ISODate.string(appointment))" }

    /// `นัดสำรวจในอีก 1 ชั่วโมง` at `fireAt` (appointment − 1 h, or later after `เตือนอีก 10 นาที`).
    static func survey(jobKey: String, name: String, area: String, appointment: Date, fireAt: Date? = nil) -> NotificationPlan {
        let at = fireAt ?? appointment.addingTimeInterval(-surveyLead)
        return NotificationPlan(id: surveyID(jobKey: jobKey, appointment: appointment), type: .survey,
                                title: surveyTitle(minutes: Int((appointment.timeIntervalSince(at) / 60).rounded())), body: name,
                                sub: [area, ThaiDate.time(appointment)].filter { !$0.isEmpty }.joined(separator: " | "),
                                fire: .at(at), info: [NotificationInfo.job: jobKey, NotificationInfo.appointment: ISO.string(appointment)])
    }

    static func surveyTitle(minutes: Int) -> String {
        if minutes <= 0 { return "ถึงเวลานัดสำรวจ" }
        if minutes % 60 == 0 { return "นัดสำรวจในอีก \(minutes / 60) ชั่วโมง" }
        return "นัดสำรวจในอีก \(minutes) นาที"
    }

    /// The evening before an appointment, 17:00 (§A3): `พรุ่งนี้ 09:00 นัดสำรวจ`, or `พรุ่งนี้ นัดสำรวจ` for a day with no
    /// time. Its own id (`…-eve`), in the bell as the appointment.
    static func surveyEve(jobKey: String, name: String, area: String, appointment: Date, calendar cal: Calendar = .current) -> NotificationPlan {
        let day = cal.startOfDay(for: appointment)
        let eve = cal.date(bySettingHour: 17, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: day)!)!
        let id = surveyID(jobKey: jobKey, appointment: appointment)
        let time = isAllDay(appointment, calendar: cal) ? "" : " " + ThaiDate.time(appointment)
        return NotificationPlan(id: id + "-eve", type: .survey, title: "พรุ่งนี้\(time) นัดสำรวจ", body: name, sub: area,
                                fire: .at(eve), info: [NotificationInfo.job: jobKey, NotificationInfo.appointment: ISO.string(appointment),
                                                       NotificationInfo.bell: id])
    }

    /// An appointment at 00:00 is a day with no time: no reminder an hour before it.
    static func isAllDay(_ appointment: Date, calendar cal: Calendar = .current) -> Bool {
        let t = cal.dateComponents([.hour, .minute], from: appointment)
        return (t.hour ?? 0) == 0 && (t.minute ?? 0) == 0
    }

    /// The one `รอซิงก์ n งาน`: two hours after the oldest change; once that has passed and been shown, 20:00.
    /// `names` are "NO.224"-style labels of the waiting reports.
    static func syncPending(names: [String], oldest: Date, now: Date, alreadyShown: Bool) -> NotificationPlan {
        let due = oldest.addingTimeInterval(2 * 3600)
        let fire: Fire
        if due > now { fire = .at(due) }
        else if !alreadyShown { fire = .after(1) }
        else { fire = .at(nextEvening(after: now)) }
        let shown = names.prefix(3).joined(separator: " | ") + (names.count > 3 ? " +\(names.count - 3)" : "")
        let day = ISODate.string(fire.date(now: now))
        return NotificationPlan(id: syncPendingID, type: .sync, title: "รอซิงก์ \(names.count) งาน", body: "ยังไม่ได้บันทึกขึ้น Google Drive",
                                sub: [shown, "จะซิงก์เองเมื่อมีสัญญาณ"].filter { !$0.isEmpty }.joined(separator: " | "), fire: fire,
                                // the bell's id for this backlog on the day it shows
                                info: [NotificationInfo.bell: "sync-\(day)-\(names.count)"])
    }

    static func nextEvening(after now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        return today > now ? today : cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Id of a Drive save, the same as the bell's: `saved-<report id>-<ms>`.
    static func savedID(report: UUID, savedAt: Date) -> String {
        "saved-\(report.uuidString)-\(Int64((savedAt.timeIntervalSince1970 * 1000).rounded()))"
    }

    /// `บันทึกขึ้น Drive แล้ว`. `files` are "PDF", "Excel", "รูป"…; `folder` is "TCRoof/2569/NO.224".
    static func driveSaved(report: UUID, savedAt: Date, name: String, files: [String], folder: String, url: String?) -> NotificationPlan {
        let body = [name, "แบบสำรวจ"].filter { !$0.isEmpty }.joined(separator: " ") + " | \(files.count) ไฟล์ (\(files.joined(separator: " | ")))"
        return NotificationPlan(id: savedID(report: report, savedAt: savedAt), type: .done, title: "บันทึกขึ้น Drive แล้ว",
                                body: body, sub: "โฟลเดอร์ \(folder)", fire: .after(1),
                                info: url.map { [NotificationInfo.url: $0] } ?? [:])
    }
}

// MARK: - Routine reports

/// The two routine-report reminders (docs/specs/routine-reports-swift.md §5).
public enum RoutineReportNotification {
    /// `ยังไม่ได้ส่งรายงานประจำวัน <สถานี>` at 17:00 today, when today is a working day and today's report isn't signed.
    public static func daily(jobKey: String, station: String, now: Date, isWorkingDay: Bool, signed: Bool,
                             calendar cal: Calendar = Calendar.current) -> NotificationPlan? {
        guard isWorkingDay, !signed, let at = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now), at > now else { return nil }
        return NotificationPlan(id: "report-daily-\(jobKey)-\(ISODate.string(at))", type: .report,
                                title: "ยังไม่ได้ส่งรายงานประจำวัน", body: station, sub: "แตะเพื่อทำรายงานวันนี้", fire: .at(at),
                                info: [NotificationInfo.job: jobKey, NotificationInfo.kind: "daily"])
    }

    /// `ยังไม่มีคำขอปฏิบัติงานสัปดาห์หน้า` at 15:00 on this week's Friday, when next week has no request yet.
    public static func request(jobKey: String, station: String, now: Date, hasNextWeek: Bool,
                               calendar cal: Calendar = Calendar.current) -> NotificationPlan? {
        guard !hasNextWeek else { return nil }
        let weekday = cal.component(.weekday, from: now)
        guard let friday = cal.date(byAdding: .day, value: (6 - weekday + 7) % 7, to: now),
              let at = cal.date(bySettingHour: 15, minute: 0, second: 0, of: friday), at > now else { return nil }
        return NotificationPlan(id: "report-request-\(jobKey)-\(ISODate.string(at))", type: .report,
                                title: "ยังไม่มีคำขอปฏิบัติงานสัปดาห์หน้า", body: station, sub: "แตะเพื่อร่างคำขอจากแผน MP", fire: .at(at),
                                info: [NotificationInfo.job: jobKey, NotificationInfo.kind: "request"])
    }
}

// MARK: - Tools (API only until the app has a tools / loan model)

/// Queue, overdue and calibration notifications for borrowed tools. Nothing in the app calls these yet:
/// they wait for the tools feature (`AppModule.tools`).
public enum ToolNotification {
    /// `ถึงคิวคุณ | DJI Mavic 3T`, right away, when the tool you queued for is returned.
    public static func notifyQueueReached(toolID: String, tool: String, from: String, place: String,
                                          job: String, until: Date, waitingPhone: String? = nil) -> NotificationPlan {
        NotificationPlan(id: "queue-\(toolID)", type: .queue, title: "ถึงคิวคุณ | \(tool)",
                         body: "\(from)คืนเครื่องและส่งต่อให้คุณ รับได้ที่\(place)",
                         sub: "งาน \(job) | ใช้ได้ถึง \(ThaiDate.dayMonth(until))", fire: .after(1),
                         info: [NotificationInfo.tool: toolID, NotificationInfo.toolName: tool])
    }

    /// `เกินกำหนดคืน | Fluke 376 FC` at 08:00 on each of the next `days` days the tool is past `due`.
    public static func notifyOverdue(toolID: String, tool: String, due: Date, waiting: String? = nil, waitingFrom: Date? = nil,
                                     waitingPhone: String? = nil, now: Date, days: Int = 7) -> [NotificationPlan] {
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let first = cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let plans = (0...days).compactMap { i -> NotificationPlan? in
            guard let at = cal.date(byAdding: .day, value: i, to: first), at > now else { return nil }
            let late = cal.dateComponents([.day], from: dueDay, to: cal.startOfDay(for: at)).day ?? 0
            guard late >= 1 else { return nil }
            var body = "เกิน \(late) วัน (กำหนด \(ThaiDate.dayMonth(due)))"
            if let waiting, !waiting.isEmpty {
                body += " | \(waiting)รอใช้ต่อ" + (waitingFrom.map { " " + ThaiDate.dayMonth($0) } ?? "")
            }
            var info = [NotificationInfo.tool: toolID, NotificationInfo.toolName: tool]
            if let waitingPhone { info[NotificationInfo.phone] = waitingPhone }
            return NotificationPlan(id: "late-\(toolID)-\(ISODate.string(at))", type: .late, title: "เกินกำหนดคืน | \(tool)",
                                    body: body, sub: "แตะเพื่อคืนพร้อมถ่ายภาพ 3 ภาพ", fire: .at(at), info: info)
        }
        return Array(plans.prefix(days))
    }

    /// `ใกล้ครบกำหนดสอบเทียบ` at 09:00, 30 and 7 days before `due` (those still ahead).
    public static func scheduleCalibration(toolID: String, tool: String, kind: String, due: Date, now: Date) -> [NotificationPlan] {
        [30, 7].compactMap { left in
            guard let day = Calendar.current.date(byAdding: .day, value: -left, to: due),
                  let at = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day), at > now else { return nil }
            return calibration(toolID: toolID, tool: tool, kind: kind, due: due, at: at)
        }
    }

    /// One calibration reminder firing at `at`; also what `เตือนอีก 7 วัน` posts.
    public static func calibration(toolID: String, tool: String, kind: String, due: Date, at: Date) -> NotificationPlan {
        let cal = Calendar.current
        let left = cal.dateComponents([.day], from: cal.startOfDay(for: at), to: cal.startOfDay(for: due)).day ?? 0
        return NotificationPlan(id: "cal-\(toolID)-\(ISODate.string(at))", type: .cal, title: "ใกล้ครบกำหนดสอบเทียบ",
                                body: [tool, kind].filter { !$0.isEmpty }.joined(separator: " ") + " | ครบ \(ThaiDate.full(due))",
                                sub: "เหลือ \(left) วัน | จองส่งสอบเทียบล่วงหน้า", fire: .at(at),
                                info: [NotificationInfo.tool: toolID, NotificationInfo.toolName: tool,
                                       NotificationInfo.toolKind: kind, NotificationInfo.due: ISO.string(due),
                                       NotificationInfo.bell: calibrationBellID(toolID: toolID, due: due)])
    }

    /// The bell's one row for a tool's calibration date, whichever reminder is on screen.
    public static func calibrationBellID(toolID: String, due: Date) -> String { "cal-\(toolID)-\(ISODate.string(due))" }
}

// MARK: - Deep links

/// Where a tap or quick action on a notification takes the app.
public enum DeepLink: Equatable, Sendable {
    public enum CameraMode: Sendable { case borrow, giveBack }

    /// Open the appointment's report at its next step (or start one).
    case survey(job: String)
    /// Apple Maps to the report's A1 GPS.
    case navigate(job: String)
    /// Post the same notification again later (background).
    case remindLater(TimeInterval)
    case toolCamera(tool: String, CameraMode)
    case toolQueue(tool: String)
    /// Confirmed in the app before leaving.
    case leaveQueue(tool: String)
    case extendLoan(tool: String)
    case call(phone: String)
    case toolRecord(tool: String)
    /// Push to the cloud now (background).
    case syncNow
    case pendingList
    case driveFolder(URL)
    case share(URL)
    /// Today's daily report of a station (docs/specs/routine-reports-swift.md §5).
    case dailyReport(job: String)
    /// Next week's request of a station.
    case weeklyRequest(job: String)
    /// The job's detail (an install day, the MP plan, an issue, work waiting for the inspector).
    case job(job: String)
    /// A station's daily report of one day.
    case daily(job: String, day: Date)
    /// The job's ICL check list.
    case inspection(job: String)
    /// A home job's punch list.
    case homework(job: String)
    /// The install records, where the daily summary leads.
    case records
    /// เดินทางและเบิกค่าใช้จ่าย on a month ("2026-10"), where a claim decision leads.
    case claims(month: String)
    case home

    /// The link for a tap (`action` nil or the system default / dismiss id) or a quick action.
    public static func route(type: NotificationType, action: String?, info: [String: String]) -> DeepLink {
        let job = info[NotificationInfo.job] ?? ""
        let tool = info[NotificationInfo.tool] ?? ""
        let url = info[NotificationInfo.url].flatMap(URL.init(string:))
        guard let action = action.flatMap(NotificationAction.init(rawValue:)) else {
            switch type {
            case .survey: return job.isEmpty ? .home : .survey(job: job)
            case .queue: return .toolQueue(tool: tool)
            case .late: return .toolCamera(tool: tool, .giveBack)
            case .cal: return .toolRecord(tool: tool)
            case .sync: return .pendingList
            case .done: return url.map(DeepLink.driveFolder) ?? .home
            case .report: return job.isEmpty ? .home : info[NotificationInfo.kind] == "request" ? .weeklyRequest(job: job) : .dailyReport(job: job)
            case .install, .mp: return job.isEmpty ? .home : .job(job: job)
            case .feed, .issue, .inspect: return FeedNotification.link(info)
            case .claim: return ClaimNotification.link(info)
            }
        }
        switch action {
        case .navigate: return .navigate(job: job)
        case .openSurvey: return .survey(job: job)
        case .remind10Minutes: return .remindLater(10 * 60)
        case .pickUp: return .toolCamera(tool: tool, .borrow)
        case .viewQueue: return .toolQueue(tool: tool)
        case .leaveQueue: return .leaveQueue(tool: tool)
        case .returnTool: return .toolCamera(tool: tool, .giveBack)
        case .extendDay: return .extendLoan(tool: tool)
        case .callWaiting: return info[NotificationInfo.phone].map { .call(phone: $0) } ?? .toolQueue(tool: tool)
        case .toolRecord: return .toolRecord(tool: tool)
        case .remind7Days: return .remindLater(7 * 86_400)
        case .syncNow: return .syncNow
        case .viewPending: return .pendingList
        case .openDrive: return url.map(DeepLink.driveFolder) ?? .home
        case .shareLink: return url.map(DeepLink.share) ?? .home
        }
    }
}

// MARK: - Formatting

/// Buddhist-calendar dates for notification text ("29/9", "20/12/2569", "10:30").
enum ThaiDate {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.calendar = Calendar(identifier: .buddhist)
        f.dateFormat = format
        return f
    }
    private static let dm = make("d/M"), dmy = make("d/M/yyyy"), hm = make("HH:mm")
    static func dayMonth(_ d: Date) -> String { dm.string(from: d) }
    static func full(_ d: Date) -> String { dmy.string(from: d) }
    static func time(_ d: Date) -> String { hm.string(from: d) }
}

/// Round-trip dates in `userInfo`.
public enum ISO {
    private static let f: ISO8601DateFormatter = ISO8601DateFormatter()
    public static func string(_ d: Date) -> String { f.string(from: d) }
    public static func date(_ s: String?) -> Date? { s.flatMap(f.date(from:)) }
}

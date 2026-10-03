import Foundation

// System notifications (docs/ui/tcroof-notifications-iphone): what TCRoof posts through UserNotifications.
// Plain values here; the app turns a `NotificationPlan` into a `UNNotificationRequest`.

/// One notification type, also its `UNNotificationCategory` id and thread id.
public enum NotificationType: String, CaseIterable, Sendable {
    case survey, queue, late, cal, sync, done

    /// The coloured word after `TCROOF ·` on the board.
    public var category: String {
        switch self {
        case .survey: "สำรวจ"
        case .queue: "เครื่องมือ"
        case .late: "ด่วน"
        case .cal: "สอบเทียบ"
        case .sync: "ซิงก์"
        case .done: "ส่งออก"
        }
    }

    public enum Level: Sendable { case passive, active, timeSensitive }
    public var level: Level {
        switch self {
        case .late: .timeSensitive
        case .survey, .queue: .active
        case .cal, .sync, .done: .passive
        }
    }

    public var actions: [NotificationAction] {
        switch self {
        case .survey: [.navigate, .openSurvey, .remind10Minutes]
        case .queue: [.pickUp, .viewQueue, .leaveQueue]
        case .late: [.returnTool, .extendDay, .callWaiting]
        case .cal: [.toolRecord, .remind7Days]
        case .sync: [.syncNow, .viewPending]
        case .done: [.openDrive, .shareLink]
        }
    }

    public var group: NotificationGroup {
        switch self {
        case .survey: .survey
        case .queue, .late: .tools
        case .cal: .calibration
        case .sync, .done: .syncExport
        }
    }
}

/// A switch in Settings › การแจ้งเตือน.
public enum NotificationGroup: String, CaseIterable, Sendable {
    case survey, tools, calibration, syncExport

    public var title: String {
        switch self {
        case .survey: "นัดสำรวจ"
        case .tools: "คิวและกำหนดคืนเครื่องมือ"
        case .calibration: "สอบเทียบ"
        case .syncExport: "ซิงก์และส่งออก"
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
        case .pickUp: "รับเครื่อง · ถ่ายภาพตอนยืม"
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

// MARK: - Survey · sync · Drive

public extension NotificationPlan {
    static let surveyLead: TimeInterval = 30 * 60
    static let syncPendingID = "sync-pending"

    /// Id of a survey appointment, the same as the bell's: `survey-<jobKey>-<yyyy-MM-dd>`.
    static func surveyID(jobKey: String, appointment: Date) -> String { "survey-\(jobKey)-\(ISODate.string(appointment))" }

    /// `นัดสำรวจในอีก 30 นาที` at `fireAt` (appointment − 30 min, or later after `เตือนอีก 10 นาที`).
    static func survey(jobKey: String, name: String, area: String, appointment: Date, fireAt: Date? = nil) -> NotificationPlan {
        let at = fireAt ?? appointment.addingTimeInterval(-surveyLead)
        return NotificationPlan(id: surveyID(jobKey: jobKey, appointment: appointment), type: .survey,
                                title: surveyTitle(minutes: Int((appointment.timeIntervalSince(at) / 60).rounded())), body: name,
                                sub: [area, ThaiDate.time(appointment)].filter { !$0.isEmpty }.joined(separator: " · "),
                                fire: .at(at), info: [NotificationInfo.job: jobKey, NotificationInfo.appointment: ISO.string(appointment)])
    }

    static func surveyTitle(minutes: Int) -> String { minutes > 0 ? "นัดสำรวจในอีก \(minutes) นาที" : "ถึงเวลานัดสำรวจ" }

    /// The one `รอซิงก์ n งาน`: two hours after the oldest change; once that has passed and been shown, 20:00.
    /// `names` are "NO.224"-style labels of the waiting reports.
    static func syncPending(names: [String], oldest: Date, now: Date, alreadyShown: Bool) -> NotificationPlan {
        let due = oldest.addingTimeInterval(2 * 3600)
        let fire: Fire
        if due > now { fire = .at(due) }
        else if !alreadyShown { fire = .after(1) }
        else { fire = .at(nextEvening(after: now)) }
        let shown = names.prefix(3).joined(separator: " · ") + (names.count > 3 ? " +\(names.count - 3)" : "")
        let day = ISODate.string(fire.date(now: now))
        return NotificationPlan(id: syncPendingID, type: .sync, title: "รอซิงก์ \(names.count) งาน", body: "ยังไม่ได้บันทึกขึ้น Google Drive",
                                sub: [shown, "จะซิงก์เองเมื่อมีสัญญาณ"].filter { !$0.isEmpty }.joined(separator: " · "), fire: fire,
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
        let body = [name, "แบบสำรวจ"].filter { !$0.isEmpty }.joined(separator: " ") + " · \(files.count) ไฟล์ (\(files.joined(separator: " · ")))"
        return NotificationPlan(id: savedID(report: report, savedAt: savedAt), type: .done, title: "บันทึกขึ้น Drive แล้ว",
                                body: body, sub: "โฟลเดอร์ \(folder)", fire: .after(1),
                                info: url.map { [NotificationInfo.url: $0] } ?? [:])
    }
}

// MARK: - Tools (API only until the app has a tools / loan model)

/// Queue, overdue and calibration notifications for borrowed tools. Nothing in the app calls these yet:
/// they wait for the tools feature (`AppModule.tools`).
public enum ToolNotification {
    /// `ถึงคิวคุณ · DJI Mavic 3T`, right away, when the tool you queued for is returned.
    public static func notifyQueueReached(toolID: String, tool: String, from: String, place: String,
                                          job: String, until: Date, waitingPhone: String? = nil) -> NotificationPlan {
        NotificationPlan(id: "queue-\(toolID)", type: .queue, title: "ถึงคิวคุณ · \(tool)",
                         body: "\(from)คืนเครื่องและส่งต่อให้คุณ รับได้ที่\(place)",
                         sub: "งาน \(job) · ใช้ได้ถึง \(ThaiDate.dayMonth(until))", fire: .after(1),
                         info: [NotificationInfo.tool: toolID, NotificationInfo.toolName: tool])
    }

    /// `เกินกำหนดคืน · Fluke 376 FC` at 08:00 on each of the next `days` days the tool is past `due`.
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
                body += " · \(waiting)รอใช้ต่อ" + (waitingFrom.map { " " + ThaiDate.dayMonth($0) } ?? "")
            }
            var info = [NotificationInfo.tool: toolID, NotificationInfo.toolName: tool]
            if let waitingPhone { info[NotificationInfo.phone] = waitingPhone }
            return NotificationPlan(id: "late-\(toolID)-\(ISODate.string(at))", type: .late, title: "เกินกำหนดคืน · \(tool)",
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
                                body: [tool, kind].filter { !$0.isEmpty }.joined(separator: " ") + " · ครบ \(ThaiDate.full(due))",
                                sub: "เหลือ \(left) วัน · จองส่งสอบเทียบล่วงหน้า", fire: .at(at),
                                info: [NotificationInfo.tool: toolID, NotificationInfo.toolName: tool,
                                       NotificationInfo.toolKind: kind, NotificationInfo.due: ISO.string(due)])
    }
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

import SwiftUI
import UIKit
import UserNotifications
import TCRoofCore
import TCRoofUI

/// System notifications (docs/ui/tcroof-notifications-iphone): categories with quick actions, posting and
/// cancelling `NotificationPlan`s, the badge, and taps routed to a `DeepLink` that `HomeView` opens.
/// Request ids are the bell's `AppNotification` ids, so reading one side marks the other read.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// The last tap or quick action still to open; `HomeView` clears it.
    var link: DeepLink?
    /// Title of the quick action behind `link`, for the tools screen's note.
    private(set) var linkAction: String?
    private(set) var authorization = UNAuthorizationStatus.notDetermined

    /// Pushes to the cloud; set once `CloudSync` has started.
    @ObservationIgnored var syncNow: (() -> Void)?

    private var center: UNUserNotificationCenter { .current() }
    private static let readKey = "notifications.read"
    private static let syncNowKey = "notifications.syncNowPending"
    private static let syncCountKey = "notifications.sync.count"
    private static let syncFireKey = "notifications.sync.fire"
    /// `userInfo` mark of a reminder the user put off.
    private static let snoozedKey = "snoozed"

    /// Called at launch, before any notification response can arrive.
    func configure() {
        center.delegate = self
        center.setNotificationCategories(Set(NotificationType.allCases.map(Self.category)))
    }

    private static func category(_ type: NotificationType) -> UNNotificationCategory {
        let actions = type.actions.map { a in
            let options: UNNotificationActionOptions = switch a.mode {
            case .foreground: [.foreground]
            case .destructive: [.destructive, .foreground]
            case .background: []
            }
            return UNNotificationAction(identifier: a.rawValue, title: a.title, options: options,
                                        icon: UNNotificationActionIcon(systemImageName: a.symbol))
        }
        return UNNotificationCategory(identifier: type.rawValue, actions: actions, intentIdentifiers: [], options: [])
    }

    // MARK: permission and settings

    /// Asks once (iOS shows the prompt only the first time). Time Sensitive needs the capability, which the
    /// app doesn't have yet, so `late` falls back to an ordinary alert.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    static func isOn(_ group: NotificationGroup) -> Bool {
        UserDefaults.standard.object(forKey: group.defaultsKey) as? Bool ?? true
    }

    /// A group was switched off: drop what it has waiting and on screen.
    func groupChanged(_ group: NotificationGroup) async {
        guard !Self.isOn(group) else { return }
        let types = Set(group.types.map(\.rawValue))
        let pending = await center.pendingNotificationRequests().filter { types.contains($0.content.categoryIdentifier) }.map(\.identifier)
        let shown = await center.deliveredNotifications().filter { types.contains($0.request.content.categoryIdentifier) }.map(\.request.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        center.removeDeliveredNotifications(withIdentifiers: shown)
        if group == .syncExport { UserDefaults.standard.removeObject(forKey: Self.syncCountKey) }
    }

    // MARK: posting

    func post(_ plan: NotificationPlan) {
        guard Self.isOn(plan.type.group) else { return }
        center.add(UNNotificationRequest(identifier: plan.id, content: Self.content(plan), trigger: Self.trigger(plan.fireDate(now: .now))))
    }

    private static func content(_ plan: NotificationPlan) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = plan.title
        c.body = plan.text
        c.threadIdentifier = plan.type.rawValue
        c.categoryIdentifier = plan.type.rawValue
        c.userInfo = plan.info
        switch plan.type.level {
        case .passive: c.interruptionLevel = .passive
        case .active: c.interruptionLevel = .active; c.sound = plan.type.silent ? nil : .default
        case .timeSensitive: c.interruptionLevel = .timeSensitive; c.sound = .default
        }
        return c
    }

    private static func trigger(_ date: Date) -> UNNotificationTrigger {
        let wait = date.timeIntervalSinceNow
        guard wait > 60 else { return UNTimeIntervalNotificationTrigger(timeInterval: max(wait, 1), repeats: false) }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    /// Replaces every waiting survey reminder with `plans` (today's and tomorrow's appointments).
    func scheduleSurveys(_ plans: [NotificationPlan]) async {
        let plans = Self.isOn(.survey) ? plans : []
        let keep = Set(plans.map(\.id))
        let stale = await center.pendingNotificationRequests()
            .filter { $0.content.categoryIdentifier == NotificationType.survey.rawValue && !keep.contains($0.identifier) }
        center.removePendingNotificationRequests(withIdentifiers: stale.map(\.identifier))
        plans.forEach(post)
    }

    /// Replaces every waiting notification of `type` with `plans` (the routine-report reminders, calibration, install
    /// days, the MP plan, the feed's summary and due issues). A reminder put off with `เตือนอีก 7 วัน` stays.
    func schedule(_ plans: [NotificationPlan], type: NotificationType) async {
        let plans = Self.isOn(type.group) ? plans : []
        let keep = Set(plans.map(\.id))
        let stale = await center.pendingNotificationRequests()
            .filter { $0.content.categoryIdentifier == type.rawValue && !keep.contains($0.identifier) && $0.content.userInfo[Self.snoozedKey] == nil }
        center.removePendingNotificationRequests(withIdentifiers: stale.map(\.identifier))
        plans.forEach(post)
    }

    /// Keeps the one `sync-pending` in step with the reports waiting to sync; `names` are "NO.224"-style labels.
    func updateSync(names: [String], oldest: Date?) async {
        let defaults = UserDefaults.standard
        guard let oldest, !names.isEmpty, Self.isOn(.syncExport) else {
            center.removePendingNotificationRequests(withIdentifiers: [NotificationPlan.syncPendingID])
            center.removeDeliveredNotifications(withIdentifiers: [NotificationPlan.syncPendingID])
            defaults.removeObject(forKey: Self.syncCountKey)
            return
        }
        let lastFire = defaults.object(forKey: Self.syncFireKey) as? Date
        let sameCount = defaults.integer(forKey: Self.syncCountKey) == names.count
        let waiting = await center.pendingNotificationRequests().contains { $0.identifier == NotificationPlan.syncPendingID }
        if sameCount && waiting { return }
        let plan = NotificationPlan.syncPending(names: names, oldest: oldest, now: .now,
                                                alreadyShown: sameCount && (lastFire.map { $0 <= .now } ?? false))
        post(plan)
        defaults.set(names.count, forKey: Self.syncCountKey)
        defaults.set(plan.fireDate(now: .now), forKey: Self.syncFireKey)
    }

    /// `บันทึกขึ้น Drive แล้ว`, only while the app isn't on screen. `kinds` are `DriveSync.Kind` raw values.
    func driveSaved(_ job: TCRoofCore.Job, kinds: [String], photos: Bool, root: String) {
        guard UIApplication.shared.applicationState != .active, let saved = job.drive?.lastSaved else { return }
        let name = job.docNo.isEmpty ? job.projectName : "NO.\(job.docNo)"
        let labels = ["pdf": "PDF", "xlsx": "Excel", "json": "ข้อมูล"]
        let files = kinds.compactMap { labels[$0] } + (photos ? ["รูป"] : [])
        post(.driveSaved(report: job.id, savedAt: saved, name: name, files: files,
                         folder: [root, job.drive?.folderName].compactMap { $0 }.joined(separator: "/"), url: job.drive?.folderURL))
    }

    // MARK: badge and read state

    func setBadge(_ count: Int) { center.setBadgeCount(count) }

    /// The bell marked these read: take their system notifications off the screen too.
    func bellRead(_ ids: Set<String>) {
        Task {
            let shown = await center.deliveredNotifications()
                .filter { ($0.request.content.userInfo[NotificationInfo.bell] as? String).map(ids.contains) ?? false }
            center.removeDeliveredNotifications(withIdentifiers: shown.map(\.request.identifier))
        }
    }

    /// A system notification was opened: mark its bell row read.
    private static func markBellRead(_ id: String) {
        let d = UserDefaults.standard
        var read = Set((d.string(forKey: readKey) ?? "").split(separator: "\n").map(String.init))
        read.insert(id)
        d.set(read.sorted().joined(separator: "\n"), forKey: readKey)
    }

    // MARK: delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let info = request.content.userInfo.compactMapValues { $0 as? String }.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = $1.value }
        let action = response.actionIdentifier
        let category = request.content.categoryIdentifier
        let content = request.content
        await MainActor.run { handle(id: request.identifier, category: category, action: action, info: info, content: content) }
    }

    private func handle(id: String, category: String, action: String, info: [String: String], content: UNNotificationContent) {
        guard action != UNNotificationDismissActionIdentifier, let type = NotificationType(rawValue: category) else { return }
        let link = DeepLink.route(type: type, action: action, info: info)
        switch link {
        case .remindLater(let wait):
            snooze(id: id, type: type, info: info, content: content, after: wait)
        case .syncNow:
            Self.markBellRead(info[NotificationInfo.bell] ?? id)
            // launched in the background, sync hasn't started yet: push once it has
            if let syncNow { syncNow() } else { UserDefaults.standard.set(true, forKey: Self.syncNowKey) }
        default:
            Self.markBellRead(info[NotificationInfo.bell] ?? id)
            linkAction = NotificationAction(rawValue: action)?.title
            self.link = link
        }
    }

    /// `ซิงก์ตอนนี้` that arrived before sync started.
    func takePendingSyncNow() -> Bool {
        defer { UserDefaults.standard.removeObject(forKey: Self.syncNowKey) }
        return UserDefaults.standard.bool(forKey: Self.syncNowKey)
    }

    /// `เตือนอีก 10 นาที` / `เตือนอีก 7 วัน`: the same notification again, its countdown updated.
    private func snooze(id: String, type: NotificationType, info: [String: String], content: UNNotificationContent, after wait: TimeInterval) {
        let at = Date.now.addingTimeInterval(wait)
        if type == .cal, let due = ISO.date(info[NotificationInfo.due]) {
            var plan = ToolNotification.calibration(toolID: info[NotificationInfo.tool] ?? "", tool: info[NotificationInfo.toolName] ?? "",
                                                    kind: info[NotificationInfo.toolKind] ?? "", due: due, at: at)
            plan.info[Self.snoozedKey] = "1"
            return post(plan)
        }
        guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        if type == .survey, let appointment = ISO.date(info[NotificationInfo.appointment]) {
            copy.title = NotificationPlan.surveyTitle(minutes: Int((appointment.timeIntervalSince(at) / 60).rounded()))
        }
        center.add(UNNotificationRequest(identifier: id, content: copy, trigger: Self.trigger(at)))
    }
}

/// The system share sheet, for `แชร์ลิงก์`.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#if DEBUG
/// Simulator checks without touch input:
/// - `-notifDemo survey` moves the first sample job's appointment 31 min ahead (its reminder fires in 1 min);
/// - `-notifDemo all` posts the board's six examples a few seconds apart (lock screen / banners);
/// - `-notifDemo live` posts one example of each live case 8 s apart (install eve and day, MP start, report sent,
///   waiting for the inspector, new issue, daily summary) about the first job, so a tap opens its screens; with
///   `-notifOnly <0-6>` just that one;
/// - `-notifAction <type>.<action>` replays a tap (`survey.default`) or quick action (`survey.navigate`).
extension NotificationService {
    static var demo: String? { UserDefaults.standard.string(forKey: "notifDemo") }

    func postBoardExamples() {
        let now = Date.now
        let soon = { (s: TimeInterval) in NotificationPlan.Fire.after(s) }
        var plans: [NotificationPlan] = [
            NotificationPlan(id: "demo-done", type: .done, title: "บันทึกขึ้น Drive แล้ว",
                             body: "NO.224 แบบสำรวจ · 4 ไฟล์ (PDF · Excel · CAD · รูป)", sub: "โฟลเดอร์ TCRoof/2569/NO.224", fire: soon(2),
                             info: [NotificationInfo.url: "https://drive.google.com/drive/folders/demo"]),
            NotificationPlan(id: "demo-sync", type: .sync, title: "รอซิงก์ 2 งาน", body: "ยังไม่ได้บันทึกขึ้น Google Drive",
                             sub: "NO.224 · NO.221 · จะซิงก์เองเมื่อมีสัญญาณ", fire: soon(3)),
            ToolNotification.calibration(toolID: "fluke1587", tool: "Fluke 1587 FC", kind: "เครื่องวัดฉนวน",
                                         due: now.adding(days: 30), at: now.addingTimeInterval(4)),
            NotificationPlan(id: "demo-survey", type: .survey, title: "นัดสำรวจในอีก 1 ชั่วโมง", body: "NO.224 กปภ. สาขาตัวอย่าง สถานีผลิตน้ำ 1",
                             sub: "ต.หนองบัว อ.เมือง · 10:30", fire: soon(5)),
            ToolNotification.notifyQueueReached(toolID: "mavic3t", tool: "DJI Mavic 3T", from: "สมชาย", place: "ห้องเก็บเครื่องมือ",
                                                job: "NO.230", until: now.adding(days: 5)),
        ]
        plans[4].fire = soon(6)
        if var late = ToolNotification.notifyOverdue(toolID: "fluke376", tool: "Fluke 376 FC", due: now.adding(days: -2), waiting: "สมชาย",
                                                     waitingFrom: now.adding(days: 1), waitingPhone: "0812345678", now: now.adding(days: -1)).first {
            late.fire = soon(7)
            plans.append(late)
        }
        plans.forEach(post)
    }

    func postLiveExamples(job: String = "demo", only: Int? = nil) {
        let now = Date.now, cal = Calendar.current
        let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: now.adding(days: 1)) ?? now
        func post(_ id: String, _ kind: FeedPost.Kind, _ place: String, _ text: String, _ source: FeedPost.Source) -> NotificationPlan {
            FeedNotification.plan(FeedPost(id: id, kind: kind, project: .pwa, initials: "TC", who: "", place: place, date: now, text: text, source: source))
        }
        var plans = [
            InstallNotification.eve(jobKey: job, name: "TC-0012 บ้านตัวอย่าง", team: "TCR01", days: 5, start: start),
            InstallNotification.day(jobKey: job, name: "TC-0012 บ้านตัวอย่าง", team: "TCR01", day: 1, of: 5, start: start),
            NotificationPlan(id: "demo-mp", type: .mp, title: "เริ่มงานพรุ่งนี้ตามแผน MP", body: "ทุ่งน้อย", sub: "2.3 ติดตั้งแผง", fire: .after(1),
                             info: [NotificationInfo.job: job]),
            post("demo-progress", .progress, "MP 189 ทุ่งน้อย · 2.3 ติดตั้งแผง", "ติดตั้งแผง 38%", .dailyReport(project: job, day: now)),
            post("demo-inspect", .waitingInspector, "MP 154 แพรกหนามแดง · 2.5 Inverter", "Inverter 100%", .dailyReport(project: job, day: now)),
            post("demo-issue", .issue, "TC-0012 · ติดตั้ง Day 2/5", "พบรอยรั่วที่ครอบหลังคาจุด B3", .punch(project: job, id: "demo")),
            post("demo-summary", .summary, "", "สรุปวันที่ 13 ต.ค. — ส่งรายงานแล้ว 8/12 สถานี กปภ. ความคืบหน้ารวม +2%", .summary(day: now)),
        ].compactMap { $0 }
        for i in plans.indices { plans[i].fire = .after(Double(4 + 8 * i)) }
        if let only, plans.indices.contains(only) {
            plans = [plans[only]]
            plans[0].fire = .after(4)
        }
        plans.forEach { self.post($0) }
    }

    /// `survey.navigate` → the same path a real response takes.
    func replay(_ arg: String) {
        let parts = arg.split(separator: ".").map(String.init)
        guard parts.count == 2, let type = NotificationType(rawValue: parts[0]) else { return }
        let action = parts[1] == "default" ? UNNotificationDefaultActionIdentifier : parts[1]
        var info = [NotificationInfo.tool: "mavic3t", NotificationInfo.url: "https://drive.google.com/drive/folders/demo",
                    NotificationInfo.phone: "0812345678"]
        info[NotificationInfo.job] = UserDefaults.standard.string(forKey: "notifJob")
        handle(id: "demo-\(type.rawValue)", category: type.rawValue, action: action, info: info, content: UNNotificationContent())
    }
}
#endif

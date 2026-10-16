import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// The bell of the PWA pages' headers (`PWARoot`, `PWADocsHomeView`): the list, read marks and row actions, as
/// `HomeView` has them. A row's screen opens on the home stack: `PhoneTabs` switches to it when
/// `NotificationService.link` is set.
@MainActor
struct PWABell: DynamicProperty {
    @AppStorage("notifications.read") private var readRaw = ""
    @State private var liveFeed = LiveFeed.shared
    @State private var instruments = InstrumentStore.shared
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @Environment(GoogleSession.self) private var session

    var notifications: [AppNotification] {
        AppNotification.list(jobs: jobs.filter { $0.installDay(on: .now) != nil || $0.surveyDate.isToday },
                             survey: session.survey, posts: liveFeed.posts, tools: instruments.all)
    }

    var unread: Int {
        let read = readIDs
        return notifications.filter { !read.contains($0.id) }.count
    }

    private var readIDs: Set<String> { Set(readRaw.split(separator: "\n").map(String.init)) }

    func view(large: Bool = false, close: (() -> Void)? = nil) -> PhoneNotificationsView {
        PhoneNotificationsView(items: notifications, read: readIDs, markRead: markRead, sync: { session.survey.cloudPush?() },
                               surveyHint: surveyHint,
                               openSurvey: { n in if let job = n.job { openLater(.survey(job: job.syncID ?? job.code)) } },
                               openLink: openLater, large: large, close: close)
    }

    /// Marks these read; ids no longer shown are dropped so the stored list stays small.
    private func markRead(_ list: [AppNotification]) {
        let shown = Set(notifications.map(\.id))
        readRaw = readIDs.intersection(shown).union(list.map(\.id)).sorted().joined(separator: "\n")
        NotificationService.shared.bellRead(Set(list.map(\.id)))
    }

    private func surveyHint(_ n: AppNotification) -> String {
        guard let job = n.job else { return "" }
        let report = job.syncID.flatMap { session.survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        guard report != nil else { return "แตะเพื่อเริ่มสำรวจ A1" }
        return TodayAppointment(job: job, report: report).nextStepLabel.map { "แตะเพื่อทำต่อ \($0)" } ?? "แตะเพื่อเปิดแบบสำรวจ"
    }

    /// After the cover has gone, so the push lands on the home stack.
    private func openLater(_ link: DeepLink) {
        Task { try? await Task.sleep(for: .milliseconds(350)); NotificationService.shared.link = link }
    }
}

import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

/// A report to open at a page, for `navigationDestination(item:)`.
struct OpenReportPage: Identifiable, Hashable {
    let id: UUID
    var start: MissingGroup.Target?
}

/// iPhone home (compact width, docs/ui/tcroof-home-iphone-v3 and v4): logo and bell header, today's appointments as a
/// pager, or with none left `แผนงานถัดไป`, and the project feed, behind `PhoneTabs`' floating dock.
struct PhoneHome: View {
    let appointments: [TodayAppointment]
    let unread: Int
    /// The minute this was drawn at, for the feed's ages.
    let now: Date
    @Binding var notificationsShown: Bool
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    let openFeed: (FeedLink) -> Void
    /// `แผนงานถัดไป`: the next plan items ahead, asked for only when today has no survey appointment left.
    let plan: () -> [HeroItem]

    @State private var page = 0

    var body: some View {
        let appointments = shown
        // nothing left today and nothing ahead: no card and no empty state, the feed starts under the header
        let ahead = appointments.isEmpty ? plan() : []
        ScrollView {
            VStack(spacing: 10) {
                if !appointments.isEmpty {
                    AppointmentHero(size: .phone, appointments: appointments.map { $0.heroItem(open: open) }, page: $page, open: open, newSurvey: nil)
                } else if !ahead.isEmpty {
                    AppointmentHero(size: .phone, title: "แผนงานถัดไป", titleLabel: "แผนงานถัดไป | ไม่มีนัดสำรวจวันนี้",
                                    pagerLabels: ("แผนงานก่อนหน้า", "แผนงานถัดไป"), appointments: ahead, page: $page, open: open, newSurvey: nil)
                }
                HomeFeed(now: now, todayTeams: Set(appointments.map(\.job.teamRaw)), open: openFeed)
            }
            // the dock and `PhoneTab.barGap` are the bottom safe-area inset: the feed ends the board's 104 pt up
            .padding(.horizontal, 16).padding(.top, 12)
        }
        .refreshable { await CloudSync.shared.refresh() }
        // under the header, which is the scroll view's top inset
        .feedNewPostsPill()
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeBrandHeader(size: .phone, unread: unread, notificationsShown: $notificationsShown)
        }
        .background(Theme.phonePage.ignoresSafeArea())
    }

    private var shown: [TodayAppointment] {
        #if DEBUG
        // `-homeNoAppointments YES`
        if UserDefaults.standard.bool(forKey: "homeNoAppointments") { return [] }
        #endif
        return appointments
    }
}

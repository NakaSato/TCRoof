import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

/// A report to open at a page, for `navigationDestination(item:)`.
struct OpenReportPage: Identifiable, Hashable {
    let id: UUID
    var start: MissingGroup.Target?
}

/// iPhone home (compact width, docs/ui/tcroof-home-iphone-v3): logo and bell header, today's appointments as a pager
/// when there are any, and the project feed, behind `PhoneTabs`' floating dock. The modules without a tab are on the
/// `เครื่องมือ` tab (`ToolsView`).
struct PhoneHome: View {
    let appointments: [TodayAppointment]
    let unread: Int
    /// The minute this was drawn at, for the feed's ages.
    let now: Date
    @Binding var notificationsShown: Bool
    let openSettings: () -> Void
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    let openFeed: (FeedLink) -> Void

    @AppStorage("userName") private var userName = ""
    @Environment(GoogleSession.self) private var session
    @State private var page = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // no appointment today: no card and no empty state, the feed starts under the header
                if !shown.isEmpty {
                    AppointmentHero(size: .phone, appointments: shown, page: $page, open: open, newSurvey: {})
                }
                HomeFeed(now: now, todayTeams: Set(appointments.map(\.job.teamRaw)), open: openFeed)
            }
            // the dock and `PhoneTab.barGap` are the bottom safe-area inset: the feed ends the board's 104 pt up
            .padding(.horizontal, 16).padding(.top, 12)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeBrandHeader(size: .phone, initials: userInitials(userName, email: session.email), unread: unread,
                            notificationsShown: $notificationsShown, openSettings: openSettings)
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

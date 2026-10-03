import SwiftUI
import SwiftData
import TCRoofCore
import SurveyUI

/// A report to open at a page, for `navigationDestination(item:)`.
struct OpenReportPage: Identifiable, Hashable {
    let id: UUID
    var start: MissingGroup.Target?
}

/// iPhone home (compact width, docs/ui/tcroof-home-iphone): brand header with the AI greeting,
/// today's appointments as a pager, and one row per module, on one screen.
struct PhoneHome: View {
    let appointments: [TodayAppointment]
    let unread: Int
    let surveyToday: Int
    let installChip: String?
    let greetingFacts: HomeGreeting.Facts
    @Binding var notificationsShown: Bool
    let openSettings: () -> Void
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    let newSurvey: () -> Void

    @AppStorage("userName") private var userName = ""
    @Environment(GoogleSession.self) private var session
    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 12) {
                    AppointmentHero(size: .phone, appointments: appointments, page: $page, open: open, newSurvey: newSurvey)
                    moduleRows
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeBrandHeader(size: .phone, initials: userInitials(userName, email: session.email), unread: unread, facts: greetingFacts,
                            notificationsShown: $notificationsShown, openSettings: openSettings) { EmptyView() }
        }
        .background(Theme.phonePage.ignoresSafeArea())
    }

    private var moduleRows: some View {
        VStack(spacing: 8) {
            ForEach(AppModule.allCases) { module in
                NavigationLink { module.destination } label: {
                    ModuleRow(size: .phone, module: module, chip: module.chip(surveyToday: surveyToday, installDay: installChip))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Tools placeholder

/// `AppModule.tools` until the tools and calibration feature is built.
struct ToolsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("เครื่องมือและอุปกรณ์วัด", systemImage: "briefcase")
        } description: {
            Text("รายการโดรน กล้องถ่ายภาพความร้อน แคลมป์มิเตอร์ และกำหนดสอบเทียบ จะเปิดใช้เร็ว ๆ นี้")
        }
        .font(.sarabun(17))
        .navigationTitle("เครื่องมือและอุปกรณ์วัด")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

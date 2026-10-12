import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore
import SurveyUI

/// A report to open at a page, for `navigationDestination(item:)`.
struct OpenReportPage: Identifiable, Hashable {
    let id: UUID
    var start: MissingGroup.Target?
}

/// iPhone home (compact width, docs/ui/tcroof-home-iphone-v2): logo and bell + avatar header,
/// today's appointments as a pager, and one row per module, on one screen above `PhoneTabs`' tab bar.
struct PhoneHome: View {
    let appointments: [TodayAppointment]
    let unread: Int
    let surveyToday: Int
    let installChip: String?
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
                VStack(spacing: 10) {
                    AppointmentHero(size: .phone, appointments: appointments, page: $page, open: open, newSurvey: newSurvey)
                    moduleRows
                }
                // the tab bar and `PhoneTab.barGap` are the bottom safe-area inset; the board leaves 11 pt above the bar
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 11 - PhoneTab.barGap)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeBrandHeader(size: .phone, initials: userInitials(userName, email: session.email), unread: unread,
                            notificationsShown: $notificationsShown, openSettings: openSettings)
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
    /// The quick action of a tools notification that opened this screen (`คืนอุปกรณ์`, `ดูคิว`…).
    var request: String? = nil

    var body: some View {
        TCEmptyState("เครื่องมือวัด", systemImage: "briefcase",
                     description: Text("รายการโดรน กล้องถ่ายภาพความร้อน แคลมป์มิเตอร์ และกำหนดสอบเทียบ จะเปิดใช้เร็ว ๆ นี้")) {
            if let request, !request.isEmpty {
                Text("จากการแจ้งเตือน: \(request)").font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.primarySoft, in: Capsule())
            }
        }
        .frame(maxHeight: .infinity)
        .navigationTitle("เครื่องมือวัด")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tcPadNavBar("เครื่องมือวัด", trail: ["หน้าหลัก"])
    }
}

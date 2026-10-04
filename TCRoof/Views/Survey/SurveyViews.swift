import SwiftUI
import SwiftData
import CoreLocation
import TCRoofCore

struct SurveyListView: View {
    @Query(sort: \Job.surveyDate) private var jobs: [Job]
    @State private var window: DateWindow = .week
    @State private var search = ""
    @State private var showNewJob = false

    /// Three cards across at 1366 pt, two at 1024 pt.
    private let columns = isPhone ? cardColumns : [GridItem(.adaptive(minimum: 400), spacing: 16)]

    private var filtered: [Job] {
        jobs.filter { window.overlaps($0.surveyInterval) && $0.matches(search) }
    }

    private func buttonTitle(_ job: Job) -> String {
        if job.surveyDraft != nil { return "ทำแบบสำรวจต่อ (ร่าง)" }
        let count = job.savedSurveys.count
        return count == 0 ? "เพิ่มแบบสำรวจ" : "เพิ่มแบบสำรวจ (มี \(count) ฉบับ)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                QueueFilterBar(listTitle: "รายการงานสำรวจ", prefix: "คิวสำรวจ", window: $window, search: $search, count: filtered.count)
                if filtered.isEmpty {
                    ContentUnavailableView("ไม่พบรายการ", systemImage: "tray", description: Text("ลองเปลี่ยนตัวกรองหรือคำค้นหา"))
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filtered) { job in
                            SurveyJobCard(job: job) {
                                NavigationLink { SurveyFormView(job: job) } label: {
                                    GradientButtonLabel(title: buttonTitle(job), systemImage: "list.bullet.clipboard")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageTopBar(title: "สำรวจหน้างาน", trail: ["หน้าหลัก", "สำรวจหน้างาน"], current: "รายการงานสำรวจ") {
                TopBarLink(title: "ประวัติการสำรวจ", systemImage: "clock.arrow.circlepath") { SurveyHistoryView() }
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(systemImage: "person.badge.plus", accessibilityLabel: "เพิ่มลูกค้าใหม่") { showNewJob = true }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewJob) { NewJobView() }
    }
}

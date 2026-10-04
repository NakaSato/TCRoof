import SwiftUI
import SwiftData
import CoreLocation
import TCRoofCore

struct SurveyListView: View {
    @Query(sort: \Job.surveyDate) private var jobs: [Job]
    @State private var window: DateWindow = .week
    @State private var search = ""
    @State private var showNewJob = false
    @Environment(\.dismiss) private var dismiss

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
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background(Theme.pageGradient.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(systemImage: "person.badge.plus", accessibilityLabel: "เพิ่มลูกค้าใหม่") { showNewJob = true }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewJob) { NewJobView() }
    }

    /// Back, page title over the breadcrumb, and the history button, on a white bar.
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .secondaryButtonFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("กลับหน้าหลัก")
            VStack(alignment: .leading, spacing: 0) {
                Text("สำรวจหน้างาน").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.navy)
                (Text("หน้าหลัก › สำรวจหน้างาน › ") + Text("รายการงานสำรวจ").bold().foregroundColor(Theme.navy))
                    .font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 12)
            NavigationLink { SurveyHistoryView() } label: {
                Label("ประวัติการสำรวจ", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .secondaryButtonFrame()
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(minHeight: 72)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }
}

private extension View {
    /// Design system `tc-btn secondary`: white, 1 pt control border, radius 8.
    func secondaryButtonFrame() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderControl))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

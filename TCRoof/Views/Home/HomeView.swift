import SwiftUI
import SwiftData
import SurveyUI

enum AppModule: String, CaseIterable, Identifiable {
    case survey, plan, scan, install, pwa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .survey: "สำรวจหน้างาน"
        case .plan: "แผนก่อสร้าง\nและเอกสาร"
        case .scan: "สแกนอุปกรณ์"
        case .install: "บันทึกงานติดตั้ง\nและใบตรวจรับงาน"
        case .pwa: "การประปา\nส่วนภูมิภาค"
        }
    }

    var subtitle: String {
        switch self {
        case .survey: "นัดหมาย เก็บข้อมูลหลังคาและระบบไฟฟ้า"
        case .plan: "ปฏิทินทีมติดตั้งและเอกสารโครงการ"
        case .scan: "สแกนซีเรียลแผงและอินเวอร์เตอร์"
        case .install: "บันทึกประจำวันและใบตรวจรับ (ICL)"
        case .pwa: "Excel / PDF / Drive"
        }
    }

    var symbol: String {
        switch self {
        case .survey: "list.clipboard.fill"
        case .plan: "calendar"
        case .scan: "barcode.viewfinder"
        case .install: "folder.fill"
        case .pwa: "drop.fill"
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .survey: SurveyListView()
        case .plan: PlanCalendarView()
        case .scan: ScanJobListView()
        case .install: InstallRecordsView()
        case .pwa: SolarSurveyEntryView()
        }
    }
}

struct HomeView: View {
    @AppStorage("userName") private var userName = ""
    @AppStorage("notifications.read") private var readRaw = ""
    @Environment(GoogleSession.self) private var session
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var showAllNotifications = false

    private var todaysJobs: [Job] {
        jobs.filter { $0.installDay(on: .now) != nil || $0.surveyDate.isToday }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(columns: isPhone ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 24), count: 2),
                          spacing: isPhone ? 20 : 24) {
                    ForEach(AppModule.allCases) { module in
                        NavigationLink { module.destination } label: { ModuleCard(module: module) }
                            .buttonStyle(.plain)
                    }
                }
                todaySection
            }
            .padding(isPhone ? 20 : 32)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsView() }
        #if DEBUG
        // `-homeNotifications YES` opens the bell panel for simulator checks
        .task { if UserDefaults.standard.bool(forKey: "homeNotifications") { try? await Task.sleep(for: .seconds(1)); showNotifications = true } }
        #endif
        .sheet(isPresented: $showAllNotifications) {
            NotificationsView(items: notifications, read: readIDs, markRead: markRead, sync: sync)
        }
    }

    // MARK: header

    private var header: some View {
        let survey = session.survey
        let stats: [HomeHeader<NotificationPanel>.Stat] = [
            .init(label: "นัดสำรวจวันนี้", value: jobs.filter { $0.surveyDate.isToday }.count, color: Theme.primary),
            .init(label: "งานสำรวจยังขาด", value: survey.jobs.filter { !$0.completion.isComplete }.count, color: Theme.navy),
            .init(label: "รอซิงก์", value: survey.jobsToSync.count, color: Theme.pending),
        ]
        let items = notifications, read = readIDs
        return HomeHeader(userName: userName, stats: stats, next: nextAppointment,
                          unread: items.filter { !read.contains($0.id) }.count,
                          showNotifications: $showNotifications, openSettings: { showSettings = true }) {
            NotificationPanel(items: items, read: read, markRead: markRead, sync: sync,
                              close: { showNotifications = false },
                              showAll: { showNotifications = false; showAllNotifications = true })
        }
    }

    /// "09:30 · TC-0012 ชื่อโครงการ" — today's first survey appointment still ahead.
    private var nextAppointment: String {
        guard let j = jobs.filter({ $0.surveyDate.isToday && $0.surveyDate > .now }).min(by: { $0.surveyDate < $1.surveyDate }) else {
            return "ไม่มีนัดวันนี้"
        }
        return j.surveyDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + " · \(j.code) \(j.projectName)"
    }

    // MARK: notifications

    private var notifications: [AppNotification] { AppNotification.list(jobs: todaysJobs, survey: session.survey) }
    private var readIDs: Set<String> { Set(readRaw.split(separator: "\n").map(String.init)) }

    /// Marks these read; ids no longer shown are dropped so the stored list stays small.
    private func markRead(_ list: [AppNotification]) {
        let shown = Set(notifications.map(\.id))
        readRaw = readIDs.intersection(shown).union(list.map(\.id)).sorted().joined(separator: "\n")
    }

    private func sync() { session.survey.cloudPush?() }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("งานวันนี้").font(.title2.bold()).foregroundStyle(Theme.navy)
            if todaysJobs.isEmpty {
                Text("ไม่มีงานสำรวจหรืองานติดตั้งในวันนี้")
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                LazyVGrid(columns: cardColumns, spacing: 16) {
                    ForEach(todaysJobs) { job in
                        NavigationLink { JobDetailView(job: job) } label: { TodayRow(job: job) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct TodayRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3).fill(job.team.color).frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.code).bold()
                    TeamTag(team: job.team)
                    Spacer()
                    if let day = job.installDay(on: .now) {
                        Text("ติดตั้ง Day \(day)/\(job.installDays)").font(.caption.bold()).foregroundStyle(Theme.primary)
                    } else {
                        Text("นัดสำรวจ").font(.caption.bold()).foregroundStyle(Theme.teal)
                    }
                }
                Text(job.projectName).font(.subheadline)
                Text("\(job.capacityKW.kw) | \(job.province)").font(.caption).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.navy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }
}

private struct ModuleCard: View {
    let module: AppModule

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(module.title)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(module.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            ModuleIllustration(symbol: module.symbol, size: isPhone ? 84 : 110)
        }
        .padding(isPhone ? 18 : 24)
        .frame(minHeight: isPhone ? 120 : 150)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardShadow()
        .contentShape(Rectangle())
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GoogleSession.self) private var session
    @AppStorage("userName") private var userName = ""
    @State private var sync = CloudSync.shared
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("ผู้ใช้งาน") {
                    TextField("ชื่อที่แสดง", text: $userName)
                        // typed by hand — stop replacing it with the account name
                        .onChange(of: userName) { GoogleSession.userNameEdited() }
                }
                Section {
                    InfoRow(title: "บัญชี Google", value: session.email.flatMap { $0.isEmpty ? nil : $0 } ?? "ลงชื่อเข้าใช้แล้ว")
                    Button("ออกจากระบบ", role: .destructive) { confirmLogout = true }
                } header: {
                    Text("Google Drive")
                } footer: {
                    Text("ไฟล์โครงการจะถูกอัปโหลดไปที่โฟลเดอร์ \"\(DriveFolders.root)\" ใน Google Drive ของบัญชีนี้")
                }
                Section {
                    InfoRow(title: "สถานะ", value: sync.state.title)
                    if let last = sync.lastSync {
                        InfoRow(title: "ซิงค์ล่าสุด", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if case .failed(let message) = sync.state {
                        Text(message).font(.caption).foregroundStyle(.red)
                        Button("ลองอีกครั้ง") { sync.retry() }
                    }
                } header: {
                    Text("ซิงค์ข้อมูลทีม")
                } footer: {
                    Text("ข้อมูลตัวอักษรของทุกงานซิงค์ผ่าน Firebase ให้ทุกเครื่องในทีมเห็นตรงกัน รูปภาพ ลายเซ็น และไฟล์เก็บในเครื่องและ Google Drive")
                }
                Section("เกี่ยวกับ") {
                    InfoRow(title: "แอป", value: "TCRoof Internal")
                    InfoRow(title: "เวอร์ชัน", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("ตั้งค่า")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
            .confirmationDialog("ต้องการออกจากระบบหรือไม่?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("ออกจากระบบ", role: .destructive) {
                    dismiss()
                    session.signOut()
                }
            }
        }
    }
}

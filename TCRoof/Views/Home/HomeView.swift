import SwiftUI
import SwiftData

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
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var showSettings = false
    @State private var showNotifications = false

    private var todaysJobs: [Job] {
        jobs.filter { $0.installDay(on: .now) != nil || $0.surveyDate.isToday }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: isPhone ? 280 : 340), spacing: 20)], spacing: 20) {
                    ForEach(AppModule.allCases) { module in
                        NavigationLink { module.destination } label: { ModuleCard(module: module) }
                            .buttonStyle(.plain)
                    }
                }
                todaySection
            }
            .padding(isPhone ? 20 : 32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNotifications) { NotificationsView(jobs: todaysJobs) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(userName.isEmpty ? "สวัสดี" : "สวัสดี, \(userName)")
                    .font(.system(size: isPhone ? 28 : 36, weight: .bold))
                    .foregroundStyle(Theme.navy)
                TimelineView(.everyMinute) { context in
                    Text(context.date.thaiLongTime)
                        .font(.title3)
                        .foregroundStyle(Theme.navy.opacity(0.8))
                }
            }
            Spacer()
            HStack(spacing: 12) {
                circleButton("bell", badge: todaysJobs.count, label: "การแจ้งเตือน") { showNotifications = true }
                circleButton("gearshape", label: "ตั้งค่า") { showSettings = true }
            }
        }
    }

    private func circleButton(_ symbol: String, badge: Int = 0, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.navy)
                .frame(width: 48, height: 48)
                .background(.white, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.danger, in: Circle())
                    }
                }
        }
        .accessibilityLabel(label)
    }

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
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            ModuleIllustration(symbol: module.symbol, size: isPhone ? 84 : 110)
        }
        .padding(isPhone ? 18 : 24)
        .frame(minHeight: isPhone ? 120 : 150)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.navy.opacity(0.08), radius: 10, y: 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings & notifications

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

struct NotificationsView: View {
    let jobs: [Job]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if jobs.isEmpty {
                    Text("ไม่มีการแจ้งเตือน").foregroundStyle(Theme.muted)
                }
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        if let day = job.installDay(on: .now) {
                            Label("ติดตั้งวันที่ \(day)/\(job.installDays) — ทีม \(job.team.rawValue)", systemImage: "hammer.fill")
                                .foregroundStyle(Theme.primary)
                        } else {
                            Label("นัดสำรวจหน้างานวันนี้", systemImage: "list.clipboard.fill")
                                .foregroundStyle(Theme.teal)
                        }
                        Text("\(job.code) · \(job.projectName)").font(.subheadline)
                        Text(job.address).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            .navigationTitle("การแจ้งเตือน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ปิด") { dismiss() } } }
        }
    }
}

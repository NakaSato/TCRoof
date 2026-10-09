import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// A photo of the day being edited, tagged with a progress line id (or "").
struct DraftPhoto: Identifiable, Equatable {
    let id = UUID()
    var data: Data
    var tag: String
    /// The stored photo it came from, kept on save so its Drive upload isn't repeated.
    var asset: PersistentIdentifier?
}

/// รายงานประจำวัน R2 (docs/specs/routine-reports-swift.md §4.2). iPad wide: sections 1–6 on the left, photos on the
/// right; otherwise one column with photos last. Bottom bar: บันทึกร่าง · ตรวจ & ลงนาม.
struct DailyReportScreen: View {
    @Bindable var job: Job
    let date: Date

    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = ""
    @State private var report: RoutineReport.Daily
    @State private var photos: [DraftPhoto] = []
    /// What was loaded or last saved, to tell unsaved edits apart.
    @State private var saved: (RoutineReport.Daily, [DraftPhoto])?
    @State private var loaded = false
    @State private var showSign = false
    @State private var showAck = false
    @State private var askUnsign = false
    @State private var showSettings = false
    @State private var share: ReportShare?
    @State private var toast: String?

    init(job: Job, date: Date) {
        self.job = job
        self.date = RoutineReport.calendar.startOfDay(for: date)
        _report = State(initialValue: RoutineReport.Daily(date: date))
    }

    private var log: InstallLog? { job.dailyLog(on: date) }
    /// Reports of other days, for "วันนี้" and the carry-over.
    private var others: [RoutineReport.Daily] { job.dailyReports.filter { RoutineReport.dayKey($0.date) != RoutineReport.dayKey(date) } }
    private var dirty: Bool { saved.map { $0.0 != report || $0.1 != photos } ?? true }

    var body: some View {
        GeometryReader { g in
            ScrollView {
                if !isPhone && g.size.width >= 1000 {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) { header; sections }
                        VStack(spacing: 16) { photoCard }.frame(width: 400)
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 16) { header; sections; photoCard }.padding(isPhone ? 16 : 24)
                }
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle("รายงานประจำวัน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Label("ตั้งค่ารายงาน", systemImage: "gearshape") }
            }
        }
        .tcPadNavBar("รายงานประจำวัน", trail: ["หน้าหลัก", job.code], current: date.thaiLong) {
            TCButton("ตั้งค่ารายงาน", systemImage: "gearshape", kind: .secondary) { showSettings = true }
        }
        .sheet(isPresented: $showSign) {
            DailySignSheet(warnings: RoutineReport.warnings(report, previous: others), engineer: job.routineSettings.siteEngineer) { name in
                sign(engineer: name)
            }
        }
        .sheet(isPresented: $showAck) {
            InspectorAckSheet(title: "Inspector รับทราบ", name: job.routineSettings.inspector, date: log?.inspectorAckAt ?? .now) { name, when in
                acknowledge(name: name, at: when)
            }
        }
        .sheet(isPresented: $showSettings) { RoutineSettingsSheet(job: job) }
        .confirmationDialog("รายงานนี้ลงนามแล้ว", isPresented: $askUnsign, titleVisibility: .visible) {
            Button("บันทึกและยกเลิกการลงนาม", role: .destructive, action: saveDraft)
            Button("กลับไปแก้ไข", role: .cancel) {}
        } message: {
            Text("บันทึกแล้วลายเซ็นและการรับทราบของ Inspector จะถูกล้าง ต้องลงนามใหม่")
        }
        .sheet(item: $share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .overlay(alignment: .top) { toastView }
        .onAppear(perform: load)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(RoutineReport.thaiDate(date)).font(.title2.bold()).foregroundStyle(Theme.navy)
                if let day = job.installDay(on: date) {
                    Text("Day \(day)/\(job.installDays)").font(.caption.bold()).foregroundStyle(Theme.primary)
                }
                Spacer()
                statusChip
            }
            Text(job.stationName).font(.subheadline).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 12) {
                Text("เวลาทำงาน").font(.subheadline).foregroundStyle(Theme.inkMuted)
                TextField("08.00", text: $report.workStart).frame(width: 64).textFieldStyle(.roundedBorder)
                Text("–")
                TextField("18.00", text: $report.workEnd).frame(width: 64).textFieldStyle(.roundedBorder)
                Text("น.").foregroundStyle(Theme.inkMuted)
            }
            .font(.body.monospacedDigit())
            if let signed = log?.engineerSignedAt {
                signedRow(signed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder private func signedRow(_ signed: Date) -> some View {
        let layout = isPhone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Label("ลงนามแล้ว \(signed.thaiLongTime)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.okText)
            if let ack = log?.inspectorAckAt {
                Label("Inspector รับทราบ \(ack.thaiLong)", systemImage: "person.fill.checkmark").foregroundStyle(Theme.okText)
            } else {
                Button("บันทึก Inspector รับทราบ") { showAck = true }.frame(minHeight: touchMin)
            }
            Menu {
                Button { exportPDF() } label: { Label("PDF", systemImage: "doc.richtext") }
                Button { exportExcel() } label: { Label("Excel", systemImage: "tablecells") }
            } label: { Label("ส่งออก", systemImage: "square.and.arrow.up").frame(minHeight: touchMin) }
        }
        .font(.subheadline.weight(.semibold))
        if dirty {
            Text("แก้ไขหลังลงนาม: บันทึกแล้วต้องลงนามใหม่").font(.caption).foregroundStyle(Theme.dangerText)
        }
    }

    @ViewBuilder private var statusChip: some View {
        switch job.dailyState(on: date) {
        case .signed: TCStatusChip("ส่งแล้ว", fill: Theme.okSoft, text: Theme.okText)
        case .draft: TCStatusChip("ร่าง", fill: Theme.warningSoft, text: Theme.pending)
        case .none: TCStatusChip("ยังไม่ทำ", fill: Theme.dangerSoft, text: Theme.dangerText)
        }
    }

    private var sections: some View {
        VStack(spacing: 16) {
            WeatherCard(weather: $report.weather)
            CrewCard(report: $report, roles: job.routineSettings.roles)
            ToolsCard(tools: $report.tools, names: job.routineSettings.tools)
            MaterialsCard(materials: $report.materials, locations: job.routineSettings.locations)
            ProgressCard(report: $report, previous: others, job: job)
            ProblemsCard(problems: $report.problems, date: date)
        }
    }

    private var photoCard: some View {
        VStack(spacing: 16) {
            DailyPhotosCard(photos: $photos, lines: report.progress)
            KeyPlanCard(job: job, today: Set(report.progress.map(\.location)))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: requestSaveDraft) {
                Text("บันทึกร่าง").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: touchMin)
            }
            .buttonStyle(.bordered).tint(Theme.primary)
            Button { showSign = true } label: {
                Text("ตรวจ & ลงนาม").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: touchMin)
            }
            .buttonStyle(.borderedProminent).tint(Theme.primary)
        }
        .padding(.horizontal, isPhone ? 16 : 24).padding(.vertical, 10)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.toast, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task { try? await Task.sleep(for: .seconds(2)); withAnimation { self.toast = nil } }
        }
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let log, let r = log.report {
            report = r
            photos = log.sortedPhotos.map { DraftPhoto(data: $0.data, tag: $0.tag, asset: $0.persistentModelID) }
        } else {
            let previous = others.filter { $0.date < date }.last
            report = RoutineReport.nextDay(from: previous, date: date, settings: job.routineSettings)
        }
        saved = (report, photos)
        #if DEBUG
        debugState()
        #endif
    }

    /// Writes the report into its install log (made on first save) and books the progress into the MP plan.
    @discardableResult
    private func write() -> InstallLog {
        let target: InstallLog
        if let log {
            target = log
            if dirty, log.engineerSignedAt != nil { log.engineerSignedAt = nil; log.inspectorAckAt = nil }
        } else {
            target = InstallLog(date: date, recorder: userName, details: "")
            context.insert(target)
            target.job = job
            if job.status == .confirmed || job.status == .interested { job.status = .installing }
        }
        if !userName.isEmpty { target.recorder = userName }
        target.report = report
        if saved?.1 != photos {
            let kept = Dictionary(uniqueKeysWithValues: photos.compactMap { p in p.asset.map { ($0, p) } })
            for asset in target.photos {
                if let p = kept[asset.persistentModelID] { asset.tag = p.tag } else { context.delete(asset) }
            }
            for (i, p) in photos.enumerated() where p.asset == nil {
                let asset = PhotoAsset(data: p.data, tag: p.tag)
                // keep the screen's order: new photos sort after the ones already stored
                asset.createdAt = Date().addingTimeInterval(Double(i) / 1000)
                context.insert(asset)
                asset.log = target
                photos[i].asset = asset.persistentModelID
            }
        }
        job.feedMP()
        try? context.save()
        saved = (report, photos)
        return target
    }

    /// A signed report that was edited loses its signatures on save, so ask first.
    private func requestSaveDraft() {
        if dirty, log?.engineerSignedAt != nil { askUnsign = true } else { saveDraft() }
    }

    private func saveDraft() {
        write()
        withAnimation { toast = "บันทึกร่างแล้ว" }
    }

    private func sign(engineer: String) {
        if job.routineSettings.siteEngineer != engineer {
            var s = job.routineSettings; s.siteEngineer = engineer; job.routineSettings = s
        }
        let target = write()
        target.engineerSignedAt = .now
        if let built = RoutineReportFiles.daily(job, log: target) {
            let data = RoutineReportFiles.file(built, job: job, context: context)
            if let url = try? RoutineReportFiles.temporaryURL(built, data: data) { share = ReportShare(url: url) }
        }
        if let excel = RoutineReportFiles.dailyExcel(job, log: target) { RoutineReportFiles.file(excel, job: job, context: context) }
        try? context.save()
        withAnimation { toast = "ลงนามแล้ว · เก็บ PDF ในเอกสารโครงการ" }
    }

    private func acknowledge(name: String, at when: Date) {
        guard let target = log else { return }
        if job.routineSettings.inspector != name {
            var s = job.routineSettings; s.inspector = name; job.routineSettings = s
        }
        target.inspectorAckAt = when
        if let built = RoutineReportFiles.daily(job, log: target) { RoutineReportFiles.file(built, job: job, context: context) }
        if let excel = RoutineReportFiles.dailyExcel(job, log: target) { RoutineReportFiles.file(excel, job: job, context: context) }
        try? context.save()
    }

    private func exportPDF() {
        guard let log, let built = RoutineReportFiles.daily(job, log: log), let url = try? RoutineReportFiles.temporaryURL(built) else { return }
        share = ReportShare(url: url)
    }

    private func exportExcel() {
        guard let log, let file = RoutineReportFiles.dailyExcel(job, log: log) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        guard (try? file.data.write(to: url, options: .atomic)) != nil else { return }
        share = ReportShare(url: url)
    }

    #if DEBUG
    /// `-routineDemo sign|ack` opens the sign or acknowledge sheet once the screen is up; `pdf` writes PDFs to Documents.
    private func debugState() {
        switch UserDefaults.standard.string(forKey: "routineDemo") {
        case "sign"?: showSign = true
        case "ack"?: if log?.engineerSignedAt != nil { showAck = true }
        // the latest daily report's PDF to Documents/daily.pdf, and this month's R4 to monthly.pdf
        case "pdf"?:
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { break }
            if let last = job.dailyLogs.last, let built = RoutineReportFiles.daily(job, log: last) {
                try? built.data.write(to: docs.appendingPathComponent("daily.pdf"))
            }
            try? RoutineReportFiles.monthly(job, month: date).data.write(to: docs.appendingPathComponent("monthly.pdf"))
        default: break
        }
    }
    #endif
}

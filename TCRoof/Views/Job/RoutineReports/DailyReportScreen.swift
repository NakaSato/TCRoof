import SwiftUI
import SwiftData
import QuickLook
import TCRoofUI
import TCRoofCore
import ModuleRules

/// A photo of the day being edited, tagged with a progress line id (or "").
struct DraftPhoto: Identifiable, Equatable {
    let id = UUID()
    var data: Data
    var tag: String
    /// The stored photo it came from, kept on save so its Drive upload isn't repeated.
    var asset: PersistentIdentifier?
}

/// รายงานประจำวัน R2 (docs/specs/routine-reports-swift.md §4.2), for one day at a time: the iPad one-page layout's
/// day switcher moves it to another report day.
struct DailyReportScreen: View {
    let job: Job
    @State private var date: Date

    init(job: Job, date: Date) {
        self.job = job
        var day = RoutineReport.calendar.startOfDay(for: date)
        #if DEBUG
        // `-routineDailyState daybefore`: the report day before (state 07)
        if DailyOnePage.Debug.state == "daybefore" {
            day = RoutineReport.reportDay(from: day, by: -1, settings: job.routineSettings) ?? day
        }
        #endif
        _date = State(initialValue: day)
    }

    var body: some View {
        DailyReportEditor(job: job, date: date) { date = $0 }.id(RoutineReport.dayKey(date))
    }
}

/// One day's report. iPad regular width (≥ 1000 pt): the one-page layout of docs/ui/daily-report-ipad
/// (`DailyOnePage`); otherwise one column of sections 1–6 and the photos, with the bottom bar บันทึกร่าง | ตรวจ & ลงนาม.
struct DailyReportEditor: View {
    @Bindable var job: Job
    let date: Date
    /// Opens another day's report.
    var moveTo: (Date) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    /// The contractor's foreman fills the report (`daily.fill`); only our engineer signs it and records the
    /// inspector's acknowledgement (`daily.sign`), since a signed report moves the MP plan.
    @Environment(\.permissions) private var permissions
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
    @State private var preview: URL?
    /// A day to open once the signed report's unsaved edits are dealt with.
    @State private var pendingDay: Date?

    init(job: Job, date: Date, moveTo: @escaping (Date) -> Void = { _ in }) {
        self.job = job
        self.date = RoutineReport.calendar.startOfDay(for: date)
        self.moveTo = moveTo
        _report = State(initialValue: RoutineReport.Daily(date: date))
    }

    private var log: InstallLog? { job.dailyLog(on: date) }
    /// Reports of other days, for "วันนี้" and the carry-over.
    private var others: [RoutineReport.Daily] { job.dailyReports.filter { RoutineReport.dayKey($0.date) != RoutineReport.dayKey(date) } }

    /// Construction tasks this report brings to 100 % while the MP plan has them below it, and whose install photos are
    /// missing (`IECReport.missingPhotoLabels`): signing books them, so the sign sheet asks first.
    private var photoWarnings: [MPMissingPhotos] {
        guard let input = job.scheduleInput else { return [] }
        let actual = job.scheduleActual, settings = job.routineSettings, reports = others + [report]
        let tasks = MasterSchedule.Task.allCases.filter { t in
            guard t.part == .construction, input.weight(t) > 0, report.progress.contains(where: { $0.task == t }),
                  let pct = RoutineReport.taskPercent(t, reports: reports, through: report.date, settings: settings), pct >= 99.95
            else { return false }
            return (actual.points[t.rawValue] ?? [:]).values.reduce(0, +) < input.weight(t) - 1e-9
        }
        return MPMissingPhotos.list(tasks, job: job)
    }
    private var dirty: Bool { saved.map { $0.0 != report || $0.1 != photos } ?? true }

    var body: some View {
        GeometryReader { g in
            if !isPhone && (g.size.width >= 1000 || Self.forceOnePage) {
                onePage
            } else {
                classic
            }
        }
        .sheet(isPresented: $showSign) {
            DailySignSheet(warnings: RoutineReport.warnings(report, previous: others), photos: photoWarnings,
                           engineer: job.routineSettings.siteEngineer) { name, drawn in
                sign(engineer: name, signature: drawn)
            }
        }
        .sheet(isPresented: $showAck) {
            InspectorAckSheet(title: "Inspector รับทราบ", name: job.routineSettings.inspector, date: log?.inspectorAckAt ?? .now,
                              signs: true) { name, when, drawn in
                acknowledge(name: name, at: when, signature: drawn)
            }
        }
        .sheet(isPresented: $showSettings) { RoutineSettingsSheet(job: job) }
        .confirmationDialog("รายงานนี้ลงนามแล้ว", isPresented: $askUnsign, titleVisibility: .visible) {
            Button("บันทึกและยกเลิกการลงนาม", role: .destructive) {
                saveDraft()
                if let d = pendingDay { pendingDay = nil; moveTo(d) }
            }
            Button("กลับไปแก้ไข", role: .cancel) { pendingDay = nil }
        } message: {
            Text("บันทึกแล้วลายเซ็นและการรับทราบของ Inspector จะถูกล้าง ต้องลงนามใหม่")
        }
        .sheet(item: $share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .quickLookPreview($preview)
        .overlay(alignment: .top) { toastView }
        .onAppear(perform: load)
    }

    /// `-routineDaily onepage`: the one-page layout whatever the width.
    private static var forceOnePage: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "routineDaily") == "onepage"
        #else
        false
        #endif
    }

    private var onePage: some View {
        DailyOnePage(job: job, date: date, report: $report, photos: $photos, others: others, log: log, dirty: dirty,
                     acknowledging: acknowledging,
                     actions: .init(mustAsk: mustAskBeforeSaving, saveDraft: { write() }, sign: requestSign,
                                    clearSignature: clearSignature, acknowledge: requestAck, clearAck: clearAck, sendBack: sendBack,
                                    preview: previewPDF, send: exportPDF, day: moveDay, open: openDay,
                                    settings: { showSettings = true }, toast: { t in withAnimation { toast = t } }))
    }

    /// The TC team's view (docs/ui/daily-report-ipad-v4 §2): a signed, saved report, opened by someone on our side who
    /// may record the acknowledgement (`requestAck`'s rule).
    private var acknowledging: Bool {
        #if DEBUG
        if DailyOnePage.Debug.ackDemo { return permissions.role != .external }
        #endif
        return log?.engineerSignedAt != nil && !dirty && permissions.role != .external && canSign
    }

    private var classic: some View {
        ScrollView {
            VStack(spacing: 16) { header; sections; photoCard }.padding(isPhone ? 16 : 24)
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
    }

    // MARK: One-page actions

    /// The previous or next report day; today's unsaved edits are kept as a draft first (a signed report asks).
    private func moveDay(_ step: Int) {
        guard let d = RoutineReport.reportDay(from: date, by: step, settings: job.routineSettings, limit: .now) else { return }
        go(to: d)
    }

    /// A day picked in the calendar (up to today), handled as `moveDay`.
    private func openDay(_ day: Date) {
        let d = RoutineReport.calendar.startOfDay(for: day)
        guard d != date, d <= RoutineReport.calendar.startOfDay(for: .now) else { return }
        go(to: d)
    }

    private func go(to d: Date) {
        if dirty, log?.engineerSignedAt != nil {
            // a contractor's edits to a signed report aren't kept (they'd take our engineer's signature off)
            guard canSign else { return moveTo(d) }
            pendingDay = d; askUnsign = true; return
        }
        if dirty { write() }
        moveTo(d)
    }

    private var canSign: Bool { permissions.can(.dailySign, on: job.access) }
    /// The contractor's site engineer (`daily.fill`) or the job's internal team (`daily.sign`) signs the reporter box
    /// (`engineerSignedAt`) to submit the daily report; our engineer/inspector (`daily.sign`) then approves (`inspectorAckAt`).
    private var canSignReport: Bool {
        if permissions.role == .external {
            #if DEBUG
            if DebugScreen.isKnown && job.access.externals.isEmpty { return true }
            #endif
            return permissions.can(.dailyFill, on: job.access)
        }
        return canSign
    }
    /// Who signs, for the line a member who can't sees: our engineers for a contractor, and for a team member not on
    /// a job that names its people (`Permissions.signsDaily`), that job's team, its supervisor or a manager.
    private var signers: String { permissions.role == .external ? "วิศวกรของเรา" : "ทีมงานของงานนี้ ผู้ควบคุมงาน หรือผู้จัดการ" }

    private func requestSign() {
        if log?.engineerSignedAt != nil, !canSign { return withAnimation { toast = signedForOthers } }
        guard canSignReport else { return withAnimation { toast = "\(signers)เป็นผู้ลงนามรายงาน" } }
        // ZNSHINE's manual: no open block, and a reason for every warn, before signing
        let stops = DailyModuleCard.stops(report)
        guard stops.isEmpty else { return withAnimation { toast = "ตรวจติดตั้งแผงยังไม่ผ่าน: " + stops.joined(separator: " | ") } }
        showSign = true
    }

    /// The inspector acknowledges a signed report only.
    private func requestAck() {
        #if DEBUG
        // `-routineDailyState ack|acked`: the sheet opens on the example; saving keeps nothing (no log)
        if DailyOnePage.Debug.ackDemo { showAck = true; return }
        #endif
        guard canSign else { return withAnimation { toast = "\(signers)เป็นผู้บันทึก Inspector รับทราบ" } }
        if log?.engineerSignedAt != nil, !dirty { showAck = true } else { withAnimation { toast = "ผู้รายงานต้องเซ็นก่อน" } }
    }

    private func clearSignature() {
        guard let log, canSign else { return withAnimation { toast = signedForOthers } }
        log.engineerSignedAt = nil
        log.inspectorAckAt = nil
        log.setSignature(nil, tag: InstallLog.engineerSignatureTag, context: context)
        log.setSignature(nil, tag: InstallLog.inspectorSignatureTag, context: context)
        job.feedMP()
        try? context.save()
    }

    /// Takes the inspector's acknowledgement off, leaving the reporter's signature (unlike `clearSignature`), updates
    /// the MP plan, and files the PDF again without it.
    private func clearAck() {
        guard let log, canSign else { return }
        log.inspectorAckAt = nil
        log.setSignature(nil, tag: InstallLog.inspectorSignatureTag, context: context)
        job.feedMP()
        if let built = RoutineReportFiles.daily(job, log: log) { RoutineReportFiles.file(built, job: job, context: context) }
        if let excel = RoutineReportFiles.dailyExcel(job, log: log) { RoutineReportFiles.file(excel, job: job, context: context) }
        try? context.save()
    }

    /// `ส่งกลับให้แก้`: the reason goes into the report as an open problem (the contractor sees it under every line
    /// and in the PDF's problem table), and saving the edited report takes both signatures off.
    private func sendBack(_ reason: String) {
        #if DEBUG
        if DailyOnePage.Debug.ackDemo { return withAnimation { toast = "ส่งกลับให้ผู้รับเหมาแก้แล้ว (ตัวอย่าง ไม่ได้บันทึก)" } }
        #endif
        guard canSign, log?.engineerSignedAt != nil else { return }
        report.problems.append(.init(description: "ทีม TC ส่งกลับให้แก้: " + reason, since: date))
        write()
        clearSignature()
        withAnimation { toast = "ส่งกลับให้ผู้รับเหมาแก้แล้ว" }
    }

    /// The daily PDF of what is on screen: saved as a draft first (a signed report asks before losing its signature).
    private func previewPDF() {
        if dirty, log?.engineerSignedAt != nil {
            guard canSign else { return withAnimation { toast = signedForOthers } }
            askUnsign = true; return
        }
        let target = dirty || log == nil ? write() : log!
        guard let built = RoutineReportFiles.daily(job, log: target), let url = try? RoutineReportFiles.temporaryURL(built) else { return }
        preview = url
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(RoutineReport.thaiDate(date)).font(.sarabun(22, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                if let day = job.installDay(on: date) {
                    Text("Day \(day)/\(job.installDays)").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary)
                }
                Spacer()
                statusChip
            }
            Text(job.stationName).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 12) {
                Text("เวลาทำงาน").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                TextField("08.00", text: $report.workStart).frame(width: 76).textFieldStyle(OutlinedFieldStyle(dense: true))
                Text("–")
                TextField("18.00", text: $report.workEnd).frame(width: 76).textFieldStyle(OutlinedFieldStyle(dense: true))
                Text("น.").foregroundStyle(Theme.inkMuted)
            }
            .font(.sarabun(17, relativeTo: .body).monospacedDigit())
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
                Button("บันทึก Inspector รับทราบ", action: requestAck).frame(minHeight: touchMin)
            }
            Menu {
                Button { exportPDF() } label: { Label("PDF", systemImage: "doc.richtext") }
                Button { exportExcel() } label: { Label("Excel", systemImage: "tablecells") }
            } label: { Label("ส่งออก", systemImage: "square.and.arrow.up").frame(minHeight: touchMin) }
        }
        .font(.sarabun(15, .semibold, relativeTo: .subheadline))
        if dirty {
            Text("แก้ไขหลังลงนาม: บันทึกแล้วต้องลงนามใหม่").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
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
            DailyModuleCard(report: $report, photos: $photos).cardStyle()
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
                Text("บันทึกร่าง").font(.sarabun(17, .semibold, relativeTo: .body)).frame(maxWidth: .infinity, minHeight: touchMin)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
            Button(action: requestSign) {
                Text("ตรวจ & ลงนาม").font(.sarabun(17, .semibold, relativeTo: .body)).frame(maxWidth: .infinity, minHeight: touchMin)
            }
            .buttonStyle(TCButtonStyle(.primary, size: .card))
            .accessibilityIdentifier("dailySign")
        }
        .padding(.horizontal, isPhone ? 16 : 24).padding(.vertical, 10)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast).font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.onMedia)
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
        // `-dailyModuleDemo YES|open`: today's module checklist with a bolt at 22 N·m (the spec's case), not saved
        if let demo = UserDefaults.standard.string(forKey: "dailyModuleDemo") {
            var c = InstallDailyCheck()
            c.method = .clamp; c.ppe = true; c.noJewelry = true; c.weatherDry = true; c.modulesDry = true
            c.boltTorquesNm = [18, 19, 22]; c.clampsPerModule = 4; c.clampOverlapMm = 8; c.gapMm = 20; c.rearClearanceMm = 100
            c.frameModified = false; c.bendRadiusMm = 50; c.groundTorquesNm = [6]; c.installedSerials = ["ZX7523351920001", "ZX7523351920002"]
            report.moduleCheck = c.json
            if demo == "open" { DailyModuleCard.openOnAppear = true }
        }
        #endif
    }

    /// Writes the report into its install log (made on first save) and books the progress into the MP plan.
    @discardableResult
    private func write() -> InstallLog {
        let target: InstallLog
        if let log {
            target = log
            if dirty, log.engineerSignedAt != nil {
                // an edited report is signed again, so its drawn signatures go with the old ones
                log.engineerSignedAt = nil; log.inspectorAckAt = nil
                log.setSignature(nil, tag: InstallLog.engineerSignatureTag, context: context)
                log.setSignature(nil, tag: InstallLog.inspectorSignatureTag, context: context)
            }
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
            for asset in target.photos where !InstallLog.isSignature(asset.tag) {
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

    /// The one-page bar's save button: a signed report that was edited asks first (or, for someone who can't sign,
    /// says why), and the button stays as it is.
    private func mustAskBeforeSaving() -> Bool {
        guard dirty, log?.engineerSignedAt != nil else { return false }
        if canSign { askUnsign = true } else { withAnimation { toast = signedForOthers } }
        return true
    }

    /// A signed report that was edited loses its signatures on save, so ask first.
    private func requestSaveDraft() {
        if dirty, log?.engineerSignedAt != nil {
            if canSign { askUnsign = true } else { withAnimation { toast = signedForOthers } }
        } else {
            saveDraft()
        }
    }

    /// Only our engineer takes a signature off (firestore.rules refuses a contractor's change to `engineerSignedAt`).
    private var signedForOthers: String { "รายงานนี้ลงนามแล้ว | แก้ได้เฉพาะ\(signers)" }

    private func saveDraft() {
        write()
        withAnimation { toast = "บันทึกร่างแล้ว" }
    }

    private func sign(engineer: String, signature: Data?) {
        if job.routineSettings.siteEngineer != engineer {
            var s = job.routineSettings; s.siteEngineer = engineer; job.routineSettings = s
        }
        // the module checklist keeps the rule set and catalog it was signed under
        if var c = DailyModuleCard.check(report) {
            c.ruleSetVersion = ModuleCatalog.ruleSetVersion; c.catalogVersion = ModuleCatalog.version
            report.moduleCheck = c.json
        }
        let target = write()
        target.engineerSignedAt = .now
        target.setSignature(signature, tag: InstallLog.engineerSignatureTag, context: context)
        job.feedMP()   // write() booked it as a draft, which doesn't count
        if let built = RoutineReportFiles.daily(job, log: target) {
            let data = RoutineReportFiles.file(built, job: job, context: context)
            if let url = try? RoutineReportFiles.temporaryURL(built, data: data) { share = ReportShare(url: url) }
        }
        if let excel = RoutineReportFiles.dailyExcel(job, log: target) { RoutineReportFiles.file(excel, job: job, context: context) }
        try? context.save()
        withAnimation { toast = "ลงนามแล้ว | เก็บ PDF ในเอกสารโครงการ" }
    }

    private func acknowledge(name: String, at when: Date, signature: Data?) {
        guard let target = log else { return }
        job.recordInspectorAck(target, name: name, at: when, signature: signature, context: context)
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
    /// `-routineDemo sign|ack` opens the sign or acknowledge sheet once the screen is up; `pdf` writes PDFs to Documents,
    /// `blank` the blank DAILY REPORT form to Documents/daily-blank.pdf.
    private func debugState() {
        switch UserDefaults.standard.string(forKey: "routineDemo") {
        case "sign"?: showSign = true
        case "ack"?: if log?.engineerSignedAt != nil { showAck = true }
        // the latest daily report's PDF to Documents/daily.pdf, and this month's R4 to monthly.pdf
        case "pdf"?:
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { break }
            if let last = job.dailyLogs.last, let built = RoutineReportFiles.daily(job, log: last, samplePhotos: 5) {
                try? built.data.write(to: docs.appendingPathComponent("daily.pdf"))
            }
            try? RoutineReportFiles.monthly(job, month: date).data.write(to: docs.appendingPathComponent("monthly.pdf"))
        case "blank"?:
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { break }
            try? RoutineReportFiles.blankForm(job).data.write(to: docs.appendingPathComponent("daily-blank.pdf"))
        default: break
        }
    }
    #endif
}

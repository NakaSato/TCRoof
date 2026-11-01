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

    @Environment(\.modelContext) var context
    /// The contractor's foreman fills the report (`daily.fill`); only our engineer signs it and records the
    /// inspector's acknowledgement (`daily.sign`), since a signed report moves the MP plan.
    @Environment(\.permissions) var permissions
    @AppStorage("userName") var userName = ""
    @State var report: RoutineReport.Daily
    @State var photos: [DraftPhoto] = []
    /// What was loaded or last saved, to tell unsaved edits apart.
    @State var saved: (RoutineReport.Daily, [DraftPhoto])?
    @State var loaded = false
    @State var showSign = false
    @State var showAck = false
    @State var askUnsign = false
    @State var askSendBack = false
    @State var sendBackReason = ""
    @State var showSettings = false
    @State var share: ReportShare?
    @State var toast: String?
    @State var preview: URL?
    /// A day to open once the signed report's unsaved edits are dealt with.
    @State var pendingDay: Date?

    init(job: Job, date: Date, moveTo: @escaping (Date) -> Void = { _ in }) {
        self.job = job
        self.date = RoutineReport.calendar.startOfDay(for: date)
        self.moveTo = moveTo
        _report = State(initialValue: RoutineReport.Daily(date: date))
    }

    var log: InstallLog? { job.dailyLog(on: date) }
    /// Reports of other days, for "วันนี้" and the carry-over.
    var others: [RoutineReport.Daily] { job.dailyReports.filter { RoutineReport.dayKey($0.date) != RoutineReport.dayKey(date) } }

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
    var dirty: Bool { saved.map { $0.0 != report || $0.1 != photos } ?? true }

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
        .alert("ส่งกลับให้แก้", isPresented: $askSendBack) {
            TextField("เหตุผลที่ส่งกลับ (ต้องใส่)", text: $sendBackReason)
            Button("ส่งกลับ") {
                let reason = sendBackReason.trimmingCharacters(in: .whitespacesAndNewlines)
                sendBackReason = ""
                guard !reason.isEmpty else { withAnimation { toast = "ใส่เหตุผลที่ส่งกลับก่อน" }; return }
                sendBack(reason)
            }
            Button("ยกเลิก", role: .cancel) { sendBackReason = "" }
        } message: {
            Text("ผู้รับเหมาจะเห็นเหตุผลนี้ในปัญหาของรายงาน แล้วแก้และเซ็นส่งใหม่")
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

    var canSign: Bool { permissions.can(.dailySign, on: job.access) }
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
    var signers: String { permissions.role == .external ? "วิศวกรของเรา" : "ทีมงานของงานนี้ ผู้ควบคุมงาน หรือผู้จัดการ" }

    func requestSign() {
        if log?.engineerSignedAt != nil, !canSign { return withAnimation { toast = signedForOthers } }
        guard canSignReport else { return withAnimation { toast = "\(signers)เป็นผู้ลงนามรายงาน" } }
        // ZNSHINE's manual: no open block, and a reason for every warn, before signing
        let stops = DailyModuleCard.stops(report)
        guard stops.isEmpty else { return withAnimation { toast = "ตรวจติดตั้งแผงยังไม่ผ่าน: " + stops.joined(separator: " | ") } }
        showSign = true
    }

    /// The inspector acknowledges a signed report only.
    func requestAck() {
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
        let target = (dirty ? nil : log) ?? write()
        guard let built = RoutineReportFiles.daily(job, log: target), let url = try? RoutineReportFiles.temporaryURL(built) else { return }
        preview = url
    }
}

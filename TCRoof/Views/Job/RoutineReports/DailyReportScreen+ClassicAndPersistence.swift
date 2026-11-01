import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ModuleRules

extension DailyReportEditor {
    // MARK: Parts

    var header: some View {
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
                if canSign {
                    Button("ส่งกลับให้แก้", role: .destructive) { askSendBack = true }
                        .frame(minHeight: touchMin)
                        .accessibilityIdentifier("dailySendBack")
                }
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

    var sections: some View {
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

    var photoCard: some View {
        VStack(spacing: 16) {
            DailyPhotosCard(photos: $photos, lines: report.progress)
            KeyPlanCard(job: job, today: Set(report.progress.map(\.location)))
        }
    }

    var bottomBar: some View {
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

    @ViewBuilder var toastView: some View {
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

    func load() {
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
    func write() -> InstallLog {
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
    func mustAskBeforeSaving() -> Bool {
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
    var signedForOthers: String { "รายงานนี้ลงนามแล้ว | แก้ได้เฉพาะ\(signers)" }

    func saveDraft() {
        write()
        withAnimation { toast = "บันทึกร่างแล้ว" }
    }

    func sign(engineer: String, signature: Data?) {
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

    func acknowledge(name: String, at when: Date, signature: Data?) {
        guard let target = log else { return }
        job.recordInspectorAck(target, name: name, at: when, signature: signature, context: context)
    }

    func exportPDF() {
        guard let log, let built = RoutineReportFiles.daily(job, log: log), let url = try? RoutineReportFiles.temporaryURL(built) else { return }
        share = ReportShare(url: url)
    }

    func exportExcel() {
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

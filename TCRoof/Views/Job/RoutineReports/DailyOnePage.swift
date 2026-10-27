import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

/// รายงานประจำวัน on iPad regular width (docs/ui/daily-report-ipad, the board's one-page layout): the key plan with
/// today's lines as pins and today's work under it on the left; the day, the team and the signatures on the right;
/// the state and the actions in the bottom bar. The page doesn't scroll; its cards do. `DailyReportEditor` keeps the
/// report, the photos, saving and signing; this view lays them out.
struct DailyOnePage: View {
    struct Actions {
        /// True when saving now must ask first (a signed report loses its signature), and it has asked.
        var mustAsk: () -> Bool
        /// Keeps the day as a draft.
        var saveDraft: () -> Void
        var sign: () -> Void
        var clearSignature: () -> Void
        /// The TC view (docs/ui/daily-report-ipad-v4): opens the inspector's acknowledgement sheet, takes the
        /// acknowledgement off (never the reporter's signature), and sends the report back with a reason.
        var acknowledge: () -> Void
        var clearAck: () -> Void
        var sendBack: (String) -> Void
        var preview: () -> Void
        var send: () -> Void
        /// Moves to the previous (-1) or next (+1) report day; nil when there is none that way.
        var day: (Int) -> Void
        /// Opens a day picked in the calendar, the same way as `day`.
        var open: (Date) -> Void
        var settings: () -> Void
        var toast: (String) -> Void
    }

    @Bindable var job: Job
    let date: Date
    @Binding var report: RoutineReport.Daily
    @Binding var photos: [DraftPhoto]
    let others: [RoutineReport.Daily]
    let log: InstallLog?
    let dirty: Bool
    /// The TC team's view of a sent report (docs/ui/daily-report-ipad-v4 §2): the sign card becomes `ลงนามรับทราบ`,
    /// the bar acknowledges or sends back, and the work and team cards are read only (`readOnly`).
    let acknowledging: Bool
    let actions: Actions

    @State var selected: UUID?
    @State var teamTab = DailyOnePage.Debug.tools ? 1 : 0
    @State var mapFull = false
    @State var pop: Pop?
    @State var showWeather = false
    #if DEBUG
    /// `-routineDailyState signedcard`: a signed card with a drawn example signature, not saved.
    @State var demoSign: (at: Date, drawn: Data)?
    /// `-routineDailyState acked`: the inspector's acknowledgement with a drawn signature, not saved.
    @State var demoAck: (at: Date, drawn: Data)?
    #endif
    @State var askSendBack = false
    @State var sendBackReason = ""
    /// A line's photos full screen (the TC view opens them in place of retaking).
    @State var viewing: ViewedPhotos?
    // the key plan (v2 §3): its picture, decoded once per change, and the upload menu's pickers
    @State var keyPlanImage: UIImage?
    @State var keyPlanVersion = 0
    @State var showUpload = false
    @State var showScan = false
    @State var showLibrary = false
    @State var libraryItem: PhotosPickerItem?
    @State var showFiles = false
    @State var pdfPick: KeyPlanFile.PDFPick?
    @State var cropPick: KeyPlanFile.CropPick?
    // a line's photo: the camera, or the library where there is none
    @State var cameraShot: Shot?
    @State var libraryShot: Shot?
    @State var showShotLibrary = false
    @State var shotItem: PhotosPickerItem?
    /// Counts edits, for the save button (it goes back to idle on a change).
    @State var editVersion = 0
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) private var dismiss

    var settings: RoutineReport.Settings { job.routineSettings }
    /// The one edit gate of the TC view: no quick picks, steppers, photo capture, adds, removes or upload; the key
    /// plan, the photos and full screen still open.
    var readOnly: Bool { acknowledging }
    /// The task's weight in this station's plan (an imported workbook has its own).
    func weight(_ task: MasterSchedule.Task) -> Double { job.scheduleInput?.weight(task) ?? task.weight(over200kVA: false) }
    var plan: [MasterSchedule.PlannedTask] { job.scheduleInput.map { MasterSchedule.plan($0) } ?? [] }
    /// Earlier reports only, for "วันนี้".
    var previous: [RoutineReport.Daily] { others.filter { $0.date < date } }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { g in
                HStack(alignment: .top, spacing: 16) {
                    // the plan about as tall as its picture is at the card's width, leaving room for the list
                    let width = g.size.width - 63 * 2 - 16 - 384
                    leftCard(planHeight: min(560, max(300, width * 0.66), g.size.height - 280), narrow: width < 700)
                    rightColumn.frame(width: 384)
                }
                .padding(.horizontal, 63).padding(.top, 16).padding(.bottom, 12)
            }
            bottomBar
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $mapFull) { fullPlan }
        .sheet(isPresented: $showWeather) { DailyWeatherSheet(report: $report) }
        .fullScreenCover(item: $viewing) { v in PhotoViewer(images: v.images, start: v.start) }
        .alert("ส่งกลับให้แก้", isPresented: $askSendBack) {
            TextField("เหตุผลที่ส่งกลับ (ต้องใส่)", text: $sendBackReason)
            Button("ส่งกลับ") { sendBack() }
            Button("ยกเลิก", role: .cancel) { sendBackReason = "" }
        } message: {
            Text("ผู้รับเหมาจะเห็นเหตุผลนี้ในปัญหาของรายงาน แล้วแก้และเซ็นส่งใหม่")
        }
        .fullScreenCover(item: $cameraShot) { s in StampedCamera { took(s, $0) } }
        .photosPicker(isPresented: $showShotLibrary, selection: $shotItem, matching: .images)
        .onChange(of: shotItem) { _, item in
            guard let item, let s = libraryShot else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { took(s, ImageUtil.compressed(data)) }
                shotItem = nil; libraryShot = nil
            }
        }
        // (a `-routineDailyState saving|saved|clean` screenshot keeps its button through the board's seeded lines)
        .onChange(of: report) { _, _ in if Debug.savePhase == nil { editVersion += 1 } }
        .onChange(of: photos.map(\.id)) { _, _ in if Debug.savePhase == nil { editVersion += 1 } }
        // the uploaded plan arriving from another device
        .onChange(of: job.uploadedKeyPlan?.needsDownload) { _, _ in keyPlanVersion += 1 }
        .task(id: keyPlanVersion) { keyPlanImage = job.keyPlanPicture?.image }
        // after the editor has loaded the day
        .task {
            if selected == nil { selected = report.progress.first?.id }
            #if DEBUG
            try? await Task.sleep(for: .milliseconds(300))
            debugState()
            #endif
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("ย้อนกลับ")
            VStack(alignment: .leading, spacing: 0) {
                Text("รายงานประจำวันที่ " + RoutineReport.thaiDateFullWeekday(date)).font(.sarabunFixed(20, .bold)).lineLimit(1)
                Text(job.stationName).font(.sarabunFixed(14)).opacity(0.9).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: actions.settings) {
                Image(systemName: "gearshape").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("ตั้งค่ารายงาน")
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background {
            Theme.headerGradient
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous))
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: lines

    /// The line's colour: by its place in today's list.
    func color(_ line: RoutineReport.ProgressLine) -> Color {
        let i = report.progress.firstIndex { $0.id == line.id } ?? 0
        return Theme.dailyTasks[i % Theme.dailyTasks.count]
    }

    func number(_ line: RoutineReport.ProgressLine) -> Int { (report.progress.firstIndex { $0.id == line.id } ?? 0) + 1 }

    func before(_ line: RoutineReport.ProgressLine) -> Double { RoutineReport.previousPercent(line, before: date, in: others) }

    func photos(of line: RoutineReport.ProgressLine) -> [(index: Int, photo: DraftPhoto)] {
        photos.enumerated().filter { $0.element.tag == line.id.uuidString }.map { ($0.offset + 1, $0.element) }
    }

    // MARK: readiness

    /// Why the report can't be sent yet, or nil when it can: every line has a photo, the reporter is named and signed.
    var blocker: String? {
        if let i = report.progress.firstIndex(where: { photos(of: $0).isEmpty }) { return "งาน \(i + 1) ยังไม่มีรูป" }
        if settings.siteEngineer.trimmingCharacters(in: .whitespaces).isEmpty { return "ใส่ชื่อผู้รายงานก่อนส่ง" }
        if signedAt == nil { return "ผู้รายงานยังไม่ได้เซ็น" }
        return nil
    }

    // MARK: acknowledgement (v4)

    /// The inspector's acknowledgement on screen.
    var ackAt: Date? {
        #if DEBUG
        if Debug.ackDemo { return demoAck?.at }
        #endif
        return log?.inspectorAckAt
    }

    var ackDrawn: Data? {
        #if DEBUG
        if Debug.ackDemo { return demoAck?.drawn }
        #endif
        return log?.signature(InstallLog.inspectorSignatureTag)?.data
    }

    func clearAck() {
        #if DEBUG
        if Debug.ackDemo { demoAck = nil; return }
        #endif
        actions.clearAck()
    }

    func sendBack() {
        let reason = sendBackReason.trimmingCharacters(in: .whitespacesAndNewlines)
        sendBackReason = ""
        guard !reason.isEmpty else { return actions.toast("ใส่เหตุผลที่ส่งกลับก่อน") }
        actions.sendBack(reason)
    }

    /// The acknowledgement is saved by the sheet already, so this only closes the page.
    func confirmAck() {
        actions.toast("รับทราบรายงานแล้ว")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
    }

    // MARK: bottom bar

    @ViewBuilder private var bottomBar: some View {
        if acknowledging { DailyAckBar(page: self) } else { contractorBar }
    }

    private var contractorBar: some View {
        let why = blocker
        return HStack(spacing: 12) {
            Image(systemName: why == nil ? "checkmark" : "exclamationmark").font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.onPrimary).frame(width: 28, height: 28)
                .background(why == nil ? Theme.success : Theme.warning, in: Circle())
            Text(why.map { "ยังส่งไม่ได้ | " + $0 } ?? "ครบทุกส่วนแล้ว | พร้อมส่ง PDF 3 หน้า")
                .font(.sarabunFixed(14)).foregroundStyle(why == nil ? Theme.successText : Theme.navy).lineLimit(1)
            Spacer(minLength: 12)
            TCSaveButton.pad(width: 190, save: { actions.saveDraft(); return .now }, version: editVersion,
                             shouldSave: { !actions.mustAsk() }, savedTime: true, start: Debug.savePhase)
            Button(action: actions.preview) {
                VStack(spacing: 0) {
                    Text("PDF 3 หน้า").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    Text("ดูตัวอย่างรายงาน").font(.sarabunFixed(16, .bold))
                }
                .frame(width: 210, height: 44)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
            Button(action: actions.send) {
                HStack(spacing: 8) {
                    VStack(spacing: 0) {
                        Text(why ?? "ครบแล้ว").font(.sarabunFixed(12)).opacity(0.85).lineLimit(1)
                        Text("ส่งรายงาน").font(.sarabunFixed(16, .bold))
                    }
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                }
                .frame(width: 210, height: 44)
            }
            .buttonStyle(TCButtonStyle(.primary, size: .card))
            .disabled(why != nil)
        }
        .padding(.horizontal, 63).padding(.vertical, 10)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    // MARK: DEBUG

    /// `-routineDailyState task2|tools|dropdown|signed|map|daybefore|material` (with `-screen daily`): states 02–08 of
    /// docs/ui/daily-report-ipad. `daybefore` is the editor's (it opens the day before); `dropdown` can't open a system
    /// menu by itself, so it shows state 01. docs/ui/daily-report-ipad-v3 adds `datepicker`, `worktime`,
    /// `worktimecustom` (07:00–17:00) and `signedcard`, and docs/ui/daily-report-ipad-v2 `upload` (the upload menu)
    /// and `saving|saved|clean` (the save button), none saved. Release builds have none.
    enum Debug {
        #if DEBUG
        static let state = UserDefaults.standard.string(forKey: "routineDailyState") ?? ""
        #else
        static let state = ""
        #endif
        static var tools: Bool { state == "tools" }
        /// `ack`, `acked` (docs/ui/daily-report-ipad-v4): today's report signed by the example engineer, seen by the TC
        /// team (with `-role internal`), not saved; `acked` also has a drawn inspector signature.
        static var ackDemo: Bool { state == "ack" || state == "acked" }
        /// `saving`, `saved`, `clean`: the save button in that state (v2 states 04–06).
        static var savePhase: TCSaveButton.Phase? {
            switch state {
            case "saving": .saving
            case "saved": .justSaved
            case "clean": .clean
            default: nil
            }
        }
    }

    #if DEBUG
    /// With `-routineDaily onepage` on a day with no saved report: the board's three lines (the carried ones moved on,
    /// a planned one added), each with a drawn photo, nothing saved.
    private func seedBoard() {
        guard UserDefaults.standard.string(forKey: "routineDaily") == "onepage", log == nil else { return }
        for g in ghosts where report.progress.count < 3 { report.progress.append(RoutineReport.startToday(g)) }
        // a station whose earlier lines are all done: the board's kind of example lines at its first places
        let places = settings.locations
        for (task, k) in [(MasterSchedule.Task.panels, 0), (.dcSide, 1), (.acSide, 4)] where report.progress.count < 3 && places.indices.contains(k) {
            let line = RoutineReport.ProgressLine(task: task, description: "", location: places[k])
            if !report.progress.contains(where: { $0.key == line.key }) { report.progress.append(line) }
        }
        for (i, line) in report.progress.enumerated() {
            let picks = RoutineReport.quickPicks(before: before(line))
            if let x = i == 0 ? picks.last : picks.first(where: { $0 >= 50 }) ?? picks.last {
                report.progress[i].percent = min(before(line) + x, 100)
            }
            let n = i == 0 ? 2 : 1
            for k in 0..<n { photos.append(DraftPhoto(data: Self.demoPhoto(i * 2 + k), tag: line.id.uuidString)) }
        }
        report.crewConfirmed = true
        selected = report.progress.first?.id
    }

    static func demoPhoto(_ n: Int) -> Data {
        let size = CGSize(width: 320, height: 240)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.25 + 0.05 * Double(n % 4), alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.3, green: 0.45, blue: 0.7, alpha: 1).setFill()
            for r in 0..<4 { ctx.fill(CGRect(x: 30 + r * 70, y: 60 + (n % 3) * 10, width: 60, height: 120)) }
        }
        return img.jpegData(compressionQuality: 0.7) ?? Data()
    }

    /// A drawn squiggle standing in for a signature.
    static func demoSignature() -> Data {
        let size = CGSize(width: 480, height: 180)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 30, y: 150))
            p.addCurve(to: CGPoint(x: 140, y: 140), controlPoint1: CGPoint(x: 70, y: 20), controlPoint2: CGPoint(x: 120, y: 30))
            p.addCurve(to: CGPoint(x: 230, y: 130), controlPoint1: CGPoint(x: 150, y: 40), controlPoint2: CGPoint(x: 220, y: 40))
            p.addCurve(to: CGPoint(x: 330, y: 110), controlPoint1: CGPoint(x: 250, y: 70), controlPoint2: CGPoint(x: 300, y: 70))
            p.addCurve(to: CGPoint(x: 450, y: 80), controlPoint1: CGPoint(x: 360, y: 150), controlPoint2: CGPoint(x: 400, y: 90))
            UIColor(Theme.navy).setStroke()
            p.lineWidth = 9; p.lineCapStyle = .round; p.lineJoinStyle = .round
            p.stroke()
        }
        return img.pngData() ?? Data()
    }

    private func debugState() {
        seedBoard()
        // `-routineKeyPlanUpload YES`: the station gets a drawn uploaded key plan (for good) when it has none
        if UserDefaults.standard.bool(forKey: "routineKeyPlanUpload"), job.uploadedKeyPlan == nil,
           let data = Job.demoPicture.image.jpegData(compressionQuality: 0.7) {
            job.setKeyPlan(data, context: context)
            keyPlanVersion += 1
        }
        switch Debug.state {
        case "task2":
            guard report.progress.count > 1 else { break }
            let line = report.progress[1]
            selected = line.id
            report.progress[1].percent = min(before(line) + 50, 100)
        case "map": mapFull = true
        case "upload": showUpload = true
        case "datepicker": pop = .date
        case "worktime": pop = .time
        case "worktimecustom":
            report.workStart = RoutineReport.WorkHours.text(7); report.workEnd = RoutineReport.WorkHours.text(17)
            pop = .time
        case "signedcard":
            let at = RoutineReport.calendar.date(bySettingHour: 17, minute: 40, second: 0, of: date) ?? date
            demoSign = (at, Self.demoSignature())
        case "ack", "acked":
            let at = RoutineReport.calendar.date(bySettingHour: 17, minute: 40, second: 0, of: date) ?? date
            demoSign = (at, Self.demoSignature())
            if Debug.state == "acked" {
                demoAck = (RoutineReport.calendar.date(bySettingHour: 18, minute: 5, second: 0, of: date) ?? date, Self.demoSignature())
            }
        case "material":
            if let line = report.progress.first(where: { $0.id == selected }) {
                report.materials.append(.init(name: "รางอะลูมิเนียม", location: line.location, qty: 12, unit: "เส้น"))
                report.problems.append(.init(description: "รางส่งมาไม่ครบ", solution: "แจ้งผู้ขายส่งเพิ่ม", since: date, lineKey: line.key))
            }
        default: break
        }
    }
    #endif
}

// MARK: - Right column

extension DailyOnePage {
    var rightColumn: some View {
        VStack(spacing: 12) {
            AnyView(daySwitcher)
            AnyView(teamCard)
            AnyView(DailyModuleCard(report: $report, photos: $photos, compact: true).dailyCard())
            acknowledging ? AnyView(DailyAckCard(page: self)) : AnyView(signCard)
        }
    }

    // MARK: team

    private var teamCard: some View {
        let labour = RoutineReport.labour(report)
        return VStack(alignment: .leading, spacing: 12) {
            // the tiles and the tabs carry the counts (v2 §7)
            Text("ทีมงานวันนี้").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
            HStack(spacing: 8) {
                labourTile("แรงงานวันนี้", labour.total, "\(labour.people) คน × \(labour.hours) ชม.")
                labourTile("ทำงานได้จริง", labour.working, labour.rainHours > 0 ? "หักฝน \(labour.rainHours) ชม." : "ไม่มีฝนในเวลางาน")
            }
            TCCountSegments([.init("คน", count: report.crewTotal), .init("เครื่องมือ", count: report.tools.reduce(0) { $0 + $1.count })],
                            selection: $teamTab, fontSize: 14, countSize: 13)
            if teamTab == 0 && !report.crewConfirmed && !readOnly {
                Button { report.crewConfirmed = true } label: {
                    Label("ใช้ค่าเมื่อวาน | แตะยืนยันกำลังคนวันนี้", systemImage: "exclamationmark.circle")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.warningText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                if teamTab == 0 {
                    DailyCountRows(counts: $report.crew, catalogue: settings.roles, unit: "คน", addTitle: "+ เพิ่มตำแหน่ง") {
                        report.crewConfirmed = true
                    }
                } else {
                    DailyCountRows(counts: $report.tools, catalogue: settings.tools, unit: "ชิ้น", addTitle: "+ เพิ่มเครื่องมือ")
                }
            }
            .allowsHitTesting(!readOnly)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .dailyCard()
    }

    private func labourTile(_ title: String, _ value: Int, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            Text("\(value) คน-ชม.").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
            Text(sub).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

}

/// The team card's rows: a name and a `7 คน ⌄` menu (`ลบออก`, then 1–12), and a dashed `+ เพิ่ม… ⌄` menu of the
/// catalogue's names not in the list. System menus: one open at a time, every option 44 pt.
struct DailyCountRows: View {
    @Binding var counts: [RoutineReport.Count]
    let catalogue: [String]
    let unit: String
    let addTitle: String
    var onChange: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(counts.enumerated()), id: \.element.id) { i, c in
                HStack(spacing: 8) {
                    Text(c.name).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1)
                    Spacer(minLength: 8)
                    countMenu(c)
                }
                .padding(.horizontal, 12).frame(minHeight: 52)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            }
            let missing = catalogue.filter { n in !counts.contains { $0.name == n } }
            if !missing.isEmpty {
                Menu {
                    ForEach(missing, id: \.self) { n in Button(n) { counts.append(.init(name: n, count: 1)); onChange() } }
                } label: {
                    Label(addTitle, systemImage: "chevron.down").labelStyle(TrailingIconLabel())
                        .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                }
                .padding(6)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func countMenu(_ c: RoutineReport.Count) -> some View {
        Menu {
            Button("ลบออก", role: .destructive) { counts.removeAll { $0.id == c.id }; onChange() }
            ForEach(1...12, id: \.self) { n in
                Button { set(c, n) } label: {
                    if n == c.count { Label("\(n)", systemImage: "checkmark") } else { Text("\(n)") }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(c.count)").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                Text(unit).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
            }
            .padding(.horizontal, 12).frame(width: 110, height: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderOutdoor))
        }
        .accessibilityLabel("\(c.name) \(c.count) \(unit)")
    }

    private func set(_ c: RoutineReport.Count, _ n: Int) {
        guard let k = counts.firstIndex(where: { $0.id == c.id }) else { return }
        counts[k].count = n
        onChange()
    }
}

/// Title, then the icon.
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon.font(.system(size: 12, weight: .semibold)) }
    }
}

extension View {
    /// The one-page report's white card.
    func dailyCard() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

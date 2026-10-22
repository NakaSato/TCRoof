import SwiftUI
import TCRoofUI
import TCRoofCore

/// รายงานประจำวัน on iPad regular width (docs/ui/daily-report-ipad, the board's one-page layout): the key plan with
/// today's lines as pins and today's work under it on the left; the day, the team and the signatures on the right;
/// the state and the actions in the bottom bar. The page doesn't scroll; its cards do. `DailyReportEditor` keeps the
/// report, the photos, saving and signing; this view lays them out.
struct DailyOnePage: View {
    struct Actions {
        var saveDraft: () -> Void
        var sign: () -> Void
        var clearSignature: () -> Void
        var preview: () -> Void
        var send: () -> Void
        /// Moves to the previous (-1) or next (+1) report day; nil when there is none that way.
        var day: (Int) -> Void
        /// Opens a day picked in the calendar, the same way as `day`.
        var open: (Date) -> Void
        var settings: () -> Void
    }

    @Bindable var job: Job
    let date: Date
    @Binding var report: RoutineReport.Daily
    @Binding var photos: [DraftPhoto]
    let others: [RoutineReport.Daily]
    let log: InstallLog?
    let dirty: Bool
    let actions: Actions

    @State var selected: UUID?
    @State var teamTab = DailyOnePage.Debug.tools ? 1 : 0
    @State var mapFull = false
    @State var pop: Pop?
    @State var showWeather = false
    #if DEBUG
    /// `-routineDailyState signedcard`: a signed card with a drawn example signature, not saved.
    @State var demoSign: (at: Date, drawn: Data)?
    #endif
    @State var showAdd = false
    @Environment(\.dismiss) private var dismiss

    var settings: RoutineReport.Settings { job.routineSettings }
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
                    VStack(spacing: 12) {
                        keyPlanCard.frame(height: max(320, g.size.height * 0.6))
                        workCard
                    }
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
        .sheet(isPresented: $showAdd) {
            AddWorkSheet(locations: settings.locations, plan: plan.isEmpty ? nil : plan) { lines in
                for var l in lines where !report.progress.contains(where: { $0.key == l.key }) {
                    l.percent = RoutineReport.previousPercent(l, before: report.date, in: others)
                    report.progress.append(l)
                    selected = l.id
                }
            }
        }
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
                Text("รายงานประจำวัน | " + RoutineReport.thaiWeekdayDate(date)).font(.sarabunFixed(20, .bold)).lineLimit(1)
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

    // MARK: bottom bar

    private var bottomBar: some View {
        let why = blocker
        return HStack(spacing: 12) {
            Image(systemName: why == nil ? "checkmark" : "exclamationmark").font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.onPrimary).frame(width: 28, height: 28)
                .background(why == nil ? Theme.success : Theme.warning, in: Circle())
            Text(why.map { "ยังส่งไม่ได้ | " + $0 } ?? "ครบทุกส่วนแล้ว | พร้อมส่ง PDF 3 หน้า")
                .font(.sarabunFixed(14)).foregroundStyle(why == nil ? Theme.successText : Theme.navy).lineLimit(1)
            Spacer(minLength: 12)
            Button(action: actions.saveDraft) {
                Text("บันทึกร่างตอนนี้").font(.sarabunFixed(16, .bold)).frame(width: 150, height: 44)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
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
    /// `worktimecustom` (07:00–17:00) and `signedcard`, none saved. Release builds have none.
    enum Debug {
        #if DEBUG
        static let state = UserDefaults.standard.string(forKey: "routineDailyState") ?? ""
        #else
        static let state = ""
        #endif
        static var tools: Bool { state == "tools" }
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
        switch Debug.state {
        case "task2":
            guard report.progress.count > 1 else { break }
            let line = report.progress[1]
            selected = line.id
            report.progress[1].percent = min(before(line) + 50, 100)
        case "map": mapFull = true
        case "datepicker": pop = .date
        case "worktime": pop = .time
        case "worktimecustom":
            report.workStart = RoutineReport.WorkHours.text(7); report.workEnd = RoutineReport.WorkHours.text(17)
            pop = .time
        case "signedcard":
            let at = RoutineReport.calendar.date(bySettingHour: 17, minute: 40, second: 0, of: date) ?? date
            demoSign = (at, Self.demoSignature())
        case "material":
            if let line = report.progress.first(where: { $0.id == selected }) {
                report.materials.append(.init(name: "รางอะลูมิเนียม", location: line.location, qty: 12, unit: "เส้น"))
                report.problems.append(.init(description: "รางส่งมาไม่ครบ", solution: "แจ้งผู้ขายส่งเพิ่ม", since: date))
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
            AnyView(signCard)
        }
    }

    // MARK: team

    private var teamCard: some View {
        let labour = RoutineReport.labour(report)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ทีมงานวันนี้").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("\(report.crewTotal) คน | เครื่องมือ \(report.tools.reduce(0) { $0 + $1.count }) รายการ")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 8) {
                labourTile("แรงงานวันนี้", labour.total, "\(labour.people) คน × \(labour.hours) ชม.")
                labourTile("ทำงานได้จริง", labour.working, labour.rainHours > 0 ? "หักฝน \(labour.rainHours) ชม." : "ไม่มีฝนในเวลางาน")
            }
            TCCountSegments([.init("คน", count: report.crewTotal), .init("เครื่องมือ", count: report.tools.reduce(0) { $0 + $1.count })],
                            selection: $teamTab, fontSize: 14, countSize: 13)
            if teamTab == 0 && !report.crewConfirmed {
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

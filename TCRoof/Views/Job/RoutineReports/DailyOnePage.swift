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
        var acknowledge: () -> Void
        var clearSignature: () -> Void
        var clearAck: () -> Void
        var preview: () -> Void
        var send: () -> Void
        /// Moves to the previous (-1) or next (+1) report day; nil when there is none that way.
        var day: (Int) -> Void
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
    @State var showTime = false
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
        .sheet(isPresented: $showTime) { DailyTimeSheet(report: $report) }
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
        if log?.engineerSignedAt == nil || dirty { return "ผู้รายงานยังไม่ได้เซ็น" }
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
    /// menu by itself, so it shows state 01. Release builds have none.
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

    private func debugState() {
        seedBoard()
        switch Debug.state {
        case "task2":
            guard report.progress.count > 1 else { break }
            let line = report.progress[1]
            selected = line.id
            report.progress[1].percent = min(before(line) + 50, 100)
        case "map": mapFull = true
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
            AnyView(signCard)
        }
    }

    private var daySwitcher: some View {
        HStack(spacing: 0) {
            Button { actions.day(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("วันก่อน")
            Text(RoutineReport.thaiWeekdayDate(date)).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
            Button { actions.day(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
            }
            .disabled(RoutineReport.reportDay(from: date, by: 1, settings: settings, limit: .now) == nil)
            .accessibilityLabel("วันถัดไป")
            Button { showTime = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("เวลาทำงาน").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                        if report.rainHours > 0 { Image(systemName: "cloud.rain").font(.system(size: 10)).foregroundStyle(Theme.primary) }
                    }
                    Text("\(report.workStart.replacingOccurrences(of: ".", with: ":"))–\(report.workEnd.replacingOccurrences(of: ".", with: ":"))")
                        .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                }
                .padding(.horizontal, 12).frame(height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เวลาทำงานและสภาพอากาศ")
        }
        .foregroundStyle(Theme.primary)
        .padding(4)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    // MARK: sign

    private var signCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ลงนาม").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("ลงใน DAILY REPORT หน้า 3").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            HStack(alignment: .top, spacing: 10) {
                signColumn(title: "ผู้รายงาน", role: "SITE ENGINEER", required: true,
                           signedAt: dirty ? nil : log?.engineerSignedAt, drawn: log?.signature(InstallLog.engineerSignatureTag)?.data,
                           name: nameBinding(\.siteEngineer),
                           placeholder: "ชื่อผู้รายงาน", tap: actions.sign, clear: actions.clearSignature)
                signColumn(title: "ผู้ตรวจงาน", role: "INSPECTOR", required: false,
                           signedAt: dirty ? nil : log?.inspectorAckAt, drawn: log?.signature(InstallLog.inspectorSignatureTag)?.data,
                           name: nameBinding(\.inspector),
                           placeholder: "ชื่อผู้ตรวจงาน", tap: actions.acknowledge, clear: actions.clearAck)
            }
        }
        .padding(16)
        .dailyCard()
    }

    private func nameBinding(_ key: WritableKeyPath<RoutineReport.Settings, String>) -> Binding<String> {
        Binding(get: { job.routineSettings[keyPath: key] }, set: { v in
            var s = job.routineSettings
            s[keyPath: key] = v
            job.routineSettings = s
        })
    }

    private func signColumn(title: String, role: String, required: Bool, signedAt: Date?, drawn: Data?, name: Binding<String>,
                            placeholder: String, tap: @escaping () -> Void, clear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                if required { Text("*").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.danger) }
                Spacer(minLength: 4)
                Text(role).font(.sarabunFixed(9.5, .bold)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Group {
                if let at = signedAt {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 2) {
                            // the drawn signature when there is one, else the name
                            if let drawn, let image = UIImage(data: drawn) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 44)
                                    .accessibilityLabel("ลายเซ็น " + name.wrappedValue)
                            } else {
                                Text(name.wrappedValue.isEmpty ? "ลงนามแล้ว" : name.wrappedValue)
                                    .font(.sarabunFixed(17, .bold)).italic().foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Text("ลงนาม " + ThaiFormat.time.string(from: at)).font(.sarabunFixed(11)).foregroundStyle(Theme.successText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Button(action: clear) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.inkFaint)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("ล้างลายเซ็น" + title)
                    }
                    .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Button(action: tap) {
                        VStack(spacing: 4) {
                            Image(systemName: "signature").font(.system(size: 18, weight: .semibold))
                            Text("แตะเพื่อเซ็น").font(.sarabunFixed(14, .bold))
                        }
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title + " แตะเพื่อเซ็น")
                    .accessibilityIdentifier(required ? "dailySign" : "dailyAck")
                }
            }
            .frame(height: 82)
            TextField(placeholder, text: name).font(.sarabunFixed(15)).textFieldStyle(OutlinedFieldStyle(dense: true))
        }
        .frame(maxWidth: .infinity)
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

/// เวลาทำงาน and the day's weather (the one-page layout has no room for the 15-hour strip).
struct DailyTimeSheet: View {
    @Binding var report: RoutineReport.Daily
    @Environment(\.dismiss) private var dismiss
    static let presets = [("08.00", "17.00"), ("08.00", "18.00"), ("07.00", "16.00"), ("07.00", "17.00")]

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 760) {
                PadSection("เวลาทำงาน") {
                    HStack(spacing: 8) {
                        ForEach(Self.presets.indices, id: \.self) { i in
                            let p = Self.presets[i]
                            let on = report.workStart == p.0 && report.workEnd == p.1
                            Button { report.workStart = p.0; report.workEnd = p.1 } label: {
                                Text("\(p.0)–\(p.1)").font(.sarabunFixed(15, on ? .bold : .regular)).monospacedDigit()
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(on ? Theme.primary : Theme.segmentTrack, in: Capsule())
                                    .foregroundStyle(on ? Theme.onPrimary : Theme.navy)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 12) {
                        TextField("08.00", text: $report.workStart).frame(width: 90).textFieldStyle(OutlinedFieldStyle(dense: true))
                        Text("–")
                        TextField("18.00", text: $report.workEnd).frame(width: 90).textFieldStyle(OutlinedFieldStyle(dense: true))
                        Text("น.").foregroundStyle(Theme.inkMuted)
                    }
                    .monospacedDigit()
                }
                PadSection {
                    WeatherCard(weather: $report.weather)
                }
            }
            .navigationTitle("เวลาทำงานและสภาพอากาศ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() }.bold() } }
        }
    }
}

extension View {
    /// The one-page report's white card.
    func dailyCard() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

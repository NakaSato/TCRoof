import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// คำขอปฏิบัติงานรายสัปดาห์ R1 (§4.3): next week by default, drafted from the MP plan and the latest crew and tools.
/// ส่งขออนุมัติ sends it (our engineer's send also signs it) and files the PDF; บันทึกอนุมัติแล้ว records the approval.
/// A contractor (`weekly.request`, their own job) fills and sends it; the team approves it or sends it back
/// (`ส่งกลับให้แก้`). A sent request is read only for the contractor, an approved one for everyone until the team
/// reopens it (`RoutineReport.WeeklyRequest.isEditable`).
struct WeeklyRequestScreen: View {
    @Bindable var job: Job
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @State private var week: Date
    @State private var request: RoutineReport.WeeklyRequest
    @State private var showApprove = false
    @State private var showAddRisk = false
    @State private var share: ReportShare?
    // the iPad one-page layout (docs/ui/weekly-request-ipad-map): the week's drawn signature, the MP lines at their
    // places, the sheets, the toast, and which week's draft has been laid out
    @State private var signature: WeeklyRequestOnePage.Signature?
    @State private var planned: [RoutineReport.PlanLine] = []
    @State private var showSign = false
    @State private var showPDF = false
    @State private var toast: String?
    @State private var prepared: String?
    /// Inside the install tracking page's `คำขอรายสัปดาห์` tab: always the one-page layout, without its own header.
    private let embedded: Bool
    /// Told the week shown whenever it changes, so the host keeps its own week in step.
    private let onWeek: ((Date) -> Void)?

    init(job: Job, week: Date = RoutineReport.calendar.date(byAdding: .day, value: 7, to: .now)!, embedded: Bool = false,
         onWeek: ((Date) -> Void)? = nil) {
        self.job = job
        self.embedded = embedded
        self.onWeek = onWeek
        var ws = MasterSchedule.weekStart(week)
        #if DEBUG
        // `-requestWeek 0|-1|-2`: next week or one of the two before
        if let n = Int(UserDefaults.standard.string(forKey: "requestWeek") ?? "") { ws = RoutineReport.add(ws, 7 * n) }
        #endif
        _week = State(initialValue: ws)
        _request = State(initialValue: Self.demo ? Self.demoRequest(ws, offset: Self.offset(ws)) : Self.load(job, ws))
    }

    static func load(_ job: Job, _ week: Date) -> RoutineReport.WeeklyRequest { WeeklyRequestStore.load(job, week) }

    /// `-requestDemo YES` (or the install page's `-installDemo YES`): the board's example in memory, nothing saved.
    static var demo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "requestDemo") || UserDefaults.standard.bool(forKey: "installDemo")
        #else
        false
        #endif
    }

    /// `-routineRequest onepage`: the one-page layout whatever the width.
    private static var forceOnePage: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "routineRequest") == "onepage"
        #else
        false
        #endif
    }

    /// Next week's start, which the week list counts from.
    private static var nextWeek: Date { MasterSchedule.weekStart(RoutineReport.add(.now, 7)) }

    /// Weeks from next week (0, -1, -2 …).
    private static func offset(_ week: Date) -> Int {
        Int((MasterSchedule.weekStart(week).timeIntervalSince(nextWeek) / (7 * 86_400)).rounded())
    }

    private var weekEnd: Date { RoutineReport.calendar.date(byAdding: .day, value: 6, to: week)! }
    private var stored: Bool { job.weeklyRequest(for: week) != nil }
    private var external: Bool { permissions.role == .external }
    /// The contractor sends it; the team (`อนุมัติ / ส่งกลับ`) approves, sends back and reopens it.
    private var mayAct: Bool { permissions.can(.weeklyRequest, on: job.access) }
    private var editable: Bool { mayAct && request.isEditable(external: external) }

    var body: some View {
        Group {
            if embedded {
                onePage
            } else {
                GeometryReader { g in
                    if !isPhone && (g.size.width >= 1000 || Self.forceOnePage) {
                        onePage
                    } else {
                        classic
                    }
                }
            }
        }
        .onChange(of: week) { _, w in reload(w); onWeek?(w) }
    }

    /// The form of cards: the iPhone, and an iPad narrower than 1000 pt.
    private var classic: some View {
        ScrollView {
            VStack(spacing: 16) {
                weekBar
                Group {
                    ReportCard("1. กำลังคน") { CountList(counts: $request.crew, names: job.routineSettings.roles, addTitle: "+ ตำแหน่ง") }
                    ReportCard("2. เครื่องมือ") { CountList(counts: $request.tools, names: job.routineSettings.tools, addTitle: "+ เครื่องมือ") }
                    workCard
                    riskCard
                }
                .disabled(!editable)
            }
            .padding(isPhone ? 16 : 24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle("คำขอปฏิบัติงานรายสัปดาห์")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exportPDF() } label: { Label("PDF", systemImage: "square.and.arrow.up") }
            }
        }
        .accessibilityIdentifier("weeklyRequest")
        .tcPadNavBar("คำขอปฏิบัติงานรายสัปดาห์", trail: ["หน้าหลัก", job.code]) {
            TCButton("PDF", systemImage: "square.and.arrow.up", kind: .secondary) { exportPDF() }
        }
        .sheet(isPresented: $showApprove) {
            InspectorAckSheet(title: "บันทึกอนุมัติแล้ว", name: request.approvedBy.isEmpty ? job.routineSettings.inspector : request.approvedBy,
                              date: request.approvedAt ?? .now) { name, when, _ in
                request.approve(by: name, at: when)
                save(file: true)
            }
        }
        .sheet(item: $share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
    }

    // MARK: one page

    private var onePage: some View {
        WeeklyRequestOnePage(
            job: job, request: $request, settings: pageSettings, planned: planned, weeks: weekChoices, signature: signature,
            editable: Self.demo ? request.isEditable(external: external) : editable,
            mayAct: Self.demo || mayAct, mayWithdraw: (Self.demo || mayAct) && !external, demo: Self.demo,
            actions: .init(save: { save(file: false) }, sign: { showSign = true }, clearSignature: { setSignature(nil) },
                           preview: { showPDF = true }, send: sendFromPage,
                           withdraw: { request.sendBack(); save(file: false) },
                           week: { shift(7 * $0) }, openWeek: { week = MasterSchedule.weekStart($0) },
                           toast: { t in withAnimation { toast = t } }),
            embedded: embedded)
            .id(request.id)
            .task(id: request.id) { prepare() }
            .sheet(isPresented: $showSign) {
                RequestSignSheet(name: pageSettings.siteEngineer) { png, name in
                    setSignature(png)
                    if !name.isEmpty, !Self.demo { var s = job.routineSettings; s.siteEngineer = name; job.routineSettings = s }
                }
            }
            .sheet(isPresented: $showPDF) {
                RequestPDFSheet(job: job, request: request, week: Self.weekNumber(request), demo: Self.demo) { url in
                    share = ReportShare(url: url)
                }
            }
            .sheet(item: $share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
            .overlay(alignment: .top) { toastView }
    }

    /// The station's settings, or the board's example ones.
    private var pageSettings: RoutineReport.Settings { Self.demo ? Self.demoSettings(job.routineSettings) : job.routineSettings }

    /// Next week and the two before, each with its request's state (this week's as it stands on screen).
    private var weekChoices: [WeeklyRequestOnePage.WeekChoice] {
        (-2...0).map { n in
            let ws = RoutineReport.add(Self.nextWeek, 7 * n)
            let status: RoutineReport.WeeklyRequest.Status? = MasterSchedule.weekStart(ws) == week ? request.status
                : Self.demo ? Self.demoRequest(ws, offset: n).status : job.weeklyRequest(for: ws)?.status
            return .init(start: ws, status: status)
        }
    }

    /// The week's MP lines at their places and its signature; a new draft takes them, assessed at the defaults.
    private func prepare() {
        planned = Self.demo ? Self.demoPlanned(week) : Self.atPlaces(WeeklyRequestStore.draft(job, week).work, job.routineSettings)
        if Self.demo {
            signature = nil
        } else {
            signature = job.requestSignature(request).map { .init(png: $0.data, at: $0.createdAt) }
        }
        if prepared != request.id, !stored, !Self.demo, request.status == .draft {
            request.work = Self.atPlaces(request.work, job.routineSettings)
            request.assessDefaults()
        }
        #if DEBUG
        if prepared == nil { applyDemoState() }
        #endif
        prepared = request.id
    }

    /// The plan's lines at the places the station's settings give their task (`taskLocations`), one line per place.
    static func atPlaces(_ lines: [RoutineReport.PlanLine], _ settings: RoutineReport.Settings) -> [RoutineReport.PlanLine] {
        lines.flatMap { line -> [RoutineReport.PlanLine] in
            guard line.location.isEmpty, let t = line.task, let places = settings.taskLocations[t.rawValue], !places.isEmpty else { return [line] }
            return places.map { .init(task: t, description: line.description, location: $0, qty: line.qty, unit: line.unit, days: line.days) }
        }
    }

    private func reload(_ w: Date) {
        request = Self.demo ? Self.demoRequest(w, offset: Self.offset(w)) : Self.load(job, w)
    }

    /// Keeps the drawn signature for the week (it syncs and prints on R1), or removes it.
    private func setSignature(_ png: Data?) {
        signature = png.map { .init(png: $0, at: .now) }
        if !Self.demo { job.setRequestSignature(png, for: request, context: context) }
    }

    /// `ส่งขออนุมัติ`: as the tab sends it (our engineer's send signs it), filing the PDF and showing it.
    private func sendFromPage() {
        request.send(by: permissions.email, signs: !external)
        save(file: true)
        showPDF = true
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast).font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.onMedia)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.toast, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task { try? await Task.sleep(for: .seconds(2)); withAnimation { self.toast = nil } }
                .accessibilityIdentifier("requestToast")
        }
    }

    #if DEBUG
    /// `-requestState signed|sent|approved|empty|pdf` (the page opens the others: line2, weeks, worktime, tools, risk,
    /// nodays, map). With `-requestDemo YES` nothing is kept.
    private func applyDemoState() {
        switch UserDefaults.standard.string(forKey: "requestState") ?? "" {
        case "signed": setSignature(Self.demoSignature)
        case "sent":
            setSignature(Self.demoSignature)
            request.send(by: permissions.email.isEmpty ? "engineer@tcroof.test" : permissions.email, signs: true)
        case "approved":
            setSignature(Self.demoSignature)
            request.send(by: permissions.email, signs: true)
            request.approve(by: pageSettings.inspector.isEmpty ? "ผู้ตรวจ กฟภ." : pageSettings.inspector, at: RoutineReport.add(request.weekStart, -2))
        case "empty": request.work = []
        case "pdf": showPDF = true
        default: break
        }
    }
    #endif

    private var weekBar: some View {
        HStack(spacing: 8) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(width: touchMin, height: touchMin) }
                .accessibilityLabel("สัปดาห์ก่อน")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(RoutineReport.thaiDate(week)) – \(RoutineReport.thaiDate(weekEnd))").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text(stateLine).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("weeklyRequest.state")
            }
            Spacer()
            Button { shift(7) } label: { Image(systemName: "chevron.right").frame(width: touchMin, height: touchMin) }
                .accessibilityLabel("สัปดาห์ถัดไป")
            statusChip
        }
        .cardStyle()
    }

    @ViewBuilder private var statusChip: some View {
        switch request.status {
        case .approved: TCStatusChip("อนุมัติแล้ว", fill: Theme.okSoft, text: Theme.okText)
        case .sent: TCStatusChip("รออนุมัติ", fill: Theme.warningSoft, text: Theme.pending)
        case .draft: TCStatusChip("ร่าง", fill: Theme.primarySoft, text: Theme.navy)
        }
    }

    private var workCard: some View {
        ReportCard("3. แผนงาน", trailing: {
            Button("+ งาน") { request.work.append(.init(task: nil, description: "")) }.font(.sarabun(15, .semibold, relativeTo: .subheadline)).frame(minHeight: touchMin)
        }) {
            if request.work.isEmpty { Text("ไม่มีงานตามแผนในสัปดาห์นี้").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted) }
            ForEach($request.work) { $w in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Menu {
                            ForEach(MasterSchedule.Task.allCases.filter { $0.part != .permit }) { t in Button("\(t.code) \(t.title)") { w.task = t } }
                            Button("งานอื่น") { w.task = nil }
                        } label: {
                            Text(w.task?.code ?? "อื่น").font(.sarabun(15, .bold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.primary)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.primarySoft, in: Capsule())
                                .frame(minHeight: touchMin)
                        }
                        TextField("รายละเอียด", text: $w.description, axis: .vertical).textFieldStyle(OutlinedFieldStyle())
                        Button(role: .destructive) { request.work.removeAll { $0.id == w.id } } label: {
                            Image(systemName: "trash").frame(width: touchMin, height: touchMin)
                        }
                        .accessibilityLabel("ลบงาน")
                    }
                    HStack {
                        LocationMenu(location: $w.location, locations: job.routineSettings.locations)
                        Spacer()
                        TextField("ปริมาณ", value: Binding(get: { w.qty > 0 ? w.qty : nil }, set: { w.qty = $0 ?? 0 }), format: .number).keyboardType(.decimalPad).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 90)
                        TextField("หน่วย", text: $w.unit).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 80)
                    }
                }
                Divider()
            }
        }
    }

    private var riskCard: some View {
        ReportCard("4. ประเมินความเสี่ยง", trailing: {
            Menu {
                ForEach(RoutineReport.commonRisks.filter { r in !request.risks.contains { $0.description == r } }, id: \.self) { r in
                    Button(r) { request.risks.append(.init(description: r)) }
                }
                Button("อื่น ๆ") { request.risks.append(.init()) }
            } label: { Text("+ ความเสี่ยง").font(.sarabun(15, .semibold, relativeTo: .subheadline)).frame(minHeight: touchMin) }
        }) {
            if request.risks.isEmpty { Text("ยังไม่ได้ประเมิน").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted) }
            ForEach($request.risks) { $r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("ความเสี่ยง", text: $r.description).textFieldStyle(OutlinedFieldStyle())
                        Button(role: .destructive) { request.risks.removeAll { $0.id == r.id } } label: {
                            Image(systemName: "trash").frame(width: touchMin, height: touchMin)
                        }
                        .accessibilityLabel("ลบความเสี่ยง")
                    }
                    TCSegmented(RoutineReport.RiskLevel.allCases.map(\.title), selection: Binding(
                        get: { r.level.title },
                        set: { t in if let l = RoutineReport.RiskLevel.allCases.first(where: { $0.title == t }) { $r.level.wrappedValue = l } }))
                        .accessibilityLabel("ระดับ")
                    TextField("แนวทางป้องกัน", text: $r.prevention, axis: .vertical).textFieldStyle(OutlinedFieldStyle())
                }
                Divider()
            }
        }
    }

    /// What the week bar says under the dates: who sent it and when, or that it is a draft.
    private var stateLine: String {
        if let at = request.approvedAt { return "อนุมัติแล้ว \(RoutineReport.thaiDate(at))" + (request.approvedBy.isEmpty ? "" : " | \(request.approvedBy)") }
        if let at = request.sentAt ?? request.engineerSignedAt {
            let by = request.sentBy.isEmpty ? "" : " | \(TeamDirectory.shared.person(request.sentBy)?.name ?? request.sentBy)"
            return "ส่งขออนุมัติ \(RoutineReport.thaiDate(at))\(by)" + (external ? " | แก้ไม่ได้จนกว่าทีมส่งกลับ" : "")
        }
        return stored ? "บันทึกร่างแล้ว" : "ร่างจากแผน MP | ยังไม่บันทึก"
    }

    private var bottomBar: some View {
        HStack(spacing: 12) { barButtons }
            .padding(.horizontal, isPhone ? 16 : 24).padding(.vertical, 10)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
    }

    @ViewBuilder private var barButtons: some View {
        if !mayAct {
            barNote("ดูอย่างเดียว")
        } else {
            switch request.status {
            case .draft:
                barButton("บันทึกร่าง", .secondary, id: "weeklyRequest.saveDraft") { save(file: false) }
                barButton("ส่งขออนุมัติ", .primary, id: "weeklyRequest.send") {
                    request.send(by: permissions.email, signs: !external)
                    save(file: true)
                    if !external { exportPDF() }
                }
            case .sent where external:
                barNote("ส่งแล้ว | รอทีมอนุมัติ")
            case .sent:
                barButton("ส่งกลับให้แก้", .secondary, id: "weeklyRequest.sendBack") { request.sendBack(); save(file: false) }
                barButton("บันทึกอนุมัติแล้ว", .primary, id: "weeklyRequest.approve") { showApprove = true }
            case .approved where external:
                barNote("อนุมัติแล้ว")
            case .approved:
                barButton("เปิดแก้อีกครั้ง", .secondary, id: "weeklyRequest.reopen") { request.reopen(); save(file: false) }
                barButton("แก้วันที่อนุมัติ", .primary, id: "weeklyRequest.approve") { showApprove = true }
            }
        }
    }

    private func barButton(_ title: String, _ kind: TCButtonKind, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabun(17, .semibold, relativeTo: .body)).frame(maxWidth: .infinity, minHeight: touchMin)
        }
        .buttonStyle(TCButtonStyle(kind, size: .card))
        .accessibilityIdentifier(id)
    }

    private func barNote(_ text: String) -> some View {
        Text(text).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: touchMin)
            .accessibilityIdentifier("weeklyRequest.note")
    }

    private func shift(_ days: Int) {
        week = RoutineReport.calendar.date(byAdding: .day, value: days, to: week) ?? week
    }

    private func save(file: Bool) {
        guard !Self.demo else { return }
        WeeklyRequestStore.save(request, job: job, external: external, file: file, context: context)
    }

    private func exportPDF() {
        if let url = WeeklyRequestStore.pdfURL(job, request) { share = ReportShare(url: url) }
    }

    /// ISO week of the request's Saturday, as the install page's other weeks.
    static func weekNumber(_ r: RoutineReport.WeeklyRequest) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: r.date(ofDay: 5))
    }
}

/// The week's request (or its draft from the MP plan), keeping it, and its R1 PDF.
@MainActor
enum WeeklyRequestStore {
    static func draft(_ job: Job, _ week: Date) -> RoutineReport.WeeklyRequest {
        RoutineReport.requestDraft(weekStart: week, plan: job.scheduleInput.map { MasterSchedule.plan($0) }, actual: job.scheduleActual,
                                   latest: job.dailyReports.last, settings: job.routineSettings)
    }

    static func load(_ job: Job, _ week: Date) -> RoutineReport.WeeklyRequest { job.weeklyRequest(for: week) ?? draft(job, week) }

    /// Keeps the request on the job, and with `file` adds its PDF to the job's documents.
    static func save(_ request: RoutineReport.WeeklyRequest, job: Job, external: Bool, file: Bool, context: ModelContext) {
        job.saveRequest(request)
        // a contractor's device sends the requests with its IEC test only when it changed them (`CloudSync`)
        if external { job.weeklyRequestsUnsent = true }
        if file { RoutineReportFiles.file(RoutineReportFiles.request(job, request), job: job, context: context) }
        try? context.save()
    }

    /// The R1 PDF in a temporary file, to share or preview.
    static func pdfURL(_ job: Job, _ request: RoutineReport.WeeklyRequest) -> URL? {
        try? RoutineReportFiles.temporaryURL(RoutineReportFiles.request(job, request))
    }
}

/// The requester's drawn signature of a week's request: a `PhotoAsset` on the job (`iecPhotos`, the job's own photos,
/// as the uploaded key plan), tagged with the week, so it syncs, goes to Drive beside the request and prints on R1.
extension Job {
    static func requestSignatureTag(_ r: RoutineReport.WeeklyRequest) -> String { "request.signature." + r.id }

    func requestSignature(_ r: RoutineReport.WeeklyRequest) -> PhotoAsset? {
        let tag = Self.requestSignatureTag(r)
        return iecPhotos.first { $0.tag == tag && !$0.data.isEmpty }
    }

    /// Keeps `png` as the week's signature (nil removes it).
    @MainActor func setRequestSignature(_ png: Data?, for r: RoutineReport.WeeklyRequest, context: ModelContext) {
        let tag = Self.requestSignatureTag(r)
        for p in iecPhotos where p.tag == tag { context.delete(p) }
        if let png {
            let asset = PhotoAsset(data: png, tag: tag)
            context.insert(asset)
            asset.iecJob = self
        }
        try? context.save()
    }

    /// Every week's signature, with its request, for the Drive upload.
    var requestSignatures: [(request: RoutineReport.WeeklyRequest, photo: PhotoAsset)] {
        weeklyRequests.compactMap { r in requestSignature(r).map { (r, $0) } }
    }
}

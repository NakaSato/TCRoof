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

    init(job: Job, week: Date = RoutineReport.calendar.date(byAdding: .day, value: 7, to: .now)!) {
        self.job = job
        let ws = MasterSchedule.weekStart(week)
        _week = State(initialValue: ws)
        _request = State(initialValue: Self.load(job, ws))
    }

    static func load(_ job: Job, _ week: Date) -> RoutineReport.WeeklyRequest { WeeklyRequestStore.load(job, week) }

    private var weekEnd: Date { RoutineReport.calendar.date(byAdding: .day, value: 6, to: week)! }
    private var stored: Bool { job.weeklyRequest(for: week) != nil }
    private var external: Bool { permissions.role == .external }
    /// The contractor sends it; the team (`อนุมัติ / ส่งกลับ`) approves, sends back and reopens it.
    private var mayAct: Bool { permissions.can(.weeklyRequest, on: job.access) }
    private var editable: Bool { mayAct && request.isEditable(external: external) }

    var body: some View {
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
        .onChange(of: week) { _, w in request = Self.load(job, w) }
    }

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
        WeeklyRequestStore.save(request, job: job, external: external, file: file, context: context)
    }

    private func exportPDF() {
        if let url = WeeklyRequestStore.pdfURL(job, request) { share = ReportShare(url: url) }
    }
}

/// What the request screen and the iPad install page's `คำขอรายสัปดาห์` tab share: the week's request (or its draft
/// from the MP plan), keeping it, and its R1 PDF.
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

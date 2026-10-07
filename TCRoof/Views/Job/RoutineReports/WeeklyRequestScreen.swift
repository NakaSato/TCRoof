import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// คำขอปฏิบัติงานรายสัปดาห์ R1 (§4.3): next week by default, drafted from the MP plan and the latest crew and tools.
/// ส่งขออนุมัติ signs it and files the PDF; บันทึกอนุมัติแล้ว records the Inspector's date and name.
struct WeeklyRequestScreen: View {
    @Bindable var job: Job
    @Environment(\.modelContext) private var context
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

    static func load(_ job: Job, _ week: Date) -> RoutineReport.WeeklyRequest {
        job.weeklyRequest(for: week) ?? RoutineReport.requestDraft(
            weekStart: week, plan: job.scheduleInput.map { MasterSchedule.plan($0) }, actual: job.scheduleActual,
            latest: job.dailyReports.last, settings: job.routineSettings)
    }

    private var weekEnd: Date { RoutineReport.calendar.date(byAdding: .day, value: 6, to: week)! }
    private var stored: Bool { job.weeklyRequest(for: week) != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                weekBar
                ReportCard("1. กำลังคน") { CountList(counts: $request.crew, names: job.routineSettings.roles, addTitle: "+ ตำแหน่ง") }
                ReportCard("2. เครื่องมือ") { CountList(counts: $request.tools, names: job.routineSettings.tools, addTitle: "+ เครื่องมือ") }
                workCard
                riskCard
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
        .sheet(isPresented: $showApprove) {
            InspectorAckSheet(title: "บันทึกอนุมัติแล้ว", name: request.approvedBy.isEmpty ? job.routineSettings.inspector : request.approvedBy,
                              date: request.approvedAt ?? .now) { name, when in
                request.approvedBy = name; request.approvedAt = when
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
                Text("\(RoutineReport.thaiDate(week)) – \(RoutineReport.thaiDate(weekEnd))").font(.headline).foregroundStyle(Theme.navy)
                Text(stored ? "บันทึกแล้ว" : "ร่างจากแผน MP · ยังไม่บันทึก").font(.caption).foregroundStyle(Theme.muted)
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
            Button("+ งาน") { request.work.append(.init(task: nil, description: "")) }.font(.subheadline.weight(.semibold)).frame(minHeight: touchMin)
        }) {
            if request.work.isEmpty { Text("ไม่มีงานตามแผนในสัปดาห์นี้").font(.subheadline).foregroundStyle(Theme.muted) }
            ForEach($request.work) { $w in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Menu {
                            ForEach(MasterSchedule.Task.allCases.filter { $0.part != .permit }) { t in Button("\(t.code) \(t.title)") { w.task = t } }
                            Button("งานอื่น") { w.task = nil }
                        } label: {
                            Text(w.task?.code ?? "อื่น").font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(Theme.primary)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.primarySoft, in: Capsule())
                                .frame(minHeight: touchMin)
                        }
                        TextField("รายละเอียด", text: $w.description, axis: .vertical).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { request.work.removeAll { $0.id == w.id } } label: {
                            Image(systemName: "trash").frame(width: touchMin, height: touchMin)
                        }
                        .accessibilityLabel("ลบงาน")
                    }
                    HStack {
                        LocationMenu(location: $w.location, locations: job.routineSettings.locations)
                        Spacer()
                        TextField("ปริมาณ", value: Binding(get: { w.qty > 0 ? w.qty : nil }, set: { w.qty = $0 ?? 0 }), format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 90)
                        TextField("หน่วย", text: $w.unit).textFieldStyle(.roundedBorder).frame(width: 80)
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
            } label: { Text("+ ความเสี่ยง").font(.subheadline.weight(.semibold)).frame(minHeight: touchMin) }
        }) {
            if request.risks.isEmpty { Text("ยังไม่ได้ประเมิน").font(.subheadline).foregroundStyle(Theme.muted) }
            ForEach($request.risks) { $r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("ความเสี่ยง", text: $r.description).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { request.risks.removeAll { $0.id == r.id } } label: {
                            Image(systemName: "trash").frame(width: touchMin, height: touchMin)
                        }
                        .accessibilityLabel("ลบความเสี่ยง")
                    }
                    Picker("ระดับ", selection: $r.level) {
                        ForEach(RoutineReport.RiskLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("แนวทางป้องกัน", text: $r.prevention, axis: .vertical).textFieldStyle(.roundedBorder)
                }
                Divider()
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { save(file: false) } label: {
                Text("บันทึกร่าง").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: touchMin)
            }
            .buttonStyle(.bordered).tint(Theme.primary)
            if request.engineerSignedAt == nil {
                Button { request.engineerSignedAt = .now; save(file: true); exportPDF() } label: {
                    Text("ส่งขออนุมัติ").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: touchMin)
                }
                .buttonStyle(.borderedProminent).tint(Theme.primary)
            } else {
                Button { showApprove = true } label: {
                    Text(request.approvedAt == nil ? "บันทึกอนุมัติแล้ว" : "แก้วันที่อนุมัติ").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: touchMin)
                }
                .buttonStyle(.borderedProminent).tint(Theme.primary)
            }
        }
        .padding(.horizontal, isPhone ? 16 : 24).padding(.vertical, 10)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func shift(_ days: Int) {
        week = RoutineReport.calendar.date(byAdding: .day, value: days, to: week) ?? week
    }

    private func save(file: Bool) {
        job.saveRequest(request)
        if file { RoutineReportFiles.file(RoutineReportFiles.request(job, request), job: job, context: context) }
        try? context.save()
    }

    private func exportPDF() {
        if let url = try? RoutineReportFiles.temporaryURL(RoutineReportFiles.request(job, request)) { share = ReportShare(url: url) }
    }
}

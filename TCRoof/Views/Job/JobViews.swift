import SwiftUI
import TCRoofUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

struct JobDetailView: View {
    @Bindable var job: Job

    @Environment(\.modelContext) private var context
    @Environment(GoogleSession.self) private var session
    @State private var showSchedule = false
    @State private var showImporter = false
    @State private var previewURL: URL?
    @State private var uploadProgress: String?
    @State private var uploadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                let pair = isPhone ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                pair {
                    customerCard
                    scheduleCard
                }
                MPScheduleCard(job: job)
                RoutineReportCard(job: job)
                StationDocsCard(job: job)
                actionsGrid
                PWASurveyCard(job: job)
                surveysCard
                documentsCard
            }
            .padding(isPhone ? 16 : 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle(job.code)
        .navigationBarTitleDisplayMode(.inline)
        .tcPadNavBar(job.projectName.isEmpty ? job.code : job.projectName, trail: ["หน้าหลัก", "แผนก่อสร้างและเอกสาร"], current: job.code)
        .sheet(isPresented: $showSchedule) { ScheduleEditSheet(job: job) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image, .spreadsheet, .presentation, .data],
                      allowsMultipleSelection: true, onCompletion: importDocuments)
        .quickLookPreview($previewURL)
        .overlay {
            if let uploadProgress {
                ProgressView(uploadProgress)
                    .padding(24)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("อัปโหลดไม่สำเร็จ", isPresented: Binding(get: { uploadError != nil }, set: { if !$0 { uploadError = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(uploadError ?? "")
        }
    }

    private var summaryCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(job.code).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.muted)
                    TeamTag(team: job.team)
                }
                Text(job.projectName).font(isPhone ? .sarabun(22, .bold, relativeTo: .title2) : .sarabun(34, .bold, relativeTo: .largeTitle)).foregroundStyle(Theme.navy)
                let facts = isPhone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 20))
                facts {
                    Label(job.capacityKW.kw, systemImage: "bolt.fill")
                    Label("~\(job.estimatedPanels) แผง", systemImage: "square.grid.3x3.fill")
                    Label(job.province, systemImage: "mappin.and.ellipse")
                }
                .font(.sarabun(15, relativeTo: .subheadline))
                .foregroundStyle(Theme.navy)
            }
            Spacer()
            Menu {
                Picker("สถานะ", selection: $job.status) {
                    ForEach(JobStatus.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    TCStatusChip(job.status.title, fill: job.status.color.opacity(0.12), text: job.status.color)
                    Image(systemName: "chevron.down").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(job.status.color)
                }
            }
        }
        .cardStyle(padding: 20)
    }

    private var customerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ข้อมูลลูกค้า").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            InfoRow(title: "ชื่อ", value: job.customerName)
            if !job.phone.isEmpty {
                HStack {
                    Text("โทรศัพท์").foregroundStyle(Theme.muted)
                    Spacer()
                    if let url = URL(string: "tel:\(job.phone)") {
                        Link(job.phone, destination: url)
                    }
                }
                .font(.sarabun(15, relativeTo: .subheadline))
            }
            InfoRow(title: "ที่อยู่", value: "\(job.address) \(job.province)")
            if let url = mapsURL {
                Link(destination: url) {
                    Label("เปิดแผนที่", systemImage: "map").font(.sarabun(15, .semibold, relativeTo: .subheadline))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(job.address) \(job.province)")]
        return components?.url
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("แผนงาน").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                Button("แก้ไข") { showSchedule = true }.font(.sarabun(15, .semibold, relativeTo: .subheadline))
            }
            InfoRow(title: "วันที่สำรวจ", value: job.surveyDate.thaiLong)
            InfoRow(title: "เริ่มติดตั้ง", value: job.installStart.thaiLong)
            InfoRow(title: "ติดตั้งเสร็จ", value: job.installEnd.thaiLong)
            InfoRow(title: "ระยะเวลา", value: "\(job.installDays) วัน · ทีม \(job.team.rawValue)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var actionsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: isPhone ? 1 : 2), spacing: 16) {
            action(job.surveyDraft == nil ? "เพิ่มแบบสำรวจ" : "ทำแบบสำรวจต่อ (ร่าง)", "list.bullet.clipboard", "\(job.savedSurveys.count) ฉบับ") { SurveyFormView(job: job) }
            action("สแกนอุปกรณ์", "barcode.viewfinder", "\(job.devices.count) รายการ") { JobDevicesView(job: job) }
            action("บันทึกงานติดตั้ง", "hammer", "\(job.logs.count) บันทึก") { JobInstallLogsView(job: job) }
            action("ใบตรวจรับงาน (ICL)", "checkmark.seal", inspectionStatus) { InspectionView(job: job) }
            action("งานบ้าน ครบวงจร", "house", "สำรวจ · ขออนุญาต PEA · ติดตั้ง · ขนานไฟ") { HomeWorkView(job: job) }
        }
    }

    private var inspectionStatus: String {
        guard let inspection = job.inspection else { return "ยังไม่เริ่ม" }
        if inspection.submittedAt != nil { return "ตรวจรับแล้ว" }
        return "\(inspection.completedCount)/\(InspectionStep.all.count) ขั้นตอน"
    }

    private func action<D: View>(_ title: String, _ symbol: String, _ detail: String,
                                 @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.sarabun(22, relativeTo: .title2))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 52, height: 52)
                    .background(Theme.headerGradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    Text(detail).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .cardStyle(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var surveysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("แบบสำรวจ").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            if job.savedSurveys.isEmpty {
                Text("ยังไม่มีแบบสำรวจ").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            if job.surveyDraft != nil {
                NavigationLink { SurveyFormView(job: job) } label: {
                    Label("มีร่างแบบสำรวจที่ยังไม่บันทึก · แตะเพื่อทำต่อ", systemImage: "pencil.and.list.clipboard")
                        .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.pending)
                }
                .buttonStyle(.plain)
            }
            ForEach(job.savedSurveys) { survey in
                NavigationLink { SurveyDetailView(survey: survey) } label: {
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(Theme.primary)
                        Text("\(survey.createdAt.thaiLong) · \(survey.roofType) · เสนอ \(survey.recommendedKW.kw)")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                    .font(.sarabun(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.navy)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var documentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("เอกสารโครงการ").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                Button { showImporter = true } label: { Label("แนบไฟล์", systemImage: "paperclip") }
                    .font(.sarabun(15, .semibold, relativeTo: .subheadline))
            }
            if job.documents.isEmpty {
                Text("แนบแบบติดตั้ง ใบเสนอราคา หรือเอกสารขออนุญาต (PDF, รูปภาพ)")
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            if !job.documents.isEmpty || job.inspection?.submittedAt != nil || job.driveFolderURL != nil {
                driveRow
            }
            ForEach(job.documents.sorted { $0.addedAt > $1.addedAt }) { doc in
                HStack {
                    Button { preview(doc) } label: {
                        HStack {
                            Image(systemName: doc.name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc")
                                .foregroundStyle(Theme.primary)
                            VStack(alignment: .leading) {
                                Text(doc.name).lineLimit(1)
                                Text("\(doc.addedAt.thaiLong) · \(ByteCountFormatter.string(fromByteCount: Int64(doc.data.count), countStyle: .file))")
                                    .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                            }
                        }
                        .foregroundStyle(Theme.navy)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if doc.driveFileID != nil {
                        Image(systemName: "checkmark.icloud.fill")
                            .foregroundStyle(Theme.teal)
                            .accessibilityLabel("อัปโหลดขึ้น Google Drive แล้ว")
                    }
                    Button(role: .destructive) { context.delete(doc) } label: { Image(systemName: "trash") }
                        .accessibilityLabel("ลบเอกสาร")
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Upload button and link to the job's Drive folder.
    @ViewBuilder private var driveRow: some View {
        let pending = ProjectDriveUpload.pendingCount(job)
        let layout = isPhone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button(action: uploadToDrive) {
                Label(pending > 0 ? "อัปโหลดขึ้น Google Drive (\(pending))" : "อัปโหลดครบแล้ว",
                      systemImage: pending > 0 ? "icloud.and.arrow.up" : "checkmark.icloud")
            }
            .buttonStyle(TCButtonStyle(.primary, size: .card))
            .disabled(pending == 0 || uploadProgress != nil)
            if let link = job.driveFolderURL, let url = URL(string: link) {
                Link(destination: url) { Label("เปิดโฟลเดอร์ใน Drive", systemImage: "arrow.up.right.square") }
                    .font(.sarabun(15, .semibold, relativeTo: .subheadline))
            }
        }
        .padding(.vertical, 4)
        if job.inspection?.submittedAt != nil {
            Text("รวมรายงานใบตรวจรับงาน (ICL) ที่ลงนามแล้วเป็น PDF")
                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
    }

    private func uploadToDrive() {
        Task {
            do {
                try await ProjectDriveUpload.run(job, session: session) { done, total in
                    uploadProgress = "กำลังอัปโหลด \(done)/\(total)"
                }
            } catch {
                uploadError = error.localizedDescription
            }
            uploadProgress = nil
        }
    }

    private func importDocuments(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let doc = DocumentAsset(name: url.lastPathComponent, data: data)
            context.insert(doc)
            doc.job = job
        }
    }

    private func preview(_ doc: DocumentAsset) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.name)
        try? doc.data.write(to: url)
        previewURL = url
    }
}

// MARK: - Schedule editor

struct ScheduleEditSheet: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection("ขนาดระบบ") {
                    LabeledContent("กำลังการผลิต (kWp)") {
                        TextField("0", value: $job.capacityKW, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                PadSection("แผนงาน") {
                    DatePicker("วันที่สำรวจ", selection: $job.surveyDate)
                    DatePicker("เริ่มติดตั้ง", selection: $job.installStart, displayedComponents: .date)
                    Stepper("ระยะเวลาติดตั้ง \(job.installDays) วัน", value: $job.installDays, in: 1...60)
                    PadPicker("ทีมติดตั้ง", selection: $job.team) {
                        ForEach(Team.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("แก้ไขแผนงาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
        }
    }
}

// MARK: - New job

/// The add-customer sheet: the iOS grouped design at compact width (docs/ui/tcroof-new-job-iphone), the plain form otherwise.
/// `onOpen` receives the new job when `เปิดงาน` is tapped on the compact sheet's saved banner.
struct NewJobView: View {
    var onOpen: ((Job) -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact { NewJobPhoneView(onOpen: onOpen) } else { NewJobFormView() }
    }
}

private struct NewJobFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var projectName = ""
    @State private var customerName = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var province = "กรุงเทพมหานคร"
    @State private var capacity: Double = 0
    @State private var team: Team = .t1
    @State private var surveyDate = Date().adding(days: 1).startOfDay.addingTimeInterval(9 * 3600)
    @State private var installStart = Date().adding(days: 14).startOfDay
    @State private var installDays = 2

    private var isValid: Bool {
        !customerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection("ลูกค้า") {
                    TextField("ชื่อลูกค้า / บริษัท *", text: $customerName)
                    TextField("ชื่อโครงการ (ว่างไว้ = ใช้ชื่อลูกค้า)", text: $projectName)
                    TextField("เบอร์โทรศัพท์", text: $phone).keyboardType(.phonePad)
                    TextField("ที่อยู่", text: $address, axis: .vertical)
                    TextField("จังหวัด", text: $province)
                }
                PadSection("แผนงาน") {
                    LabeledContent("ขนาดระบบโดยประมาณ (kWp)") {
                        TextField("0", value: $capacity, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    DatePicker("นัดสำรวจ", selection: $surveyDate)
                    DatePicker("เริ่มติดตั้ง (ประมาณ)", selection: $installStart, displayedComponents: .date)
                    Stepper("ระยะเวลาติดตั้ง \(installDays) วัน", value: $installDays, in: 1...60)
                    PadPicker("ทีม", selection: $team) { ForEach(Team.allCases) { Text($0.rawValue).tag($0) } }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("เพิ่มลูกค้าใหม่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("บันทึก", action: save).disabled(!isValid) }
            }
        }
    }

    private func save() {
        let name = customerName.trimmingCharacters(in: .whitespaces)
        let project = projectName.trimmingCharacters(in: .whitespaces)
        let job = Job(code: SampleData.newJobCode(), projectName: project.isEmpty ? name : project, customerName: name,
                      phone: phone, address: address, province: province, capacityKW: capacity, team: team,
                      status: .interested, surveyDate: surveyDate, installStart: installStart, installDays: installDays)
        context.insert(job)
        try? context.save()
        dismiss()
    }
}

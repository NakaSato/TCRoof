import SwiftUI
import SwiftData
import CoreLocation
import TCRoofCore

struct SurveyListView: View {
    @Query(sort: \Job.surveyDate) private var jobs: [Job]
    @State private var window: DateWindow = .week
    @State private var search = ""
    @State private var showNewJob = false
    @Environment(\.dismiss) private var dismiss

    /// Three cards across at 1366 pt, two at 1024 pt.
    private let columns = isPhone ? cardColumns : [GridItem(.adaptive(minimum: 400), spacing: 16)]

    private var filtered: [Job] {
        jobs.filter { window.overlaps($0.surveyInterval) && $0.matches(search) }
    }

    private func buttonTitle(_ job: Job) -> String {
        if job.surveyDraft != nil { return "ทำแบบสำรวจต่อ (ร่าง)" }
        let count = job.savedSurveys.count
        return count == 0 ? "เพิ่มแบบสำรวจ" : "เพิ่มแบบสำรวจ (มี \(count) ฉบับ)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                QueueFilterBar(listTitle: "รายการงานสำรวจ", prefix: "คิวสำรวจ", window: $window, search: $search, count: filtered.count)
                if filtered.isEmpty {
                    ContentUnavailableView("ไม่พบรายการ", systemImage: "tray", description: Text("ลองเปลี่ยนตัวกรองหรือคำค้นหา"))
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filtered) { job in
                            SurveyJobCard(job: job) {
                                NavigationLink { SurveyFormView(job: job) } label: {
                                    GradientButtonLabel(title: buttonTitle(job), systemImage: "list.bullet.clipboard")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background(Theme.pageGradient.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(systemImage: "person.badge.plus", accessibilityLabel: "เพิ่มลูกค้าใหม่") { showNewJob = true }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewJob) { NewJobView() }
    }

    /// Back, page title over the breadcrumb, and the history button, on a white bar.
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .secondaryButtonFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("กลับหน้าหลัก")
            VStack(alignment: .leading, spacing: 0) {
                Text("สำรวจหน้างาน").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.navy)
                (Text("หน้าหลัก › สำรวจหน้างาน › ") + Text("รายการงานสำรวจ").bold().foregroundColor(Theme.navy))
                    .font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 12)
            NavigationLink { SurveyHistoryView() } label: {
                Label("ประวัติการสำรวจ", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .secondaryButtonFrame()
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(minHeight: 72)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }
}

private extension View {
    /// Design system `tc-btn secondary`: white, 1 pt control border, radius 8.
    func secondaryButtonFrame() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderControl))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Survey job card

/// A survey queue card: job, appointment, draft progress, then `footer` (the survey button).
/// The body opens `JobDetailView`; the footer is a separate tap target.
struct SurveyJobCard<Footer: View>: View {
    let job: Job
    @ViewBuilder var footer: () -> Footer

    private var days: Int { RelativeDay.days(from: .now, to: job.surveyDate) }
    private var when: String { RelativeDay.label(days: days, time: ThaiFormat.time.string(from: job.surveyDate)) }
    private var progress: SurveyCardProgress {
        SurveyCardProgress(draft: job.surveyDraft.map(SurveyOptions.progress), hasSaved: !job.savedSurveys.isEmpty)
    }

    var body: some View {
        let p = progress
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { JobDetailView(job: job) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(job.projectName), \(when), \(p.key) \(p.value) \(p.percent)%")
            progressBox(p)
            footer()
        }
        .cardStyle()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            codeRow
            metaRow
            Divider().padding(.vertical, 4)
            whenRow
            Label(job.province, systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(Theme.navy.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(job.projectName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.navy)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            DotPill(title: "ทีม \(job.team.rawValue)", color: job.team.color, dot: true)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    private var codeRow: some View {
        HStack(spacing: 8) {
            Text(job.code).font(.caption.bold()).foregroundStyle(Theme.inkMuted)
            DotPill(title: job.status.title, color: job.status.color)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 16) {
            if job.customerName != job.projectName {
                Label(job.customerName, systemImage: "person").lineLimit(1)
            }
            Label(job.capacityKW.kw, systemImage: "bolt.fill")
        }
        .font(.footnote)
        .foregroundStyle(Theme.navy.opacity(0.85))
    }

    private var whenRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(when, systemImage: "calendar")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(days == 0 ? Theme.primary : days < 0 ? Theme.muted : Theme.navy)
            Text(job.surveyDate.thaiShort).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func progressBox(_ p: SurveyCardProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.key).font(.caption).foregroundStyle(Theme.inkMuted)
                Text(p.value).font(.subheadline.bold()).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(p.percent)%").font(.subheadline.bold()).monospacedDigit()
                    .foregroundStyle(p.percent == 0 ? Theme.progressZero : p.tone == .complete ? Theme.progressFull : Theme.primary)
            }
            HStack(spacing: 3) {
                ForEach(p.segments.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(color(p.segments[i])).frame(height: 6)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(p.tone == .draft ? Theme.progressBox : Theme.progressBoxIdle, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func color(_ segment: SurveyCardProgress.Segment) -> Color {
        switch segment {
        case .done: Theme.stepDone
        case .current: Theme.primary
        case .todo: Theme.borderSubtle
        }
    }
}

// MARK: - Survey form

/// Opens a job's survey draft (creating one if needed), or an existing survey for editing.
/// The form edits the SwiftData record directly, so nothing is lost when the screen is left.
struct SurveyFormView: View {
    private let job: Job?
    private let existing: SurveyForm?

    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = "สมชาย"
    @State private var form: SurveyForm?

    init(job: Job) {
        self.job = job
        self.existing = nil
    }

    init(survey: SurveyForm) {
        self.job = survey.job
        self.existing = survey
    }

    var body: some View {
        if let form {
            SurveyEditor(form: form)
        } else {
            ProgressView().onAppear(perform: resolve)
        }
    }

    private func resolve() {
        if let existing { form = existing; return }
        guard let job else { return }
        if let draft = job.surveyDraft { form = draft; return }
        let draft = SurveyForm.blankDraft(surveyor: userName)
        context.insert(draft)
        draft.job = job
        try? context.save()
        form = draft
    }
}

enum SurveyOptions {
    static let roofTypes = ["เมทัลชีท", "กระเบื้องลอนคู่", "กระเบื้องซีแพค", "คอนกรีต/ดาดฟ้า", "อื่น ๆ"]
    static let orientations = ["ทิศใต้", "ทิศตะวันออก", "ทิศตะวันตก", "ทิศเหนือ", "ทิศตะวันออกเฉียงใต้", "ทิศตะวันตกเฉียงใต้"]
    static let shadings = ["ไม่มี", "มีบางส่วน", "มีมาก"]
    static let utilities = ["กฟภ.", "กฟน."]
    static let tariffs = ["อัตราปกติ", "TOU"]
    static let groundings = ["มี", "ไม่มี", "ไม่แน่ใจ"]
    static let breakers = [16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 300, 400]

    struct PhotoTag: Identifiable {
        let id: String
        let title: String
        let required: Bool
    }

    static let photoTags: [PhotoTag] = [
        .init(id: "meter", title: "มิเตอร์ไฟฟ้า", required: true),
        .init(id: "mdb", title: "ตู้ไฟ / เมนเบรกเกอร์", required: true),
        .init(id: "roof", title: "หลังคา (ภาพรวม)", required: true),
        .init(id: "structure", title: "โครงหลังคา / แป", required: false),
        .init(id: "inverter", title: "จุดติดตั้งอินเวอร์เตอร์", required: false),
        .init(id: "bill", title: "บิลค่าไฟ", required: false),
        .init(id: "other", title: "อื่น ๆ", required: false),
    ]

    /// Photos of one category; untagged photos from older versions count as "อื่น ๆ".
    static func photos(_ form: SurveyForm, _ tag: String) -> [PhotoAsset] {
        form.photos.filter { $0.tag == tag || (tag == "other" && $0.tag.isEmpty) }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Rough sizing: kWh/month (or bill ÷ 4.5 THB), 60% daytime use, 4 peak sun hours.
    static func suggestedKW(_ form: SurveyForm) -> Double {
        let units = form.monthlyKWh > 0 ? form.monthlyKWh : form.monthlyBill / 4.5
        guard units > 0 else { return 0 }
        return ((units * 0.6 / 30 / 4) * 100).rounded() / 100
    }

    /// ~6 m² of roof per kWp.
    static func maxKWByRoof(_ form: SurveyForm) -> Double { (form.roofAreaSqm / 6 * 100).rounded() / 100 }

    static func autoKW(_ form: SurveyForm) -> Double {
        let a = suggestedKW(form), b = maxKWByRoof(form)
        if a > 0 && b > 0 { return min(a, b) }
        return max(a, b)
    }

    /// Every required item in form order, with its group in `SurveyDraftProgress.groupTitles`
    /// (หลังคา, ระบบไฟฟ้า, ค่าไฟ, รูปบังคับ) and whether it is filled.
    static func checklist(_ form: SurveyForm) -> [(title: String, group: Int, filled: Bool)] {
        [
            ("ประเภทหลังคา", 0, !form.roofType.isEmpty),
            ("พื้นที่หลังคา", 0, form.roofAreaSqm > 0),
            ("ทิศทางหลังคา", 0, !form.orientation.isEmpty),
            ("เงาบัง", 0, !form.shading.isEmpty),
            ("การไฟฟ้า", 1, !form.utility.isEmpty),
            ("ระบบมิเตอร์", 1, !form.meterPhase.isEmpty),
            ("เมนเบรกเกอร์", 1, form.mainBreakerAmp > 0),
            ("ค่าไฟหรือหน่วยต่อเดือน", 2, form.monthlyBill > 0 || form.monthlyKWh > 0),
        ] + photoTags.filter(\.required).map { ("รูป\($0.title)", 3, !photos(form, $0.id).isEmpty) }
    }

    /// Required items still empty, in form order.
    static func missing(_ form: SurveyForm) -> [String] {
        checklist(form).filter { !$0.filled }.map { $0.title }
    }

    /// The same checklist as `missing`, counted per group for the job list card.
    static func progress(_ form: SurveyForm) -> SurveyDraftProgress {
        SurveyDraftProgress(items: checklist(form).map { .init(group: $0.group, filled: $0.filled) })
    }
}

private struct SurveyEditor: View {
    @Bindable var form: SurveyForm

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = "สมชาย"

    @State private var locator = LocationFetcher()
    @State private var locating = false
    @State private var locationError: String?
    @State private var showMissing = false
    @State private var confirmDiscard = false

    private var missing: [String] { SurveyOptions.missing(form) }

    var body: some View {
        Form {
            Section {
                if let job = form.job {
                    InfoRow(title: "รหัสโครงการ", value: job.code)
                    InfoRow(title: "ลูกค้า", value: job.customerName)
                    InfoRow(title: "ที่อยู่", value: "\(job.address) \(job.province)")
                }
            } footer: {
                if form.isDraft {
                    Text("ร่าง: บันทึกอัตโนมัติทุกครั้งที่แก้ไข ออกจากหน้านี้แล้วกลับมาทำต่อได้")
                }
            }

            locationSection
            roofSection
            electricalSection
            sizingSection
            photoSections

            Section("หมายเหตุ") {
                TextField("รายละเอียดเพิ่มเติม", text: $form.notes, axis: .vertical).lineLimit(3...8)
            }

            if !missing.isEmpty {
                Section {
                    ForEach(missing, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                } header: {
                    Text("ยังขาด \(missing.count) รายการ")
                }
            }
        }
        .navigationTitle(form.isDraft ? "แบบสำรวจหน้างาน (ร่าง)" : "แก้ไขแบบสำรวจ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(form.isDraft ? "บันทึก" : "เสร็จ", action: finish).bold()
            }
            if form.isDraft {
                ToolbarItem(placement: .secondaryAction) {
                    Button("ทิ้งร่าง", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                }
            }
        }
        .alert("ยังกรอกไม่ครบ", isPresented: $showMissing) {
            Button("กรอกต่อ", role: .cancel) {}
            Button(form.isDraft ? "เก็บเป็นร่างไว้ก่อน" : "ปิดไปก่อน") { dismiss() }
        } message: {
            Text(missing.joined(separator: "\n"))
        }
        .confirmationDialog("ทิ้งร่างแบบสำรวจนี้?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("ทิ้งร่างและรูปทั้งหมด", role: .destructive, action: discard)
        }
        .task {
            if form.isDraft && form.latitude == nil { locate() }
        }
    }

    // MARK: Sections

    private var locationSection: some View {
        Section("ตำแหน่งหน้างาน") {
            if let lat = form.latitude, let lon = form.longitude {
                LabeledContent("พิกัด", value: String(format: "%.6f, %.6f", lat, lon))
                if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(form.job?.code ?? "หน้างาน")") {
                    Link(destination: url) { Label("เปิดในแผนที่", systemImage: "map") }
                }
            }
            Button(action: locate) {
                HStack {
                    Label(form.latitude == nil ? "บันทึกพิกัดปัจจุบัน" : "อัปเดตพิกัด", systemImage: "location.fill")
                    if locating { Spacer(); ProgressView() }
                }
            }
            .disabled(locating)
            if let locationError {
                Text(locationError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var roofSection: some View {
        Section("ข้อมูลหลังคา") {
            Picker("ประเภทหลังคา", selection: $form.roofType) {
                Text("เลือก").tag("")
                ForEach(SurveyOptions.roofTypes, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("พื้นที่หลังคาที่ใช้ได้ (ตร.ม.)") {
                TextField("กรอก", value: optional(\.roofAreaSqm), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Picker("ทิศทางหลังคา", selection: $form.orientation) {
                Text("เลือก").tag("")
                ForEach(SurveyOptions.orientations, id: \.self) { Text($0).tag($0) }
            }
            Stepper("ความลาดชัน \(form.tiltDegree)°", value: $form.tiltDegree, in: 0...60)
            Picker("เงาบัง", selection: $form.shading) {
                Text("เลือก").tag("")
                ForEach(SurveyOptions.shadings, id: \.self) { Text($0).tag($0) }
            }
            Toggle("โครงสร้างหลังคารับน้ำหนักได้", isOn: $form.structureOK)
        }
    }

    private var electricalSection: some View {
        Section("ระบบไฟฟ้า") {
            Picker("การไฟฟ้า", selection: $form.utility) {
                ForEach(SurveyOptions.utilities, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent("เลขผู้ใช้ไฟฟ้า (CA)") {
                TextField("ดูจากบิลค่าไฟ", text: $form.caNumber)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            Picker("ระบบมิเตอร์", selection: $form.meterPhase) {
                Text("1 เฟส").tag("1 เฟส")
                Text("3 เฟส").tag("3 เฟส")
            }
            .pickerStyle(.segmented)
            LabeledContent("ขนาดมิเตอร์") {
                TextField("เช่น 15(45) A", text: $form.meterSize).multilineTextAlignment(.trailing)
            }
            Picker("เมนเบรกเกอร์", selection: $form.mainBreakerAmp) {
                Text("เลือก").tag(0)
                ForEach(breakerOptions, id: \.self) { Text("\($0) A").tag($0) }
            }
            Picker("อัตราค่าไฟ", selection: $form.tariff) {
                Text("ไม่ระบุ").tag("")
                ForEach(SurveyOptions.tariffs, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("หน่วยไฟเฉลี่ยต่อเดือน (kWh)") {
                TextField("จากบิล", value: optional(\.monthlyKWh), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("ค่าไฟเฉลี่ยต่อเดือน (บาท)") {
                TextField("กรอก", value: optional(\.monthlyBill), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Picker("สายดินเดิม", selection: $form.grounding) {
                Text("ไม่ระบุ").tag("")
                ForEach(SurveyOptions.groundings, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    /// Standard sizes, plus the stored value when an older record used another size.
    private var breakerOptions: [Int] {
        let current = form.mainBreakerAmp
        return current > 0 && !SurveyOptions.breakers.contains(current)
            ? (SurveyOptions.breakers + [current]).sorted() : SurveyOptions.breakers
    }

    private var sizingSection: some View {
        Section {
            LabeledContent("ขนาดแนะนำจากการใช้ไฟ", value: SurveyOptions.suggestedKW(form).kw)
            LabeledContent("ขนาดสูงสุดตามพื้นที่หลังคา", value: SurveyOptions.maxKWByRoof(form).kw)
            LabeledContent("ขนาดที่เสนอ (kWp)") {
                TextField(SurveyOptions.autoKW(form).plain, value: optional(\.recommendedKW), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .bold()
            }
        } header: {
            Text("ขนาดระบบที่เสนอ")
        } footer: {
            Text("ใช้หน่วย kWh ถ้ากรอก ไม่เช่นนั้นคิดจากค่าไฟ 4.5 บาท/หน่วย · ใช้ไฟกลางวัน 60% · แดดเฉลี่ย 4 ชม./วัน · เว้นว่างเพื่อใช้ค่าที่คำนวณ")
        }
    }

    private var photoSections: some View {
        ForEach(SurveyOptions.photoTags) { tag in
            let photos = SurveyOptions.photos(form, tag.id)
            Section {
                PhotoPickerSection(images: photos.map(\.data),
                                   onAdd: { addPhoto($0, tag: tag.id) },
                                   onDelete: { index in deletePhoto(photos, at: index) })
            } header: {
                HStack {
                    Text("รูป\(tag.title)")
                    if tag.required {
                        Text(photos.isEmpty ? "จำเป็น" : "ครบ")
                            .foregroundStyle(photos.isEmpty ? .orange : .green)
                    }
                }
            }
        }
    }

    // MARK: Actions

    /// A number field that shows empty for 0 instead of a made-up value.
    private func optional(_ keyPath: ReferenceWritableKeyPath<SurveyForm, Double>) -> Binding<Double?> {
        Binding(get: { form[keyPath: keyPath] > 0 ? form[keyPath: keyPath] : nil },
                set: { form[keyPath: keyPath] = max($0 ?? 0, 0) })
    }

    private func addPhoto(_ data: Data, tag: String) {
        let photo = PhotoAsset(data: data, tag: tag)
        context.insert(photo)
        photo.survey = form
        try? context.save()
    }

    private func deletePhoto(_ photos: [PhotoAsset], at index: Int) {
        guard photos.indices.contains(index) else { return }
        context.delete(photos[index])
        try? context.save()
    }

    private func locate() {
        locating = true
        locationError = nil
        locator.request { result in
            locating = false
            switch result {
            case .success(let location):
                form.latitude = location.coordinate.latitude
                form.longitude = location.coordinate.longitude
                try? context.save()
            case .failure(let error):
                locationError = error.localizedDescription
            }
        }
    }

    private func finish() {
        guard missing.isEmpty else { showMissing = true; return }
        if form.recommendedKW <= 0 { form.recommendedKW = SurveyOptions.autoKW(form) }
        if form.isDraft {
            form.isDraft = false
            form.createdAt = .now
            form.surveyor = userName
        }
        if let job = form.job, job.capacityKW == 0 { job.capacityKW = form.recommendedKW }
        try? context.save()
        dismiss()
    }

    private func discard() {
        let form = form, context = context
        dismiss()
        // Delete after the screen has gone so nothing reads the removed record.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            context.delete(form)
            try? context.save()
        }
    }
}

// MARK: - History & detail

struct SurveyHistoryView: View {
    @Query(filter: #Predicate<SurveyForm> { !$0.isDraft }, sort: \SurveyForm.createdAt, order: .reverse)
    private var surveys: [SurveyForm]

    var body: some View {
        List {
            if surveys.isEmpty {
                ContentUnavailableView("ยังไม่มีประวัติการสำรวจ", systemImage: "list.clipboard")
            }
            ForEach(surveys) { survey in
                NavigationLink { SurveyDetailView(survey: survey) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(survey.job?.code ?? "-") · \(survey.job?.projectName ?? "")").bold()
                        Text("\(survey.createdAt.thaiLongTime) · โดย \(survey.surveyor)")
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text("\(survey.roofType) · \(survey.roofAreaSqm.plain) ตร.ม. · เสนอ \(survey.recommendedKW.kw)")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Theme.navy)
                }
            }
        }
        .navigationTitle("ประวัติการสำรวจ")
    }
}

struct SurveyDetailView: View {
    let survey: SurveyForm

    private func orDash(_ s: String) -> String { s.isEmpty ? "-" : s }

    var body: some View {
        Form {
            Section {
                InfoRow(title: "โครงการ", value: survey.job?.projectName ?? "-")
                InfoRow(title: "วันที่สำรวจ", value: survey.createdAt.thaiLongTime)
                InfoRow(title: "ผู้สำรวจ", value: survey.surveyor)
                if let lat = survey.latitude, let lon = survey.longitude {
                    InfoRow(title: "พิกัด", value: String(format: "%.6f, %.6f", lat, lon))
                }
            }
            Section("หลังคา") {
                InfoRow(title: "ประเภท", value: orDash(survey.roofType))
                InfoRow(title: "พื้นที่", value: "\(survey.roofAreaSqm.plain) ตร.ม.")
                InfoRow(title: "ทิศทาง / ลาดชัน", value: "\(orDash(survey.orientation)) / \(survey.tiltDegree)°")
                InfoRow(title: "เงาบัง", value: orDash(survey.shading))
                InfoRow(title: "โครงสร้าง", value: survey.structureOK ? "รับน้ำหนักได้" : "ต้องเสริมโครงสร้าง")
            }
            Section("ระบบไฟฟ้า") {
                InfoRow(title: "การไฟฟ้า / CA", value: "\(orDash(survey.utility)) / \(orDash(survey.caNumber))")
                InfoRow(title: "มิเตอร์", value: [survey.meterPhase, survey.meterSize].filter { !$0.isEmpty }.joined(separator: " · "))
                InfoRow(title: "เมนเบรกเกอร์", value: survey.mainBreakerAmp > 0 ? "\(survey.mainBreakerAmp) A" : "-")
                InfoRow(title: "อัตราค่าไฟ", value: orDash(survey.tariff))
                if survey.monthlyKWh > 0 { InfoRow(title: "หน่วย/เดือน", value: "\(survey.monthlyKWh.plain) kWh") }
                InfoRow(title: "ค่าไฟ/เดือน", value: survey.monthlyBill > 0 ? "\(survey.monthlyBill.plain) บาท" : "-")
                InfoRow(title: "สายดินเดิม", value: orDash(survey.grounding))
                InfoRow(title: "ขนาดที่เสนอ", value: survey.recommendedKW.kw)
            }
            ForEach(SurveyOptions.photoTags) { tag in
                let photos = SurveyOptions.photos(survey, tag.id)
                if !photos.isEmpty {
                    Section("รูป\(tag.title)") {
                        PhotoGrid(images: photos.map(\.data)).padding(.vertical, 8)
                    }
                }
            }
            if !survey.notes.isEmpty {
                Section("หมายเหตุ") { Text(survey.notes) }
            }
        }
        .navigationTitle("แบบสำรวจ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { SurveyFormView(survey: survey) } label: { Text("แก้ไข") }
            }
        }
    }
}

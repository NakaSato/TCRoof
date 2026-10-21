import SwiftUI
import TCRoofUI
import SwiftData
import CoreLocation
import TCRoofCore
import ModuleRules

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

/// iPhone: the grouped form. iPad: cards from the components board (`SurveyFormView+Pad.swift`).
/// Both edit the same record; the bar, the checks and the actions are shared.
struct SurveyEditor: View {
    @Bindable var form: SurveyForm

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("userName") private var userName = "สมชาย"

    @State private var locator = LocationFetcher()
    @State var locating = false
    @State var locationError: String?
    @State private var showMissing = false
    @State private var showInstallStops = false
    @State private var confirmDiscard = false

    var missing: [String] { SurveyOptions.missing(form) }

    var body: some View {
        Group {
            if sizeClass == .compact { phoneForm } else { padForm }
        }
        // the phone's bar has room for the shorter title only
        .navigationTitle(form.isDraft ? (isPhone ? "แบบสำรวจ (ร่าง)" : "แบบสำรวจหน้างาน (ร่าง)") : "แก้ไขแบบสำรวจ")
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
        .tcPadNavBar(form.isDraft ? "แบบสำรวจหน้างาน (ร่าง)" : "แก้ไขแบบสำรวจ", trail: ["หน้าหลัก", "สำรวจหน้างาน"]) {
            HStack(spacing: 12) {
                if form.isDraft { TCButton("ทิ้งร่าง", systemImage: "trash", kind: .destructive) { confirmDiscard = true } }
                TCButton(form.isDraft ? "บันทึก" : "เสร็จ", action: finish)
            }
        }
        .alert("ยังบันทึกไม่ได้ตามคู่มือติดตั้งแผง", isPresented: $showInstallStops) {
            Button("แก้ไขต่อ", role: .cancel) {}
            if form.isDraft { Button("เก็บเป็นร่างไว้ก่อน") { dismiss() } }
        } message: {
            Text(installStops.joined(separator: "\n"))
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
        #if DEBUG
        // `-installCheckDemo YES`: example answers for the installation checks (Bangkok, a 5° plan, near the sea)
        .task {
            guard UserDefaults.standard.bool(forKey: "installCheckDemo") else { return }
            form.latitude = form.latitude ?? 13.7563; form.longitude = form.longitude ?? 100.5018
            var c = SiteInstallCheck()
            c.plannedTiltDeg = 5; c.altitudeM = 12; c.seaDistance = .to1km; c.humidityPct = 80; c.monthlyMinC = 21; c.monthlyMaxC = 36
            c.tMinC = 15; c.roofFireproof = false; c.rearClearanceMm = 100; c.edgeSafeZoneM = 0.6; c.highWind = true
            c.shadingSources = ["ต้นไม้"]; c.reasons = ["ZN-73b": "ใช้แผงกันเกลือและอุปกรณ์สแตนเลส"]
            installCheck = c
        }
        #endif
    }

    // MARK: iPhone

    private var phoneForm: some View {
        PadForm {
            PadSection {
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
            installSection
            photoSections

            PadSection("หมายเหตุ") {
                TextField("รายละเอียดเพิ่มเติม", text: $form.notes, axis: .vertical).lineLimit(3...8)
            }

            if !missing.isEmpty {
                PadSection("ยังขาด \(missing.count) รายการ") {
                    ForEach(missing, id: \.self) { TCMissingLine($0) }
                }
            }
        }
    }

    // MARK: Sections

    private var locationSection: some View {
        PadSection("ตำแหน่งหน้างาน") {
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
                Text(locationError).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
            }
        }
    }

    private var roofSection: some View {
        PadSection("ข้อมูลหลังคา") {
            PadPicker("ประเภทหลังคา", selection: $form.roofType) {
                Text("เลือก").tag("")
                ForEach(SurveyOptions.roofTypes, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("พื้นที่หลังคาที่ใช้ได้ (ตร.ม.)") {
                TextField("กรอก", value: optional(\.roofAreaSqm), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            PadPicker("ทิศทางหลังคา", selection: $form.orientation) {
                Text("เลือก").tag("")
                ForEach(SurveyOptions.orientations, id: \.self) { Text($0).tag($0) }
            }
            Stepper("ความลาดชัน \(form.tiltDegree)°", value: $form.tiltDegree, in: 0...60)
            PadPicker("เงาบัง", selection: $form.shading) {
                Text("เลือก").tag("")
                ForEach(SurveyOptions.shadings, id: \.self) { Text($0).tag($0) }
            }
            Toggle("โครงสร้างหลังคารับน้ำหนักได้", isOn: $form.structureOK)
        }
    }

    private var electricalSection: some View {
        PadSection("ระบบไฟฟ้า") {
            VStack(alignment: .leading, spacing: 6) {
                Text("การไฟฟ้า").foregroundStyle(Theme.inkMuted)
                TCSegmented(SurveyOptions.utilities, selection: $form.utility).accessibilityLabel("การไฟฟ้า")
            }
            LabeledContent("เลขผู้ใช้ไฟฟ้า (CA)") {
                TextField("ดูจากบิลค่าไฟ", text: $form.caNumber)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ระบบมิเตอร์").foregroundStyle(Theme.inkMuted)
                TCSegmented(["1 เฟส", "3 เฟส"], selection: $form.meterPhase).accessibilityLabel("ระบบมิเตอร์")
            }
            LabeledContent("ขนาดมิเตอร์") {
                TextField("เช่น 15(45) A", text: $form.meterSize).multilineTextAlignment(.trailing)
            }
            PadPicker("เมนเบรกเกอร์", selection: $form.mainBreakerAmp) {
                Text("เลือก").tag(0)
                ForEach(breakerOptions, id: \.self) { Text("\($0) A").tag($0) }
            }
            PadPicker("อัตราค่าไฟ", selection: $form.tariff) {
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
            PadPicker("สายดินเดิม", selection: $form.grounding) {
                Text("ไม่ระบุ").tag("")
                ForEach(SurveyOptions.groundings, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    /// Standard sizes, plus the stored value when an older record used another size.
    var breakerOptions: [Int] {
        let current = form.mainBreakerAmp
        return current > 0 && !SurveyOptions.breakers.contains(current)
            ? (SurveyOptions.breakers + [current]).sorted() : SurveyOptions.breakers
    }

    private var sizingSection: some View {
        PadSection("ขนาดระบบที่เสนอ") {
            LabeledContent("ขนาดแนะนำจากการใช้ไฟ", value: SurveyOptions.suggestedKW(form).kw)
            LabeledContent("ขนาดสูงสุดตามพื้นที่หลังคา", value: SurveyOptions.maxKWByRoof(form).kw)
            LabeledContent("ขนาดที่เสนอ (kWp)") {
                TextField(SurveyOptions.autoKW(form).plain, value: optional(\.recommendedKW), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .bold()
            }
        } footer: {
            Text("ใช้หน่วย kWh ถ้ากรอก ไม่เช่นนั้นคิดจากค่าไฟ 4.5 บาท/หน่วย | ใช้ไฟกลางวัน 60% | แดดเฉลี่ย 4 ชม./วัน | เว้นว่างเพื่อใช้ค่าที่คำนวณ")
        }
    }

    private var photoSections: some View {
        ForEach(SurveyOptions.photoTags) { tag in
            let photos = SurveyOptions.photos(form, tag.id)
            PadSection("รูป\(tag.title)") {
                VStack(alignment: .leading, spacing: 8) {
                    if tag.required {
                        Text(photos.isEmpty ? "จำเป็น" : "ครบ").font(.sarabun(12.5, .bold, relativeTo: .caption))
                            .foregroundStyle(photos.isEmpty ? Theme.pending : Theme.okText)
                    }
                    PhotoPickerSection(images: photos.map(\.data),
                                       onAdd: { addPhoto($0, tag: tag.id) },
                                       onDelete: { index in deletePhoto(photos, at: index) })
                }
            }
        }
    }

    // MARK: Actions

    /// A number field that shows empty for 0 instead of a made-up value.
    func optional(_ keyPath: ReferenceWritableKeyPath<SurveyForm, Double>) -> Binding<Double?> {
        Binding(get: { form[keyPath: keyPath] > 0 ? form[keyPath: keyPath] : nil },
                set: { form[keyPath: keyPath] = max($0 ?? 0, 0) })
    }

    func addPhoto(_ data: Data, tag: String) {
        let photo = PhotoAsset(data: data, tag: tag)
        context.insert(photo)
        photo.survey = form
        try? context.save()
    }

    func deletePhoto(_ photos: [PhotoAsset], at index: Int) {
        guard photos.indices.contains(index) else { return }
        context.delete(photos[index])
        try? context.save()
    }

    func locate() {
        locating = true
        locationError = nil
        locator.request { result in
            locating = false
            switch result {
            case .success(let location):
                form.latitude = location.coordinate.latitude
                form.longitude = location.coordinate.longitude
                // the altitude comes with the fix, when GPS has one and the check has none
                if location.verticalAccuracy >= 0, installCheck.altitudeM == nil {
                    var c = installCheck; c.altitudeM = (location.altitude).rounded(); installCheck = c
                }
                try? context.save()
            case .failure(let error):
                locationError = error.localizedDescription
            }
        }
    }

    private func finish() {
        guard missing.isEmpty else { showMissing = true; return }
        // ZNSHINE's manual: a block stops the save, a warn needs the engineer's reason
        guard installStops.isEmpty else { showInstallStops = true; return }
        stampInstallCheck()
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

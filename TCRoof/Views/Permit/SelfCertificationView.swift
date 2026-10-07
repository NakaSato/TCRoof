import SwiftUI
import TCRoofUI
import TCRoofCore

/// แบบฟอร์มรับรองตนเอง VSPP 2569 (12 pages: the statement, signatures and attachments 1–10) of one job.
/// The printout is the original PEA pages with the answers, ticks and photos on them.
struct SelfCertificationView: View {
    let job: Job

    @State private var form = SelfCertification()
    @State private var loaded = false
    /// Photo data by file name, read once from the job's permit folder.
    @State private var photoData: [String: Data] = [:]
    /// The photo open in the editor.
    @State private var editing: EditTarget?

    struct EditTarget: Identifiable {
        let attachment: Int
        let file: String
        var id: String { file }
    }
    private let map = PermitFormMap.load(PermitFormMap.selfCertification)
    static let file = "selfcert"

    var body: some View {
        if let map {
            PermitFormScaffold(title: "แบบฟอร์มรับรองตนเอง", job: job, map: map, issues: form.issues,
                               fileName: "แบบฟอร์มรับรองตนเอง-\(job.code).pdf", version: AnyHashable(version),
                               content: content) {
                producerCard
                systemCard
                ForEach(1...10, id: \.self) { attachmentCard($0) }
                signCard
            }
            .task { load() }
            .onChange(of: form) { _, new in if loaded { PermitStore(job: job).save(new, Self.file) } }
            .sheet(item: $editing) { target in editor(target) }
        } else {
            ContentUnavailableView("ไม่พบแบบฟอร์ม", systemImage: "doc.questionmark")
        }
    }

    private var version: Data { (try? JSONEncoder().encode(form)) ?? Data() }

    private func content() -> PermitRenderer.Content {
        var pages: [String: PermitRenderer.AttachmentPage] = [:]
        for n in 1...10 {
            // attachment 2 stays empty when no limiter is needed (the form says so)
            if n == 2 && form.exportLimiter == .notRequired { continue }
            var page = PermitRenderer.AttachmentPage(layout: form.layout(n), captions: form.captionsOn(n))
            for (i, file) in form.printedPhotos(n).enumerated() {
                guard let image = photoData[file].flatMap(UIImage.init(data:)) else { continue }
                let info = form.info(file)
                page.items.append(.init(image: image.turned(info.quarterTurns), fit: form.fit(file, attachment: n),
                                        highlights: info.highlights, caption: form.caption(attachment: n, index: i)))
            }
            pages["att\(n)"] = page
        }
        return PermitRenderer.Content(values: form.values, marks: form.marks, attachments: pages)
    }

    private func load() {
        guard !loaded else { return }
        let store = PermitStore(job: job)
        if let saved = store.load(SelfCertification.self, Self.file) {
            form = saved
            for name in saved.photos.flatMap({ $0 }) { photoData[name] = store.photo(name) }
        } else {
            form.producerName = job.customerName
            form.phone = job.phone
            form.address = [job.address, job.province].filter { !$0.isEmpty }.joined(separator: " ")
            if job.capacityKW > 0 { form.pvKWp = String(format: "%.2f", job.capacityKW) }
        }
        loaded = true
    }

    // MARK: Cards

    private var producerCard: some View {
        PermitSection(title: "ผู้ผลิตไฟฟ้าและสัญญา", subtitle: "ผู้ผลิตไฟฟ้า คือผู้เป็นเจ้าของมิเตอร์") {
            PermitField("ชื่อผู้ผลิตไฟฟ้า", text: $form.producerName, required: true)
            PermitField("เลขที่คำขอในระบบ PPIM (ต่อจาก PPIM1A6)", text: $form.ppimSuffix, required: true)
            PermitRow {
                PermitField("สัญญาซื้อขายไฟฟ้า เลขที่", text: $form.contractNo, required: true)
                PermitField("ลงวันที่", text: $form.contractDate, required: true)
            }
            PermitField("หมายเลขผู้ใช้ไฟฟ้า", text: $form.caNo, required: true, keyboard: .numberPad)
            PermitRow {
                PermitField("เบอร์โทรศัพท์", text: $form.phone, required: true, keyboard: .phonePad)
                PermitField("อีเมล", text: $form.email, required: true, keyboard: .emailAddress)
            }
            PermitField("สถานที่ติดตั้งระบบผลิตไฟฟ้า เลขที่", text: $form.address, required: true)
        }
    }

    private var systemCard: some View {
        PermitSection(title: "ขนาดระบบ") {
            PermitRow {
                PermitField("แผง PV", text: $form.pvKWp, required: true, keyboard: .decimalPad, unit: "kWp")
                PermitField("Inverter", text: $form.inverterKW, required: true, keyboard: .decimalPad, unit: "kW")
            }
            PermitField("ปริมาณกำลังไฟฟ้าเสนอขาย", text: $form.sellKW, required: true, keyboard: .decimalPad, unit: "kW",
                        error: (Double(form.sellKW) ?? 0) > 5 ? "เสนอขายได้ไม่เกิน 5 kW" : nil)
            VStack(alignment: .leading, spacing: 6) {
                TCFieldLabel("การเชื่อมต่อ", required: true)
                HStack(spacing: Space.s) {
                    ForEach(SelfCertification.Phase.allCases, id: \.self) { p in
                        TCChoiceChip(p.title, selected: form.phase == p) { form.phase = p }
                    }
                }
            }
            limiterNote
        }
    }

    @ViewBuilder private var limiterNote: some View {
        switch form.exportLimiter {
        case nil:
            Text("กรอก Inverter ปริมาณเสนอขาย และการเชื่อมต่อ แล้วแอปจะเลือกช่องในเอกสารแนบ 2 ให้")
                .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        case .notRequired?:
            TCStatusChip("ไม่ต้องติด Export Limiting Device · ไม่ต้องแนบรูปข้อ 2", kind: .ok)
        case let limiter?:
            TCStatusChip(limiter == .singleOver7 ? "ต้องติด Export Limiting Device (เฟสเดียว > 7 kW)"
                                                 : "ต้องติด Export Limiting Device (หลายเฟส > 10 kW)", kind: .pending)
        }
    }

    private func attachmentCard(_ n: Int) -> some View {
        let skip = n == 2 && form.exportLimiter == .notRequired
        return PermitSection(title: "เอกสารแนบ \(n)", subtitle: SelfCertification.attachments[n - 1]) {
            if n == 1 {
                PermitRow {
                    PermitField("Latitude", text: $form.latitude, required: true, keyboard: .numbersAndPunctuation)
                    PermitField("Longitude", text: $form.longitude, required: true, keyboard: .numbersAndPunctuation)
                }
                if !(form.latitude.isEmpty && form.longitude.isEmpty) && !form.coordinatesValid {
                    Text("พิกัดควรอยู่ในประเทศไทย (Lat 5–21, Lng 97–106)")
                        .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
                }
            }
            if n == 6 {
                ForEach(1...3, id: \.self) { i in
                    TCRadioCard(SelfCertification.overcurrentOptions[i - 1], selected: form.overcurrent == i) { form.overcurrent = i }
                }
            }
            if skip {
                Text("ไม่เข้าเงื่อนไข ไม่ต้องแนบรูปถ่ายในหัวข้อนี้")
                    .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkMuted)
            } else {
                photoBlock(n)
            }
        }
    }

    /// Add / delete, then the page layout and the order the photos take in it.
    @ViewBuilder private func photoBlock(_ n: Int) -> some View {
        let images = form.photos[n - 1].compactMap { photoData[$0] }
        PhotoPickerSection(images: images,
                           onAdd: { addPhoto($0, to: n) },
                           onDelete: { removePhoto(at: $0, from: n) })
        Text(images.count >= SelfCertification.maxPhotos ? "ครบ \(SelfCertification.maxPhotos) รูปแล้ว"
                                                         : "เก็บได้ \(SelfCertification.maxPhotos) รูปต่อหัวข้อ")
            .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.muted)
        if !images.isEmpty {
            PhotoLayoutPicker(selection: $form.layouts[n - 1], count: images.count)
            TCSwitchRow("คำบรรยายใต้รูป (รูปที่ \(n).1, \(n).2 …)", isOn: $form.showCaptions[n - 1])
            PhotoOrderStrip(images: images, capacity: form.layout(n).resolved(images.count).capacity,
                            move: { index, step in form.movePhoto(attachment: n, from: index, by: step) },
                            edit: { index in
                                let files = form.photos[n - 1]
                                if files.indices.contains(index) { editing = EditTarget(attachment: n, file: files[index]) }
                            })
        }
    }

    @ViewBuilder private func editor(_ target: EditTarget) -> some View {
        if let data = photoData[target.file], let index = form.photos[target.attachment - 1].firstIndex(of: target.file) {
            AttachmentPhotoEditor(attachment: target.attachment, index: index, data: data,
                                  info: Binding(get: { form.info(target.file) }, set: { form.photoInfo[target.file] = $0 }),
                                  defaultFit: SelfCertification.defaultFit(target.attachment))
        }
    }

    private func addPhoto(_ data: Data, to n: Int) {
        guard form.photos[n - 1].count < SelfCertification.maxPhotos else { return }
        let name = PermitStore(job: job).addPhoto(data)
        photoData[name] = data
        form.photos[n - 1].append(name)
    }

    private func removePhoto(at index: Int, from n: Int) {
        guard form.photos[n - 1].indices.contains(index) else { return }
        let name = form.photos[n - 1].remove(at: index)
        form.photoInfo[name] = nil
        PermitStore(job: job).deletePhoto(name)
        photoData[name] = nil
    }

    private var signCard: some View {
        PermitSection(title: "ผู้ลงนาม", subtitle: "ช่องลายเซ็นเว้นไว้ให้เซ็นจริง · วิศวกรลงนามรับรองทุกแผ่น") {
            PermitField("ชื่อวิศวกร (ตัวบรรจง)", text: $form.engineerName, required: true)
            dateRow("พิมพ์วันที่ลงนามของผู้ผลิตไฟฟ้า", $form.producerSignDate)
            dateRow("พิมพ์วันที่ลงนามของวิศวกร", $form.engineerSignDate)
        }
    }

    /// Off = the date is left for handwriting.
    private func dateRow(_ title: String, _ date: Binding<Date?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TCSwitchRow(title, isOn: Binding(get: { date.wrappedValue != nil },
                                             set: { date.wrappedValue = $0 ? Date() : nil }))
            if date.wrappedValue != nil {
                TCDateField(date: Binding(get: { date.wrappedValue ?? Date() }, set: { date.wrappedValue = $0 }),
                            accessibilityTitle: title)
            }
        }
    }
}

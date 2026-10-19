import SwiftUI
import SwiftData
import PhotosUI
import TCRoofUI
import TCRoofCore

/// One expense: its receipt, the values read from it (shown as suggestions until accepted), and the job it's charged to
/// (§B4). A new expense is saved only by `บันทึก`; a submitted month's is read only.
struct ExpenseEditor: View {
    /// nil for a new one.
    let expense: Expense?
    var receipt: Data? = nil
    var date: Date = .now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GoogleSession.self) private var session
    @Query(sort: \Job.installStart) private var jobs: [Job]

    @State private var category = TravelClaim.Category.fuel
    @State private var amountText = ""
    @State private var day = Date.now
    @State private var vendor = ""
    @State private var taxID = ""
    @State private var note = ""
    @State private var jobID: String?
    @State private var photo: Data?
    @State private var fillSource = "typed"
    @State private var proposal: ReceiptParser.Proposal?
    @State private var reading = false
    @State private var picked: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showViewer = false
    @State private var confirmDelete = false
    @State private var splitNotice: String?
    @State private var loaded = false

    private var locked: Bool { TravelStore.isLocked(context, month: TravelClaim.monthKey(day)) }
    private var amount: Int? { Self.satang(amountText) }

    /// "1,038.05" → 103805.
    static func satang(_ text: String) -> Int? {
        let t = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let v = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: v * 100).rounding(accordingToBehavior: nil).intValue
    }

    static func text(_ satang: Int) -> String { satang == 0 ? "" : String(format: "%.2f", Double(satang) / 100) }

    var body: some View {
        NavigationStack {
            Form {
                receiptSection
                if let proposal, !proposal.isEmpty, !locked { proposalSection(proposal) }
                Section("รายการ") {
                    Picker("ประเภท", selection: $category) {
                        ForEach(TravelClaim.Category.receipts) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    LabeledContent("จำนวนเงิน (บาท)") {
                        TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("expense.amount")
                    }
                    DatePicker("วันที่", selection: $day, displayedComponents: [.date, .hourAndMinute])
                    TextField("ร้าน / ผู้รับเงิน", text: $vendor)
                    TextField("เลขประจำตัวผู้เสียภาษี (ถ้าเป็นใบกำกับภาษี)", text: $taxID).keyboardType(.numberPad)
                    TextField("หมายเหตุ", text: $note, axis: .vertical)
                }
                .disabled(locked)
                jobSection
                if expense != nil, !locked {
                    Section {
                        Button("ลบรายการนี้", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .tcFormStyle()
            .navigationTitle(expense == nil ? "เพิ่มค่าใช้จ่าย" : "ค่าใช้จ่าย")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(locked ? "ปิด" : "ยกเลิก") { dismiss() } }
                if !locked {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("บันทึก") { save(); dismiss() }.disabled(amountText.isEmpty == false && amount == nil)
                    }
                }
            }
            .confirmationDialog("ลบค่าใช้จ่ายนี้?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("ลบ", role: .destructive) {
                    if let expense { context.delete(expense); try? context.save() }
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ReceiptCamera { pages in if let first = pages.first { setPhoto(first) } }
            }
            .fullScreenCover(isPresented: $showViewer) { if let photo { PhotoViewer(images: [photo], start: 0) } }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { setPhoto(ReceiptImage.jpeg(data)) }
                    picked = nil
                }
            }
            .tcToast($splitNotice)
            .task { load() }
        }
    }

    // MARK: sections

    private var receiptSection: some View {
        Section {
            if let photo {
                HStack(spacing: 14) {
                    Button { showViewer = true } label: {
                        Thumbnail(data: photo).frame(width: 84, height: 112)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ดูใบเสร็จ")
                    VStack(alignment: .leading, spacing: 6) {
                        if reading {
                            Label("กำลังอ่านใบเสร็จ…", systemImage: "text.viewfinder").foregroundStyle(Theme.muted)
                        } else if fillSource == "receipt" {
                            Label("กรอกจากใบเสร็จแล้ว", systemImage: "checkmark.seal").foregroundStyle(Theme.successText)
                        } else {
                            Button { Task { await read() } } label: { Label("อ่านจากใบเสร็จอีกครั้ง", systemImage: "text.viewfinder") }
                        }
                        if !locked {
                            Button("เอารูปออก", role: .destructive) { self.photo = nil; proposal = nil }
                        }
                    }
                }
            } else if !locked {
                Button { showCamera = true } label: { Label("ถ่ายใบเสร็จ", systemImage: "doc.viewfinder") }
                PhotosPicker(selection: $picked, matching: .images) { Label("เลือกรูปใบเสร็จจากคลังภาพ", systemImage: "photo") }
            } else {
                Text("ไม่มีใบเสร็จ").foregroundStyle(Theme.muted)
            }
        } header: { Text("ใบเสร็จ") }
    }

    private func proposalSection(_ p: ReceiptParser.Proposal) -> some View {
        Section {
            if let a = p.amount { LabeledContent("ยอดเงิน", value: TravelClaim.baht(a) + " บาท") }
            if let d = p.date { LabeledContent("วันที่", value: RoutineReport.thaiDate(d)) }
            if let c = p.category { LabeledContent("ประเภท", value: c.title) }
            if let v = p.vendor { LabeledContent("ร้าน", value: v) }
            if let t = p.taxID { LabeledContent("เลขภาษี", value: t) }
            Button { accept(p) } label: { Label("ใช้ค่านี้", systemImage: "checkmark.circle.fill") }
                .accessibilityIdentifier("expense.accept")
        } header: { Text("อ่านได้จากใบเสร็จ") } footer: { Text("ตรวจให้ตรงกับใบเสร็จก่อนกดใช้ แก้ทีหลังได้ทุกช่อง") }
    }

    private var jobSection: some View {
        Section {
            Picker("งาน", selection: $jobID) {
                Text("ไม่ระบุงาน").tag(String?.none)
                ForEach(dayJobs) { job in Text(TravelStore.label(job)).tag(job.syncID) }
                if let jobID, !dayJobs.contains(where: { $0.syncID == jobID }), let job = jobs.first(where: { $0.syncID == jobID }) {
                    Text(TravelStore.label(job)).tag(String?.some(jobID))
                }
            }
            .disabled(locked)
            if category == .fuel, !locked, (amount ?? 0) > 0, dayWeights.count > 1 {
                Button { splitByDistance() } label: { Label("แบ่งตามระยะทาง (\(dayWeights.count) งาน)", systemImage: "arrow.triangle.branch") }
            }
        } header: { Text("คิดเข้างาน") } footer: {
            Text("ใบเสร็จระหว่างอยู่ที่สถานีจะเลือกงานนั้นให้ ค่าน้ำมันแบ่งให้งานของวันนั้นตามระยะทางได้")
        }
    }

    // MARK: data

    /// The day's stations first, then the jobs with a survey or install on that day.
    private var dayJobs: [Job] {
        let trip = TravelStore.trip(context, on: day, create: false)
        let ids = trip?.stops.compactMap(\.jobID) ?? []
        var out = ids.compactMap { id in jobs.first { $0.syncID == id } }
        for j in jobs where !out.contains(where: { $0 === j }) && (j.surveyDate.isSameDay(day) || j.installDay(on: day) != nil) {
            out.append(j)
        }
        var seen = Set<ObjectIdentifier>()
        return out.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private var dayWeights: [(jobID: String, km: Double)] {
        guard let trip = TravelStore.trip(context, on: day, create: false) else { return [] }
        var w: [(jobID: String, km: Double)] = []
        for s in trip.stops {
            guard let id = s.jobID else { continue }
            if let i = w.firstIndex(where: { $0.jobID == id }) { w[i].km += s.legKm ?? 0 } else { w.append((id, s.legKm ?? 0)) }
        }
        return w
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let e = expense {
            category = e.category; amountText = Self.text(e.amount); day = e.date; vendor = e.vendor; taxID = e.taxID
            note = e.note; jobID = e.jobID; photo = e.receipt; fillSource = e.fillSource
            if photo == nil, let id = e.receiptDriveID { Task { await download(id) } }
        } else {
            day = date
            jobID = TravelStore.trip(context, on: date, create: false).flatMap { TravelClaim.jobAt(date, stops: $0.stops) }
            if let receipt { setPhoto(receipt) }
        }
        #if DEBUG
        if expense == nil, receipt == nil, UserDefaults.standard.bool(forKey: "travelReceiptStub") { setPhoto(ReceiptImage.stub()) }
        #endif
    }

    private func download(_ id: String) async {
        guard let data = try? await session.survey.driveDownload(id) else { return }
        photo = data
        expense?.receipt = data
    }

    private func setPhoto(_ data: Data) {
        photo = data
        fillSource = "typed"
        Task { await read() }
    }

    private func read() async {
        guard let photo else { return }
        reading = true
        let text = await TextReader.read(photo)
        reading = false
        proposal = ReceiptParser().parse(text)
        // a blank form takes what was read straight away; anything typed stays until the person accepts
        if let p = proposal, amountText.isEmpty, vendor.isEmpty, expense == nil { accept(p) }
    }

    private func accept(_ p: ReceiptParser.Proposal) {
        if let a = p.amount { amountText = Self.text(a) }
        if let d = p.date {
            // the receipt gives the day; the time stays the one it was taken
            let cal = TravelClaim.calendar
            let t = cal.dateComponents([.hour, .minute], from: day)
            day = cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: d) ?? d
        }
        if let c = p.category { category = c }
        if let v = p.vendor { vendor = v }
        if let t = p.taxID { taxID = t }
        fillSource = "receipt"
        proposal = nil
    }

    @discardableResult
    private func save() -> Expense {
        let e = expense ?? {
            let made = Expense(date: day, ownerEmail: TravelStore.owner, person: TravelStore.person, category: category)
            context.insert(made)
            return made
        }()
        e.category = category; e.amount = amount ?? 0; e.date = day; e.vendor = vendor.trimmingCharacters(in: .whitespaces)
        e.taxID = taxID.filter(\.isNumber); e.note = note; e.jobID = jobID; e.fillSource = fillSource
        if e.receipt != photo { e.receipt = photo; if photo == nil { e.receiptDriveID = nil } }
        try? context.save()
        return e
    }

    /// The fuel receipt split across the day's jobs by their leg distance: this expense keeps the first share, a copy
    /// takes each other one, all sharing the one receipt picture.
    private func splitByDistance() {
        guard let total = amount else { return }
        let parts = TravelClaim.split(total, by: dayWeights)
        guard let first = parts.first else { return }
        jobID = first.jobID
        amountText = Self.text(first.amount)
        note = note.isEmpty ? "แบ่งตามระยะทางจาก \(TravelClaim.baht(total)) บาท" : note
        let original = save()
        for part in parts.dropFirst() {
            let copy = Expense(date: original.date, ownerEmail: original.ownerEmail, person: original.person, category: .fuel, amount: part.amount)
            copy.vendor = original.vendor; copy.taxID = original.taxID; copy.note = original.note; copy.jobID = part.jobID
            copy.fillSource = original.fillSource
            context.insert(copy)
        }
        try? context.save()
        splitNotice = "แบ่งเป็น \(parts.count) รายการแล้ว รูปใบเสร็จอยู่ที่รายการแรก"
    }
}

/// The document camera where there is one, else the plain camera.
struct ReceiptCamera: View {
    let onScan: ([Data]) -> Void

    var body: some View {
        if ReceiptScanner.isSupported {
            ReceiptScanner(onScan: onScan).ignoresSafeArea()
        } else {
            StampedCamera { onScan([ReceiptImage.jpeg($0)]) }
        }
    }
}

private extension Date {
    func isSameDay(_ other: Date) -> Bool { TravelClaim.calendar.isDate(self, inSameDayAs: other) }
}

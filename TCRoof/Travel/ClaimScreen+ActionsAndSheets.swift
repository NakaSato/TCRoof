import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

extension ClaimScreen {

    // MARK: actions

    func shift(_ by: Int) {
        guard let start = TravelClaim.monthStart(month),
              let next = TravelClaim.calendar.date(byAdding: .month, value: by, to: start) else { return }
        month = TravelClaim.monthKey(next)
    }

    func stamp(_ kind: TravelClaim.StampKind, _ job: Job) async {
        stamping = job.syncID ?? job.code
        let result = await TravelStore.stamp(kind, job: job, context: context)
        stamping = nil
        switch result {
        case .undone?: notice = "ยกเลิกเวลาที่เพิ่งบันทึกแล้ว"
        case .nothingToClose?: notice = "ยังไม่ได้บันทึกเวลาถึงสถานีนี้"
        case .stamped?: notice = kind == .arrive ? "บันทึกเวลาถึงแล้ว | กดอีกครั้งภายใน 2 นาทีเพื่อยกเลิก" : "บันทึกเวลาออกแล้ว"
        case nil: notice = "เดือนนี้ยื่นเบิกแล้ว ถอนการยื่นก่อนจึงบันทึกได้"
        }
    }

    /// Each page of the document camera becomes an expense; one page opens its sheet, several are saved as read.
    func addScanned(_ pages: [Data]) {
        guard !pages.isEmpty else { return }
        if pages.count == 1 { newExpense = NewExpense(receipt: pages[0], date: defaultDate); return }
        Task {
            for data in pages {
                let p = ReceiptParser().parse(await TextReader.read(data))
                let date = p.date.flatMap { d in
                    TravelClaim.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: d)
                } ?? defaultDate
                let e = Expense(date: date, ownerEmail: TravelStore.owner, person: TravelStore.person, category: p.category ?? .other,
                                amount: p.amount ?? 0)
                e.vendor = p.vendor ?? ""; e.taxID = p.taxID ?? ""; e.receipt = data
                e.fillSource = p.isEmpty ? "typed" : "receipt"
                e.jobID = TravelStore.trip(context, on: date, create: false).flatMap { TravelClaim.jobAt(date, stops: $0.stops) }
                context.insert(e)
            }
            try? context.save()
            notice = "เพิ่มใบเสร็จ \(pages.count) ใบ | ตรวจยอดแต่ละใบก่อนยื่น"
        }
    }

    func exportFiles() {
        do { share = try ClaimExport(month: month, context: context).files() } catch { notice = "ส่งออกไม่สำเร็จ: \(error.localizedDescription)" }
    }

    func submit(_ signature: Data?) {
        ClaimExport(month: month, context: context).submit(signature: signature)
        Task { await upload() }
    }

    func upload() async {
        guard session.survey.google.isSignedIn else { notice = "ยื่นแล้ว | ยังไม่ได้เข้าสู่ระบบ Google จึงยังไม่ส่งขึ้น Drive"; return }
        uploading = true
        do {
            try await ClaimExport(month: month, context: context).upload(session.survey)
            notice = "ยื่นเบิกแล้ว | ส่งใบเบิกขึ้น Google Drive แล้ว"
        } catch {
            notice = "ยื่นแล้ว แต่ส่งขึ้น Drive ไม่สำเร็จ ลองใหม่ได้: \(error.localizedDescription)"
        }
        uploading = false
    }

    /// Receipts uploaded from the person's other device come down when the month is opened.
    func downloadReceipts() async {
        guard session.survey.google.isSignedIn else { return }
        for e in expenses where e.receipt == nil {
            guard let id = e.receiptDriveID, let data = try? await session.survey.driveDownload(id) else { continue }
            e.receipt = data
        }
        try? context.save()
    }
}

/// "09:42" or "–:–".
enum ClaimPagesTime {
    static func format(_ d: Date?) -> String {
        guard let d else { return "–:–" }
        let c = TravelClaim.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// `ยื่นเบิก`: what is being sent, the warnings left, and the claimant's signature (§B5).
struct ClaimSubmitSheet: View {
    let total: Int
    let warnings: Int
    let submit: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var signature: Data?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("ยอดเบิก \(TravelClaim.baht(total)) บาท").font(.sarabun(22, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                if warnings > 0 {
                    Label("ยังมี \(warnings) รายการที่ควรตรวจ ยื่นได้แต่ผู้อนุมัติจะเห็น", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warningText)
                }
                Text("ลงชื่อผู้เบิก").font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                // the canvas doesn't carry an identifier itself; its container does, for the UI test
                ZStack { AccountSignatureCanvas(signature: $signature) }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Theme.borderSubtle))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("claim.signature")
                HStack {
                    Button("ล้าง") { signature = nil }.buttonStyle(TCButtonStyle(.text))
                    Spacer()
                }
                MySignatureActions(signature: $signature)
                Text("เมื่อยื่นแล้ว รายการของเดือนนี้จะแก้ไม่ได้จนกว่าจะถอนการยื่น ใบเบิก PDF, Excel และรูปใบเสร็จจะส่งขึ้น Google Drive ของคุณ")
                    .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                Spacer()
                Button { submit(signature); dismiss() } label: { Label("ยื่นเบิก", systemImage: "paperplane.fill") }
                    .buttonStyle(TCButtonStyle(.primary, fullWidth: true))
                    .disabled(signature == nil)
                    .accessibilityIdentifier("claim.submit")
            }
            .padding(20)
            .tcPageBackground()
            .navigationTitle("ยื่นเบิก")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } } }
        }
    }
}

/// ตั้งค่าการเบิก: the company, the office the days start from, the usual vehicle and the private-car rate.
struct TravelSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TravelSettings.companyKey) private var company = "TCRoof"
    @AppStorage(TravelSettings.officeKey) private var office = "สำนักงาน"
    @AppStorage(TravelSettings.vehicleKey) private var vehicle = TravelClaim.Vehicle.company.rawValue
    @AppStorage(TravelSettings.plateKey) private var plate = ""
    @AppStorage(TravelSettings.rateKey) private var rate = TravelClaim.defaultRate
    @AppStorage(TravelSettings.returnKey) private var returnLeg = true
    @State private var officeSet = TravelSettings.officeLocation != nil
    @State private var locating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("ใบเบิก") { TextField("ชื่อบริษัท", text: $company) }
                Section {
                    TextField("ชื่อจุดออกเดินทาง", text: $office)
                    Button {
                        locating = true
                        Task {
                            if let l = await TravelStore.currentLocation() {
                                TravelSettings.setOffice(.init(latitude: l.lat, longitude: l.lon))
                                officeSet = true
                            } else { error = "หาตำแหน่งไม่ได้ ลองใหม่ที่สำนักงาน" }
                            locating = false
                        }
                    } label: {
                        HStack {
                            Label(officeSet ? "ตั้งตำแหน่งใหม่จากที่นี่" : "ตั้งตำแหน่งสำนักงานจากที่นี่", systemImage: "location")
                            if locating { Spacer(); ProgressView() }
                        }
                    }
                    if officeSet { Label("ตั้งตำแหน่งแล้ว", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.successText) }
                    Toggle("นับขากลับเข้าสำนักงาน", isOn: $returnLeg)
                } header: { Text("จุดออกเดินทาง") } footer: {
                    Text("ทุกวันเริ่มจากสำนักงาน ถ้าค้างคืน ปิดขากลับ หรือแก้จุดออกเดินทางของวันนั้นได้")
                }
                Section {
                    Picker("ยานพาหนะประจำ", selection: $vehicle) {
                        ForEach(TravelClaim.Vehicle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    TextField("ทะเบียนรถ", text: $plate)
                    LabeledContent("ค่าเดินทางรถส่วนตัว (บาท/กม.)") {
                        TextField("5", value: $rate, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } header: { Text("ยานพาหนะ") } footer: {
                    Text("อัตราใช้กับการเดินทางที่บันทึกต่อจากนี้ วันที่บันทึกไปแล้วแก้อัตราได้ในวันนั้น")
                }
            }
            .tcFormStyle()
            .navigationTitle("ตั้งค่าการเบิก")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
            .alert("ตำแหน่ง", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("ตกลง") {}
            } message: { Text(error ?? "") }
        }
    }
}

import SwiftUI
import QuickLook
import TCRoofUI
import TCRoofCore

extension Job {
    /// What a drafted station paper says about this station.
    var stationFacts: StationDocs.Facts {
        let place = province.isEmpty || address.contains(province) ? address : [address, "จ." + province].filter { !$0.isEmpty }.joined(separator: " ")
        return StationDocs.Facts(station: projectName, address: place, capacityKW: capacityKW, company: routineSettings.contractor)
    }

    /// The letterhead of a station paper: the company kept in the library, or the contractor's name alone.
    var stationLetterhead: HomeCompany {
        let kept = PermitStore.library.load(HomeLibrary.self, PermitStore.libraryFile)?.company ?? HomeCompany()
        guard kept.isEmpty else { return kept }
        var c = HomeCompany()
        c.nameTH = routineSettings.contractor
        return c
    }
}

/// ร่างหนังสือแจ้งดับไฟ: the number, who it goes to, the outage's day and hours, the text and who signs. The answers
/// are kept on the station as they change; `บันทึกเป็นไฟล์` hands the PDF back to become the paper's file.
struct OutageLetterSheet: View {
    @Bindable var job: Job
    /// Called with the letter's PDF when the team keeps it.
    let keep: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = StationDocs.OutageLetter()
    @State private var loaded = false
    @State private var preview: URL?

    private var facts: StationDocs.Facts { job.stationFacts }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                letterSection
                outageSection
                textSection
                signSection
                PadSection {
                    if !form.issues.isEmpty {
                        Text("ยังขาด: " + form.issues.joined(separator: " · "))
                            .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
                    }
                    Button { open() } label: { Label("ดูตัวอย่าง PDF", systemImage: "doc.text.magnifyingglass") }
                        .frame(minHeight: touchMin)
                    Button { keep(pdf()); dismiss() } label: { Label("บันทึกเป็นไฟล์ของเอกสาร", systemImage: "square.and.arrow.down") }
                        .frame(minHeight: touchMin)
                } footer: {
                    Text("ไฟล์เก็บในแฟ้มเอกสารของงาน สถานะเป็น “ร่างแล้ว” · พิมพ์แล้วลงนามบนกระดาษ")
                }
            }
            .navigationTitle("ร่างหนังสือแจ้งดับไฟ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } } }
            .quickLookPreview($preview)
            .onAppear { form = job.stationDocs.outageLetter ?? StationDocs.OutageLetter(); loaded = true }
            .onChange(of: form) { _, new in
                guard loaded else { return }
                var station = job.stationDocs
                station.outageLetter = new
                job.stationDocs = station
            }
        }
    }

    private var letterSection: some View {
        PadSection("หนังสือ") {
            LabeledContent("เลขที่") {
                TextField("TC-PML-001/2569", text: $form.number).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("outage.number")
            }
            DatePicker("ลงวันที่", selection: Binding(get: { form.date ?? .now }, set: { form.date = $0 }), displayedComponents: .date)
            LabeledContent("เรียน") {
                TextField("ผู้รับหนังสือ", text: $form.to, axis: .vertical).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("outage.to")
            }
        }
    }

    private var outageSection: some View {
        PadSection("ดับไฟ") {
            if let day = form.outageDay {
                DatePicker("วันที่ดับไฟ", selection: Binding(get: { day }, set: { form.outageDay = $0 }), displayedComponents: .date)
            } else {
                Button("กำหนดวันที่ดับไฟ") { form.outageDay = .now }.frame(minHeight: touchMin)
            }
            DatePicker("เริ่ม", selection: clock(\.start), displayedComponents: .hourAndMinute)
            DatePicker("ถึง", selection: clock(\.end), displayedComponents: .hourAndMinute)
            if !form.duration.isEmpty { LabeledContent("รวม", value: form.duration) }
        }
    }

    private var textSection: some View {
        PadSection("ข้อความ") {
            TextEditor(text: Binding(get: { form.body.isEmpty ? form.standardBody(facts) : form.body },
                                     set: { form.body = $0 == form.standardBody(facts) ? "" : $0 }))
                .font(.sarabun(15, relativeTo: .subheadline)).frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("outage.body")
            if !form.body.isEmpty { Button("ใช้ข้อความมาตรฐาน") { form.body = "" }.frame(minHeight: touchMin) }
        } footer: {
            Text(form.body.isEmpty ? "ข้อความมาตรฐานเปลี่ยนตามวันและเวลาด้านบน · แก้ได้ แล้วแอปจะใช้ข้อความที่แก้"
                                   : "ใช้ข้อความที่แก้เอง วันและเวลาด้านบนไม่เปลี่ยนข้อความนี้แล้ว")
        }
    }

    private var signSection: some View {
        PadSection("ผู้ลงนาม") {
            LabeledContent("ชื่อ") {
                TextField("ชื่อ นามสกุล", text: $form.signer).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("outage.signer")
            }
            LabeledContent("ตำแหน่ง") { TextField("ตำแหน่ง", text: $form.position).multilineTextAlignment(.trailing) }
        }
    }

    /// A time of day picker over minutes after midnight.
    private func clock(_ key: WritableKeyPath<StationDocs.OutageLetter, Int>) -> Binding<Date> {
        let cal = Calendar.current
        return Binding(
            get: { cal.date(bySettingHour: form[keyPath: key] / 60, minute: form[keyPath: key] % 60, second: 0, of: .now) ?? .now },
            set: { let c = cal.dateComponents([.hour, .minute], from: $0); form[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }

    private func pdf() -> Data {
        StationPaperRenderer.pdf(form.letter(facts), company: job.stationLetterhead)
    }

    private func open() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("หนังสือแจ้งดับไฟ-\(job.code).pdf".replacingOccurrences(of: "/", with: "-"))
        if (try? pdf().write(to: url, options: .atomic)) != nil { preview = url }
    }
}

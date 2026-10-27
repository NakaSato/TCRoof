import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ExcelExport

/// `เริ่มจากแม่แบบ` (ตั้งค่าแผน): a station's plan file from the team's set (`MPTemplates`, the 102 PWA stations), opened on
/// this station's own (by its code, else its name) and searchable by code, station or สาขา, HV / LV and size. It goes on the
/// job as an import of that file would (`MPWorkbookFlow.install`): kept with the file's dates and progress
/// (`ใช้วันและความคืบหน้าตามไฟล์`), or moved to a kickoff with no progress; booked progress stays under the new weights, and the
/// file becomes the station's plan workbook for export. The station's own file also fills the project facts it leaves
/// empty (`ProjectSetup`: สาขา, Inverter, กันย้อน, PPIM, วิศวกร, ผรม. …); another station's gives none.
///
/// `แม่แบบตามกรณี`: a station without a file of its own starts from one of the 20 install cases (`MPTemplates.installCases`),
/// picked by its main site type (`MPTemplates.mainSite`: the daily reports' locations), where its zero export sits and its
/// inverter size (`MPTemplates.suggest`), moved to the kickoff, with that site type's 2.1 steps and none of the case's example
/// figures.
struct MPTemplateSheet: View {
    @Bindable var job: Job
    /// The kickoff and size the setup sheet has so far.
    let input: MasterSchedule.Input
    /// The job's new plan, for the setup sheet to go on from.
    let applied: (MasterSchedule.Input) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var cases: [MPTemplates.Case] = []
    /// The 20 install cases, and the case the station's facts point to.
    @State private var installCases: [MPTemplates.Case] = []
    @State private var caseSite = ""
    @State private var caseBackfeed = "HV"
    @State private var caseBig = false
    @State private var loaded = false
    @State private var own: String?
    @State private var pickedID: String?
    @State private var search = ""
    /// 0 every station, 1 HV, 2 LV.
    @State private var backfeed = 0
    /// 0 every size, 1 under 200 kVA, 2 from 200 kVA.
    @State private var size = 0
    @State private var keepFile = true
    @State private var kickoff: Date
    @State private var working = false
    @State private var failure: String?

    init(job: Job, input: MasterSchedule.Input, applied: @escaping (MasterSchedule.Input) -> Void) {
        self.job = job; self.input = input; self.applied = applied
        _kickoff = State(initialValue: MasterSchedule.calendar.startOfDay(for: input.kickoff))
    }

    private var picked: MPTemplates.Case? { (cases + installCases).first { $0.id == pickedID } }

    /// The site types of the cases, in the files' order.
    private var caseSites: [String] {
        var seen = Set<String>()
        return installCases.map(\.site).filter { seen.insert($0).inserted }
    }

    private var suggestedCase: MPTemplates.Case? {
        MPTemplates.suggest(site: caseSite, backfeed: caseBackfeed, over200kVA: caseBig, among: installCases)
    }

    private var shown: [MPTemplates.Case] {
        cases.filter { c in
            c.matches(search)
                && (backfeed == 0 || c.backfeed == (backfeed == 1 ? "HV" : "LV"))
                && (size == 0 || c.over200kVA == (size == 2))
        }
    }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                if !loaded {
                    PadSection { HStack { ProgressView(); Text("กำลังอ่านแผนของสถานี…").foregroundStyle(Theme.inkMuted) } }
                } else {
                    if let o = cases.first(where: { $0.id == own }) {
                        PadSection("สถานีของงานนี้") { row(o) }
                    }
                    if !installCases.isEmpty { caseSection }
                    PadSection("เลือกจากทุกสถานี (\(cases.count))") {
                        TextField("ค้นหารหัส ชื่อสถานี หรือสาขา", text: $search)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("mpTemplate.search")
                        Picker("กันย้อน", selection: $backfeed) {
                            Text("ทุกแบบ").tag(0); Text("HV").tag(1); Text("LV").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("mpTemplate.backfeed")
                        Picker("Inverter", selection: $size) {
                            Text("ทุกขนาด").tag(0); Text("ต่ำกว่า 200 kVA").tag(1); Text("ตั้งแต่ 200 kVA").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("mpTemplate.inverter")
                        if shown.isEmpty {
                            Text("ไม่มีสถานีที่ตรงกับที่ค้นหา").foregroundStyle(Theme.inkMuted)
                        }
                        ForEach(shown) { row($0) }
                    }
                    PadSection("วันของแผน") {
                        Toggle("ใช้วันและความคืบหน้าตามไฟล์", isOn: $keepFile).tint(Theme.primary)
                            .disabled(picked?.site.isEmpty == false)
                            .accessibilityIdentifier("mpTemplate.keepFile")
                        if !keepFile { DatePicker("Kick off", selection: $kickoff, displayedComponents: .date) }
                    } footer: {
                        Text(keepFile ? "แผนและงานที่เสร็จแล้วตามไฟล์ของสถานี เหมือนนำเข้าไฟล์นั้น"
                             : "ทุกงานเลื่อนตามวัน Kick off ระยะเวลาและน้ำหนักตามไฟล์ ไม่เอาความคืบหน้าในไฟล์มา")
                    }
                    PadSection("แผนที่จะได้") {
                        if let c = picked {
                            LabeledContent(c.id, value: c.title)
                                .accessibilityIdentifier("mpTemplate.case")
                        } else {
                            Text("เลือกสถานีด้านบน").foregroundStyle(Theme.inkMuted)
                        }
                    } footer: {
                        Text([job.scheduleInput != nil ? "แทนแผน MP เดิมของสถานีนี้ ความก้าวหน้าที่บันทึกไว้คงอยู่ตามน้ำหนักใหม่" : nil,
                              pickedID != nil && pickedID == own ? "ข้อมูลโครงการที่ยังว่าง (สาขา Inverter กันย้อน PPIM วิศวกร ผรม.) เติมตามไฟล์ของสถานี" : nil]
                            .compactMap { $0 }.joined(separator: "\n"))
                    }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("เริ่มจากแม่แบบ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("ใช้แผนนี้", action: apply).disabled(picked == nil)
                            .accessibilityIdentifier("mpTemplate.apply")
                    }
                }
            }
            .alert("ใช้แผนนี้ไม่ได้", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("ตกลง", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
            .task { await load() }
        }
    }

    /// `แม่แบบตามกรณี`: the case for the site type, zero export and size picked, which start from the station's facts.
    private var caseSection: some View {
        PadSection("แม่แบบตามกรณี (\(installCases.count))") {
            Picker("ประเภทหน้างาน", selection: $caseSite) {
                ForEach(caseSites, id: \.self) { Text($0).tag($0) }
            }
            .accessibilityIdentifier("mpTemplate.caseSite")
            Picker("กันย้อน", selection: $caseBackfeed) {
                Text("กันย้อน HV").tag("HV"); Text("กันย้อน LV").tag("LV")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mpTemplate.caseBackfeed")
            Picker("Inverter", selection: $caseBig) {
                Text("ต่ำกว่า 200 kVA").tag(false); Text("ตั้งแต่ 200 kVA (พค.2)").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mpTemplate.caseSize")
            if let c = suggestedCase { row(c) } else { Text("ไม่มีแม่แบบของกรณีนี้").foregroundStyle(Theme.inkMuted) }
        } footer: {
            Text("สำหรับสถานีที่ยังไม่มีไฟล์ของตัวเอง: ทุกงานเลื่อนตามวัน Kick off งาน 2.1 ตามประเภทหน้างาน ใบอนุญาตตามกันย้อนและขนาด Inverter ไม่เอาข้อมูลตัวอย่างในไฟล์")
        }
        .onChange(of: [caseSite, caseBackfeed, caseBig ? "1" : "0"]) {
            // a case already picked follows the pickers
            if picked?.site.isEmpty == false { pickedID = suggestedCase?.id }
        }
    }

    /// A station: code, name, kWp and its line; a tap picks it.
    private func row(_ c: MPTemplates.Case) -> some View {
        let on = c.id == pickedID
        return Button {
            pickedID = c.id
            // an example case has no dates of its own to keep
            if !c.site.isEmpty { keepFile = false }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.primary : Theme.inkMuted)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(c.id).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                        Text(c.title).font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                        // a case's kWp is its example's
                        if let k = c.kWp, c.site.isEmpty { Text("\(k.formatted()) kWp").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted) }
                    }
                    Text([c.site.isEmpty ? c.branch : "แม่แบบ", "กันย้อน " + c.backfeed, c.over200kVA ? "ต้องยื่น พค.2" : "ไม่ต้อง พค.2"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mpTemplate.row." + c.id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load() async {
        cases = await Task.detached { MPTemplates.cases() }.value
        installCases = await Task.detached { MPTemplates.installCases() }.value
        // the case from the station's facts: its main site type, its zero export and its size
        let station = job.stationDocs
        caseSite = MPTemplates.mainSite(points: [], locations: job.routineSettings.locations, among: caseSites) ?? caseSites.first ?? ""
        caseBackfeed = station.zeroExport == "LV" ? "LV" : "HV"
        caseBig = input.over200kVA
        // the station's own file first (by its code in the 102-station list, else by name)
        own = MPTemplates.best(for: job.stationName, code: [job.code, station.code ?? ""].joined(separator: " "), in: cases)?.id
        pickedID = own ?? suggestedCase?.id
        // no file of its own: a case (or another station's plan), moved to this one's kickoff
        if own == nil { keepFile = false }
        loaded = true
    }

    private func apply() {
        guard let c = picked else { return }
        working = true
        // a case's own dates are its example's: it always moves to the kickoff
        let kickoff = kickoff, keep = keepFile && c.site.isEmpty
        Task {
            defer { working = false }
            do {
                let r = try await Task.detached { try MPTemplates.plan(c, kickoff: keep ? nil : kickoff) }.value
                // the station's own file fills its empty project facts; another station's are not this one's
                let setup = c.id == own ? ProjectSetup.defaultFields(job.setupChanges(r.imported.setup)) : []
                MPWorkbookFlow.install(r.imported, data: r.data, name: "แผนงาน MP \(job.stationName) (\(keep ? "" : "แม่แบบ ")\(c.id)).xlsx",
                                       on: job, setup: setup)
                try? context.save()
                if let new = job.scheduleInput { applied(new) }
                dismiss()
            } catch {
                failure = (error as? MPWorkbook.Failure)?.message ?? error.localizedDescription
            }
        }
    }
}

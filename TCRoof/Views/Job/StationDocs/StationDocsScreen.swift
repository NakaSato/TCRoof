import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

/// เอกสารสถานี กปภ.: every paper the station needs, by submission (ขนานไฟ, พค.2, อาคาร, ทดสอบ, ส่งมอบ), with who makes
/// or signs it, where it stands and its file; plus the ERC พค.2 check list ticked from those states.
struct StationDocsScreen: View {
    @Bindable var job: Job

    enum Pane: Hashable { case package(StationDocs.Package), checklist, erc }

    @State private var tab: Pane = .package(.gridConnection)
    @State private var library = StationDocsStore.loadLibrary()
    @State private var editing: StationDocs.Kind?
    @State private var showStation = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var ctx: StationDocs.Context { job.stationContext }

    /// The station's papers and the ERC flow are the team's (`stationdocs.drafts`, `erc.flow_record`).
    @Environment(\.permissions) private var permissions

    /// A contractor views their station's papers: nothing changes here (firestore.rules refuse their job edits).
    private var readOnly: Bool { !permissions.can(.stationDocsDrafts, on: job.access) }

    var body: some View {
        if permissions.canView(.stationDocsDrafts, on: job.access) {
            content
        } else {
            TCEmptyState("เอกสารสำหรับทีมภายใน", systemImage: "lock.doc",
                         description: Text("เอกสารสถานี กปภ. ร่างและยื่นโดยทีมภายใน"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.pageGradient.ignoresSafeArea())
        }
    }

    private var content: some View {
        PadForm {
            PadSection { stationSummary }
            PadSection { tabPicker }
            switch tab {
            case .package(let p): packageRows(p)
            case .checklist: checklistRows
            case .erc: ERCFlowRows(job: job, library: library) { tab = .package($0) }.disabled(readOnly)
            }
        }
        .navigationTitle("เอกสารสถานี กปภ.")
        .navigationBarTitleDisplayMode(.inline)
        .tcPadNavBar("เอกสารสถานี กปภ.", trail: ["หน้าหลัก", job.code]) {
            if !readOnly {
                TCButton("แก้ข้อมูลสถานี", systemImage: "slider.horizontal.3", kind: .secondary) { showStation = true }
            }
        }
        .sheet(item: $editing) { kind in
            StationDocSheet(job: job, kind: kind, library: $library)
        }
        .sheet(isPresented: $showStation) { StationFactsSheet(job: job) }
        .onAppear {
            library = StationDocsStore.loadLibrary()
            #if DEBUG
            debugDraft()
            #endif
        }
    }

    #if DEBUG
    /// `-stationDocsDraft outage` opens ร่างหนังสือแจ้งดับไฟ; `pdf` writes the letter with example answers to
    /// `Documents/outage.pdf` without keeping them.
    private func debugDraft() {
        switch UserDefaults.standard.string(forKey: "stationDocsDraft") {
        case "outage": editing = StationDocs.kind("outage_letter")
        case "pdf":
            let letter = job.stationDocs.outageLetter ?? StationDocs.OutageLetter(
                number: "TC-PML-001/2569", to: "ผู้จัดการการไฟฟ้าส่วนภูมิภาค", outageDay: .now, signer: "ชื่อ นามสกุล", position: "วิศวกรโครงการ")
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("outage.pdf")
            try? StationPaperRenderer.pdf(letter.letter(job.stationFacts), company: job.stationLetterhead).write(to: url)
        default: break
        }
        debugERC()
    }

    /// `-stationDocsERC wait|failed|ready|parallel|done` sets the station to 200 kVA and over, writes that state of the
    /// ERC flow dated back from today, and opens ลำดับ กกพ. It changes the job for good. `-stationDocsERCSize <kVA>`
    /// sets the station's size instead (`150`: under 200 kVA, the `utility_lt200` flow, where `parallel` is the
    /// inspection waiting and `done` leaves out the พค.2 steps); `-stationDocsERC small` is `wait` at 150 kVA.
    private func debugERC() {
        guard var name = UserDefaults.standard.string(forKey: "stationDocsERC") else { return }
        var kVA = UserDefaults.standard.object(forKey: "stationDocsERCSize") != nil
            ? UserDefaults.standard.double(forKey: "stationDocsERCSize") : ERCFlow.pk2ThresholdKVA
        if name == "small" { name = "wait"; kVA = 150 }
        let variant = ERCFlow.Variant(kVA: kVA), big = variant == .from200
        func ago(_ days: Int) -> String { ERCFlow.day(Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now) }
        var r = ERCFlow.Record(variant: variant)
        switch name {
        case "wait":
            r.add(.designRequest, day: ago(30))
        case "failed":
            r.add(.designRequest, day: ago(40)); r.add(.designResult, day: ago(28), result: .failed, note: "ให้แก้ขนาดสายประธาน")
        case "ready":
            r.add(.designRequest, day: ago(60)); r.add(.designResult, day: ago(48)); r.add(.install, day: ago(2))
        case "parallel":
            r.add(.designRequest, day: ago(90)); r.add(.designResult, day: ago(78)); r.add(.install, day: ago(20))
            if big { r.add(.pk2Request, day: ago(15)); r.add(.ercToDede, day: ago(10)); r.utilityWantsPK2 = true }
            r.add(.inspectionRequest, day: ago(12))
        case "done":
            r.add(.designRequest, day: ago(120)); r.add(.designResult, day: ago(108)); r.add(.install, day: ago(60))
            if big { r.add(.pk2Request, day: ago(55)); r.add(.pk2Signed, day: ago(25)); r.utilityWantsPK2 = false }
            r.add(.inspectionRequest, day: ago(50)); r.add(.inspectionResult, day: ago(30))
            if !big { r.add(.utilityToERC, day: ago(20)) }
            r.add(.cod, day: ago(15)); r.add(.exemptionResult, day: ago(5))
        default: return
        }
        var station = job.stationDocs
        station.over200kVA = big
        station.erc = r
        job.stationDocs = station
        tab = .erc
    }
    #endif

    // MARK: Header

    private var stationSummary: some View {
        let s = job.stationDocs
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ctx.over200kVA ? "อินเวอร์เตอร์ 200 kVA ขึ้นไป · ต้องยื่น พค.2" : "อินเวอร์เตอร์ต่ำกว่า 200 kVA · ไม่ต้องยื่น พค.2")
                    .font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                Text("อาคาร: \(s.buildingRoute.title) · คำขอ พค.2: \(s.requestType.title)")
                    .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            // iPad: in the nav bar
            if sizeClass == .compact, !readOnly { Button("แก้ข้อมูลสถานี") { showStation = true }.frame(minHeight: touchMin) }
        }
    }

    /// The packages with their ready counts, the พค.2 check list of a station of 200 kVA and over, and the ERC flow of
    /// every station (its size picks the flow: `Job.ercContext`).
    private var tabs: [(tab: Pane, title: String, count: String?)] {
        var out: [(Pane, String, String?)] = StationDocs.packages(ctx).map { p in
            let pr = StationDocs.progress(p, station: job.stationDocs, library: library, ctx)
            return (.package(p), p.title, "\(pr.ready)/\(pr.total)")
        }
        if ctx.over200kVA { out.append((.checklist, "Check list พค.2", nil)) }
        out.append((.erc, "ลำดับ กกพ.", nil))
        return out
    }

    private var tabPicker: some View {
        let tabs = self.tabs
        return ScrollView(.horizontal, showsIndicators: false) {
            if sizeClass == .compact {
                // the PWA module's view switch on iPhone (docs/ui/pwa-plan-iphone §2)
                TCCountSegments(tabs.map { .init($0.title, count: $0.count) },
                                selection: Binding(get: { tabs.firstIndex { $0.tab == tab } ?? 0 }, set: { tab = tabs[$0].tab }),
                                equalWidths: false)
            } else {
                HStack(spacing: 8) {
                    ForEach(tabs, id: \.title) { t in
                        chip([t.title, t.count].compactMap { $0 }.joined(separator: " "), selected: tab == t.tab) { tab = t.tab }
                    }
                }
            }
        }
        .onChange(of: ctx.over200kVA) { _, over in
            if !over, tab == .checklist || tab == .package(.pk2) { tab = .package(.gridConnection) }
        }
    }

    private func chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabun(15, relativeTo: .subheadline).weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14).frame(minHeight: touchMin)
                .background(selected ? Theme.primary : Theme.segmentTrack, in: Capsule())
                .foregroundStyle(selected ? Theme.onPrimary : Theme.navy)
        }
        .buttonStyle(.plain)
    }

    // MARK: Papers

    /// The day a package's papers are due, for `กำหนดส่ง` of the PWA plan page: the MP plan's day, or one set here.
    @ViewBuilder private func dueSection(_ p: StationDocs.Package) -> some View {
        if let task = PWAPlan.submissionTask(p) {
            let planned = job.scheduleInput.flatMap { input in MasterSchedule.plan(input).first { $0.task == task }?.start }
            PadSection("กำหนดยื่น") {
                if let due = job.stationDocs.due(p) {
                    DatePicker("วันครบกำหนด", selection: Binding(get: { due }, set: { setDue($0, p) }), displayedComponents: .date)
                    Button("ใช้วันตามแผน MP") { setDue(nil, p) }
                } else {
                    LabeledContent("วันครบกำหนด", value: planned.map { "ตามแผน MP · " + RoutineReport.thaiDate($0) } ?? "ยังไม่มีแผน MP")
                    Button("กำหนดวันเอง") { setDue(planned ?? .now, p) }
                }
            } footer: {
                Text("แสดงในกำหนดส่งของหน้าแผนงาน PWA")
            }
            .disabled(readOnly)
        }
    }

    private func setDue(_ date: Date?, _ p: StationDocs.Package) {
        guard !readOnly else { return }
        var s = job.stationDocs
        s.setDue(date, for: p)
        job.stationDocs = s
    }

    @ViewBuilder private func packageRows(_ p: StationDocs.Package) -> some View {
        dueSection(p)
        ForEach(StationDocs.Origin.allCases, id: \.self) { origin in
            let kinds = StationDocs.papers(in: p, ctx).filter { $0.origin == origin }
            if !kinds.isEmpty {
                PadSection(origin.title) {
                    ForEach(kinds) { k in
                        Button { editing = k } label: { StationDocRow(kind: k, state: StationDocs.state(k, station: job.stationDocs, library: library)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Check list

    private var checklistRows: some View {
        PadSection("Check list เอกสารประกอบคำขอ พค.2 (แบบ กกพ.)") {
            ForEach(StationDocs.pk2Checklist) { item in
                checkRow(item, StationDocs.check(item, station: job.stationDocs, library: library, ctx))
            }
        } footer: {
            Text("ติ๊กให้เมื่อเอกสารทุกฉบับของข้อนั้นลงนาม ยื่น หรืออนุมัติแล้ว · ข้อที่ไม่มีเอกสารในแอป ให้ทีมติ๊กบนแบบฟอร์มเอง")
        }
    }

    private func checkRow(_ item: StationDocs.CheckItem, _ state: StationDocs.CheckState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(item.number)").font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.inkMuted)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(state == .notApplicable ? Theme.inkMuted : Theme.navy)
                if case .missing(let names) = state {
                    Text("ยังขาด: " + names.joined(separator: " · ")).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
                }
            }
            Spacer()
            switch state {
            case .done: TCStatusChip("ครบ", fill: Theme.okSoft, text: Theme.okText)
            case .missing: TCStatusChip("ยังไม่ครบ", fill: Theme.dangerSoft, text: Theme.dangerText)
            case .manual: TCStatusChip("ทีมติ๊กเอง", fill: Theme.segmentTrack, text: Theme.navy)
            case .notApplicable: TCStatusChip("ไม่ใช้", fill: Theme.segmentTrack, text: Theme.inkMuted)
            }
        }
        .frame(minHeight: touchMin)
    }
}

/// One paper in the list: name, who makes / signs it, scope, state and whether a file is kept.
struct StationDocRow: View {
    let kind: StationDocs.Kind
    let state: StationDocs.DocState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.name).font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                    .multilineTextAlignment(.leading)
                if !detail.isEmpty { Text(detail).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted) }
                if let e = StationDocs.expiry(kind, state) {
                    Text(e == .expired ? "หมดอายุแล้ว" : "ใกล้หมดอายุ")
                        .font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                statusChip
                if state.fileName != nil {
                    Label("มีไฟล์", systemImage: "doc.fill").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.primary)
                }
            }
        }
        .frame(minHeight: touchMin)
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts: [String] = []
        if kind.scope.isShared { parts.append(kind.scope.title + " (คลังกลาง)") }
        if let s = kind.signBy { parts.append("ลงนาม: " + s) }
        if let o = kind.obtainFrom { parts.append("ขอจาก: " + o) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var statusChip: some View {
        switch state.status {
        case .approved, .submitted, .signed: TCStatusChip(state.status.title, fill: Theme.okSoft, text: Theme.okText)
        case .draft, .requested: TCStatusChip(state.status.title, fill: Theme.warningSoft, text: Theme.pending)
        case .notNeeded: TCStatusChip(state.status.title, fill: Theme.segmentTrack, text: Theme.inkMuted)
        case .missing: TCStatusChip(state.status.title, fill: Theme.dangerSoft, text: Theme.dangerText)
        }
    }
}

/// Edits one paper: state, expiry, note and its file. Site papers keep the file in the job's documents (so it goes
/// to Drive with the job); shared papers keep it in the device library.
struct StationDocSheet: View {
    @Bindable var job: Job
    let kind: StationDocs.Kind
    @Binding var library: StationDocs.Library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.permissions) private var permissions

    /// A contractor sees the paper and opens its file; nothing is kept (firestore.rules refuse their job edits).
    private var readOnly: Bool { !permissions.can(.stationDocsDrafts, on: job.access) }

    @State private var state = StationDocs.DocState()
    @State private var importing = false
    @State private var preview: URL?
    @State private var drafting = false
    @State private var askRedraft = false

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection {
                    Text(kind.name).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    if let n = kind.note { Text(n).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted) }
                    LabeledContent("ต้นทาง", value: kind.origin.title)
                    LabeledContent("ใช้ซ้ำ", value: kind.scope.title)
                    if let s = kind.signBy { LabeledContent("ผู้ลงนาม", value: s) }
                    if let o = kind.obtainFrom { LabeledContent("ขอจาก", value: o) }
                    LabeledContent("ใช้ในชุด", value: kind.packages.map(\.title).joined(separator: " · "))
                }
                statusSection
                filesSection
            }
            .navigationTitle("เอกสาร")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if readOnly {
                    ToolbarItem(placement: .confirmationAction) { Button("ปิด") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("บันทึก") { save(); dismiss() } }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .spreadsheet, .data],
                          onCompletion: attach)
            .quickLookPreview($preview)
            .sheet(isPresented: $drafting) { OutageLetterSheet(job: job, keep: keepDraft) }
            .confirmationDialog("เอกสารนี้\(state.status.title) ร่างใหม่จะแทนไฟล์เดิม และสถานะกลับเป็น “ร่างแล้ว”",
                                isPresented: $askRedraft, titleVisibility: .visible) {
                Button("ร่างใหม่", role: .destructive) { drafting = true }
                Button("ยกเลิก", role: .cancel) {}
            }
            .onAppear {
                state = StationDocs.state(kind, station: job.stationDocs, library: library)
                #if DEBUG
                if UserDefaults.standard.string(forKey: "stationDocsDraft") == "outage", !readOnly { drafting = true }
                #endif
            }
        }
    }

    private var statusSection: some View {
        PadSection("สถานะ") {
            PadPicker("สถานะ", selection: $state.status) {
                ForEach(StationDocs.Status.choices(for: kind.origin), id: \.self) { Text($0.title).tag($0) }
            }
            if kind.expires {
                Toggle("มีวันหมดอายุ", isOn: Binding(get: { state.expiresAt != nil },
                                                     set: { state.expiresAt = $0 ? (state.expiresAt ?? .now) : nil }))
                if let d = state.expiresAt {
                    DatePicker("หมดอายุ", selection: Binding(get: { d }, set: { state.expiresAt = $0 }), displayedComponents: .date)
                }
            }
            TextField("หมายเหตุ เช่น ส่งให้ ผจก.สาขาแล้ว รอลงนาม", text: $state.note, axis: .vertical)
        }
        .disabled(readOnly)
    }

    private var filesSection: some View {
        PadSection("ไฟล์") {
            if StationDocs.draft(for: kind) != nil, !readOnly {
                Button { if state.status.isReady, state.fileName != nil { askRedraft = true } else { drafting = true } } label: {
                    Label("ร่างในแอป", systemImage: "square.and.pencil")
                }
                .frame(minHeight: touchMin)
            }
            if let name = state.fileName {
                Button { open(name) } label: { Label(name, systemImage: "doc.text.magnifyingglass") }
                    .frame(minHeight: touchMin)
                if !readOnly {
                    Button("เปลี่ยนไฟล์") { importing = true }.frame(minHeight: touchMin)
                    Button("เอาไฟล์ออก", role: .destructive) { removeFile() }.foregroundStyle(Theme.danger).frame(minHeight: touchMin)
                }
            } else if readOnly {
                Text("ยังไม่มีไฟล์").foregroundStyle(Theme.inkMuted).frame(minHeight: touchMin)
            } else {
                Button { importing = true } label: { Label("แนบไฟล์", systemImage: "paperclip") }
                    .frame(minHeight: touchMin)
            }
        } footer: {
            Text(readOnly ? "ดูอย่างเดียว · ทีมภายในเป็นผู้แก้และอัปโหลดเอกสาร"
                 : kind.scope.isShared
                 ? "เก็บไว้ในเครื่องครั้งเดียว ใช้กับทุกสถานี ไม่อัปโหลดขึ้น Drive"
                 : "เก็บในแฟ้มเอกสารของงาน และอัปโหลดขึ้น Drive พร้อมเอกสารอื่น")
        }
    }

    /// The drafted paper becomes the paper's file, in place of the one before it.
    private func keepDraft(_ data: Data) {
        let name = HomeArchive.name("\(job.code) \(kind.name)", ext: "pdf")
        guard let kept = HomeArchive.keep(data, name: name, job: job)?.name else { return }
        if let old = state.fileName, old != kept, let doc = job.documents.first(where: { $0.name == old }) {
            job.modelContext?.delete(doc)
        }
        state.fileName = kept
        state.status = .draft
    }

    private func attach(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        if kind.scope.isShared {
            state.fileName = StationDocsStore.keepFile(data, kindID: kind.id, ext: ext)
        } else {
            if let old = state.fileName, let doc = job.documents.first(where: { $0.name == old }) {
                job.modelContext?.delete(doc)
            }
            let name = HomeArchive.name("\(job.code) \(kind.name)", ext: ext.lowercased())
            state.fileName = HomeArchive.keep(data, name: name, job: job)?.name
        }
        if state.fileName != nil, state.status == .missing { state.status = kind.origin == .external ? .signed : .draft }
    }

    private func removeFile() {
        guard let name = state.fileName else { return }
        if kind.scope.isShared {
            StationDocsStore.removeFiles(kindID: kind.id)
        } else if let doc = job.documents.first(where: { $0.name == name }) {
            job.modelContext?.delete(doc)
        }
        state.fileName = nil
    }

    private func open(_ name: String) {
        if kind.scope.isShared {
            preview = StationDocsStore.fileURL(name)
        } else if let doc = job.documents.first(where: { $0.name == name }) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.name)
            try? doc.data.write(to: url)
            preview = url
        }
    }

    private func save() {
        guard !readOnly else { return }
        var s = state
        s.updatedAt = .now
        if kind.scope.isShared {
            library.docs[kind.id] = s
            StationDocsStore.save(library)
        } else {
            var station = job.stationDocs
            station.docs[kind.id] = s
            job.stationDocs = station
        }
    }
}

/// The facts that decide which papers the station needs.
struct StationFactsSheet: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss
    @State private var s = StationDocs.Station()

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection("สังกัด กปภ.") {
                    LabeledContent("สาขา") { TextField("เช่น สาขาปากช่อง", text: $s.branch).multilineTextAlignment(.trailing) }
                    LabeledContent("เขต / พื้นที่") { TextField("เช่น เขต 2", text: $s.region).multilineTextAlignment(.trailing) }
                } footer: {
                    Text("ใช้ตั้งชื่อไฟล์ส่งมอบใน Drive กลาง เช่น AS-Built <สถานี> <สาขา>")
                }
                PadSection("ใบอนุญาต พค.2") {
                    PadPicker("พค.2", selection: Binding(get: { s.over200kVA.map { $0 ? 1 : 0 } ?? -1 },
                                                     set: { s.over200kVA = $0 < 0 ? nil : $0 == 1 })) {
                        Text(autoTitle).tag(-1)
                        Text("ต้องยื่น (200 kVA ขึ้นไป)").tag(1)
                        Text("ไม่ต้องยื่น").tag(0)
                    }
                    PadPicker("คำขอ พค.2", selection: $s.requestType) {
                        ForEach(StationDocs.RequestType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("โครงการ SRT (แนบสัญญา / ใบสั่งจ้าง)", isOn: $s.srtProject)
                    Toggle("จำหน่ายไฟฟ้า (แนบสัญญาซื้อขายไฟ)", isOn: $s.sellsPower)
                }
                PadSection("อาคาร") {
                    PadPicker("เทศบาลให้", selection: $s.buildingRoute) {
                        ForEach(StationDocs.BuildingRoute.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("ยังไม่รู้ = แสดงทั้งคำขออนุญาตและหนังสือแจ้งยกเว้นไว้ก่อน")
                }
            }
            .navigationTitle("ข้อมูลสถานี")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        var station = job.stationDocs
                        station.over200kVA = s.over200kVA; station.buildingRoute = s.buildingRoute
                        station.requestType = s.requestType; station.srtProject = s.srtProject; station.sellsPower = s.sellsPower
                        station.branch = s.branch.trimmingCharacters(in: .whitespaces)
                        station.region = s.region.trimmingCharacters(in: .whitespaces)
                        job.stationDocs = station
                        dismiss()
                    }
                }
            }
            .onAppear { s = job.stationDocs }
        }
    }

    private var autoTitle: String {
        guard let kw = job.inverterKW else { return "ตามแผนงาน MP" }
        return "ตามขนาดอินเวอร์เตอร์ (\(Int(kw)) kW)"
    }
}

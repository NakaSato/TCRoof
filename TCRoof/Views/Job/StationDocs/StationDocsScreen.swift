import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

/// เอกสารสถานี กปภ.: every paper the station needs, by submission (ขนานไฟ, พค.2, อาคาร, ทดสอบ, ส่งมอบ), with who makes
/// or signs it, where it stands and its file; plus the ERC พค.2 check list ticked from those states.
struct StationDocsScreen: View {
    @Bindable var job: Job

    enum Pane: Hashable { case package(StationDocs.Package), checklist }

    @State private var tab: Pane = .package(.gridConnection)
    @State private var library = StationDocsStore.loadLibrary()
    @State private var editing: StationDocs.Kind?
    @State private var showStation = false

    private var ctx: StationDocs.Context { job.stationContext }

    var body: some View {
        List {
            Section { stationSummary }
            Section { tabPicker }
            switch tab {
            case .package(let p): packageRows(p)
            case .checklist: checklistRows
            }
        }
        .navigationTitle("เอกสารสถานี กปภ.")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { kind in
            StationDocSheet(job: job, kind: kind, library: $library)
        }
        .sheet(isPresented: $showStation) { StationFactsSheet(job: job) }
        .onAppear { library = StationDocsStore.loadLibrary() }
    }

    // MARK: Header

    private var stationSummary: some View {
        let s = job.stationDocs
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ctx.over200kVA ? "อินเวอร์เตอร์ 200 kVA ขึ้นไป · ต้องยื่น พค.2" : "อินเวอร์เตอร์ต่ำกว่า 200 kVA · ไม่ต้องยื่น พค.2")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.navy)
                Text("อาคาร: \(s.buildingRoute.title) · คำขอ พค.2: \(s.requestType.title)")
                    .font(.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button("แก้ข้อมูลสถานี") { showStation = true }.frame(minHeight: touchMin)
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StationDocs.packages(ctx)) { p in
                    let pr = StationDocs.progress(p, station: job.stationDocs, library: library, ctx)
                    chip("\(p.title) \(pr.ready)/\(pr.total)", selected: tab == .package(p)) { tab = .package(p) }
                }
                if ctx.over200kVA { chip("Check list พค.2", selected: tab == .checklist) { tab = .checklist } }
            }
        }
        .onChange(of: ctx.over200kVA) { _, over in if !over, tab == .checklist || tab == .package(.pk2) { tab = .package(.gridConnection) } }
    }

    private func chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14).frame(minHeight: touchMin)
                .background(selected ? Theme.primary : Theme.segmentTrack, in: Capsule())
                .foregroundStyle(selected ? Color.white : Theme.navy)
        }
        .buttonStyle(.plain)
    }

    // MARK: Papers

    @ViewBuilder private func packageRows(_ p: StationDocs.Package) -> some View {
        ForEach(StationDocs.Origin.allCases, id: \.self) { origin in
            let kinds = StationDocs.papers(in: p, ctx).filter { $0.origin == origin }
            if !kinds.isEmpty {
                Section(origin.title) {
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
        Section {
            ForEach(StationDocs.pk2Checklist) { item in
                checkRow(item, StationDocs.check(item, station: job.stationDocs, library: library, ctx))
            }
        } header: {
            Text("Check list เอกสารประกอบคำขอ พค.2 (แบบ กกพ.)")
        } footer: {
            Text("ติ๊กให้เมื่อเอกสารทุกฉบับของข้อนั้นลงนาม ยื่น หรืออนุมัติแล้ว · ข้อที่ไม่มีเอกสารในแอป ให้ทีมติ๊กบนแบบฟอร์มเอง")
        }
    }

    private func checkRow(_ item: StationDocs.CheckItem, _ state: StationDocs.CheckState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(item.number)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.inkMuted)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text).font(.subheadline).foregroundStyle(state == .notApplicable ? Theme.inkMuted : Theme.navy)
                if case .missing(let names) = state {
                    Text("ยังขาด: " + names.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dangerText)
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
                Text(kind.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.navy)
                    .multilineTextAlignment(.leading)
                Text(detail).font(.caption).foregroundStyle(Theme.inkMuted)
                if let e = StationDocs.expiry(kind, state) {
                    Text(e == .expired ? "หมดอายุแล้ว" : "ใกล้หมดอายุ")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.dangerText)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                statusChip
                if state.fileName != nil {
                    Label("มีไฟล์", systemImage: "doc.fill").font(.caption).foregroundStyle(Theme.primary)
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

    @State private var state = StationDocs.DocState()
    @State private var importing = false
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(kind.name).font(.headline).foregroundStyle(Theme.navy)
                    if let n = kind.note { Text(n).font(.subheadline).foregroundStyle(Theme.inkMuted) }
                    LabeledContent("ต้นทาง", value: kind.origin.title)
                    LabeledContent("ใช้ซ้ำ", value: kind.scope.title)
                    if let s = kind.signBy { LabeledContent("ผู้ลงนาม", value: s) }
                    if let o = kind.obtainFrom { LabeledContent("ขอจาก", value: o) }
                    LabeledContent("ใช้ในชุด", value: kind.packages.map(\.title).joined(separator: " · "))
                }
                Section("สถานะ") {
                    Picker("สถานะ", selection: $state.status) {
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
                Section {
                    if let name = state.fileName {
                        Button { open(name) } label: { Label(name, systemImage: "doc.text.magnifyingglass") }
                            .frame(minHeight: touchMin)
                        Button("เปลี่ยนไฟล์") { importing = true }.frame(minHeight: touchMin)
                        Button("เอาไฟล์ออก", role: .destructive) { removeFile() }.frame(minHeight: touchMin)
                    } else {
                        Button { importing = true } label: { Label("แนบไฟล์", systemImage: "paperclip") }
                            .frame(minHeight: touchMin)
                    }
                } header: {
                    Text("ไฟล์")
                } footer: {
                    Text(kind.scope.isShared
                         ? "เก็บไว้ในเครื่องครั้งเดียว ใช้กับทุกสถานี ไม่อัปโหลดขึ้น Drive"
                         : "เก็บในแฟ้มเอกสารของงาน และอัปโหลดขึ้น Drive พร้อมเอกสารอื่น")
                }
            }
            .navigationTitle("เอกสาร")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("บันทึก") { save(); dismiss() } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .spreadsheet, .data],
                          onCompletion: attach)
            .quickLookPreview($preview)
            .onAppear { state = StationDocs.state(kind, station: job.stationDocs, library: library) }
        }
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
            Form {
                Section {
                    Picker("พค.2", selection: Binding(get: { s.over200kVA.map { $0 ? 1 : 0 } ?? -1 },
                                                     set: { s.over200kVA = $0 < 0 ? nil : $0 == 1 })) {
                        Text(autoTitle).tag(-1)
                        Text("ต้องยื่น (200 kVA ขึ้นไป)").tag(1)
                        Text("ไม่ต้องยื่น").tag(0)
                    }
                    Picker("คำขอ พค.2", selection: $s.requestType) {
                        ForEach(StationDocs.RequestType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("โครงการ SRT (แนบสัญญา / ใบสั่งจ้าง)", isOn: $s.srtProject)
                    Toggle("จำหน่ายไฟฟ้า (แนบสัญญาซื้อขายไฟ)", isOn: $s.sellsPower)
                } header: {
                    Text("ใบอนุญาต พค.2")
                }
                Section {
                    Picker("เทศบาลให้", selection: $s.buildingRoute) {
                        ForEach(StationDocs.BuildingRoute.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("อาคาร")
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

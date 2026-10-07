import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

/// งานบ้าน: one residential Solar Rooftop job from survey to handover — the stages, every document PEA asks for
/// (by route: selling the surplus or self-use), the forms that make them, and the PPIM upload pack.
/// Homes only (ผู้ใช้ไฟประเภท 1, PEA area).
struct HomeWorkView: View {
    let job: Job

    @State private var home = HomeJob()
    @State private var loaded = false
    @State private var openStage: HomeStage?
    @State private var showWeight = false
    @State private var showPack = false
    @State private var showEntry = false
    @State private var library = HomeLibrary()
    /// nil = open while the sizes or the phase are missing.
    @State private var setupOpen: Bool?
    /// Finished stages the team opened again.
    @State private var openStages: Set<HomeStage> = []
    @State private var scrollTarget: String?
    static let file = "home"

    private var store: PermitStore { PermitStore(job: job) }

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "งานบ้าน", trail: ["หน้าหลัก", job.code], current: "งานบ้าน ครบวงจร") {
                if home.residentialConfirmed {
                    NavigationLink { HomeLibraryView() } label: {
                        Label("คลังเอกสาร", systemImage: "books.vertical").font(.sarabun(14, .semibold, relativeTo: .body))
                            .padding(.horizontal, Space.m).frame(minHeight: touchMin)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    TCButton("ชุดไฟล์ PPIM", systemImage: "tray.and.arrow.up", kind: .secondary, size: .card) { showPack = true }
                }
            }
            ScrollViewReader { proxy in
                ScrollView { content }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { load() }
        .onAppear {
            library = PermitStore.library.load(HomeLibrary.self, PermitStore.libraryFile) ?? HomeLibrary()
            refreshAuto()
        }
        .onChange(of: home) { _, new in
            guard loaded else { return }
            store.save(new, Self.file)
            markDone(homeDone)
            home.applyLibrary(library)
        }
        .sheet(isPresented: $showWeight) { RoofWeightSheet(result: $home.roofKgPerM2) }
        .sheet(isPresented: $showPack) { PPIMPackView(job: job, home: home, library: library) }
        .sheet(isPresented: $showEntry) { PPIMEntryView(home: $home) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if home.residentialConfirmed {
                nextCard
                setupSection.id("setup")
                if home.mode == .sell { HomeSellCard(home: $home).id("sell") }
                stageStrip
                ForEach(HomeStage.allCases, id: \.self) { stageCard($0) }
            } else {
                residentialGate
            }
        }
        .padding(isPhone ? Space.l : Space.xl)
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
    }

    private func load() {
        guard !loaded else { return }
        if let saved = store.load(HomeJob.self, Self.file) {
            home = saved
        } else if job.capacityKW > 0 {
            home.pvKWp = String(format: "%.2f", job.capacityKW)
        }
        loaded = true
        refreshAuto()
    }

    /// Documents made by other screens count as received once those screens are done.
    private func refreshAuto() {
        guard loaded else { return }
        let poa = store.load(PowerOfAttorney.self, PowerOfAttorneyView.file)
        let cert = store.load(SelfCertification.self, SelfCertificationView.file)
        let boq = store.load(HomeBOQ.self, BOQView.file)
        markDone([
            "survey": !job.savedSurveys.isEmpty,
            "installLog": !job.logs.isEmpty,
            "icl": job.inspection?.submittedAt != nil,
            "poa": poa.map { $0.issues.isEmpty } ?? false,
            "selfCert": cert.map { $0.issues.isEmpty } ?? false,
            "installCert": cert.map { $0.issues.isEmpty } ?? false,
            "boq": boq.map { $0.issues(for: home).isEmpty } ?? false,
        ])
        markDone(homeDone)
        home.applyLibrary(library)
    }

    /// Documents this screen's own answers complete.
    private var homeDone: [String: Bool] {
        let filed = !home.ppimRequestNo.trimmingCharacters(in: .whitespaces).isEmpty
        return [
            "roofWeight": home.roofKgPerM2 != nil,
            "ppimRequest": filed,
            "sellRequest": filed && home.offer != nil,
            "peaApproval": home.mode == .sell && home.announcedOn != nil,
            "connectRequest": !home.connectRequestNo.trimmingCharacters(in: .whitespaces).isEmpty,
            "connectionDate": home.cod != nil,
            "sitePhotos": !home.photoReport.pages.isEmpty,
        ]
    }

    /// Marks received; never lowers a status the team set.
    private func markDone(_ done: [String: Bool]) {
        for (id, isDone) in done where isDone && !home.document(id).status.isDone {
            var d = home.document(id)
            d.status = .received
            d.updatedAt = .now
            home.documents[id] = d
        }
    }

    // MARK: Homes only

    private var residentialGate: some View {
        PermitSection(title: "งานบ้านอยู่อาศัยเท่านั้น",
                      subtitle: "โมดูลนี้ใช้กับผู้ใช้ไฟประเภท 1 (บ้านอยู่อาศัย) ในพื้นที่ PEA · โรงงาน อาคารพาณิชย์ และงาน กปภ. ใช้โมดูลอื่น") {
            PermitField("Rate code บนบิลค่าไฟ (เลข 4 หลัก)", text: $home.caRateCode, required: true, keyboard: .numberPad,
                        error: home.rateCodeIsResidential == false ? "ขึ้นต้นด้วย \(home.caRateCode.prefix(1)) — ไม่ใช่บ้านอยู่อาศัย ใช้โมดูลนี้ไม่ได้" : nil)
            Text("หลักแรก 1 = บ้านอยู่อาศัย · หลักที่ 4 = 5 คือแรงดันต่ำกว่า 400 V · กรุงเทพฯ นนทบุรี สมุทรปราการ เป็นพื้นที่ MEA ใช้ขั้นตอนอื่น")
                .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            TCButton("ยืนยันเป็นงานบ้าน", systemImage: "house", kind: .primary,
                     disabledReason: home.rateCodeIsResidential == true ? nil : "กรอก rate code ที่ขึ้นต้นด้วย 1") {
                home.residentialConfirmed = true
            }
        }
    }

    // MARK: Next

    /// The few things to do now; tapping one goes to its row or card.
    private var nextCard: some View {
        let actions = home.nextActions()
        return PermitSection(title: "ต้องทำต่อ",
                             subtitle: home.currentStage.map { "ตอนนี้อยู่ขั้น\($0.title)" } ?? "ครบทุกขั้นแล้ว ปิดงานได้") {
            if actions.isEmpty {
                Text("ไม่มีงานค้าง").font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.okText)
            }
            ForEach(actions) { actionRow($0) }
        }
    }

    private func actionRow(_ a: HomeAction) -> some View {
        Button { go(a) } label: {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: icon(a.kind)).font(.system(size: 18)).foregroundStyle(tint(a.kind)).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.title).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let d = a.detail {
                        Text(d).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(a.kind == .document ? Theme.inkMuted : tint(a.kind))
                    }
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkMuted)
            }
            .padding(Space.m)
            .frame(minHeight: touchMin)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func icon(_ k: HomeAction.Kind) -> String {
        switch k {
        case .overdue: "exclamationmark.triangle.fill"
        case .issue: "exclamationmark.circle"
        case .deadline: "clock"
        case .document: "doc.badge.plus"
        }
    }

    private func tint(_ k: HomeAction.Kind) -> Color {
        switch k {
        case .overdue, .issue: Theme.dangerText
        case .deadline: Theme.pending
        case .document: Theme.primary
        }
    }

    private func go(_ a: HomeAction) {
        if let doc = a.docID {
            if let stage = HomeCatalog.spec(doc)?.stage { openStages.insert(stage) }
            scrollTarget = doc
        } else if a.kind == .issue {
            setupOpen = true
            scrollTarget = "setup"
        } else {
            scrollTarget = home.mode == .sell ? "sell" : "setup"
        }
    }

    // MARK: Setup

    private var setupIsOpen: Bool {
        setupOpen ?? (HomeJob.number(home.pvKWp) == nil || HomeJob.number(home.inverterKW) == nil || home.phase == nil)
    }

    @ViewBuilder private var setupSection: some View {
        if setupIsOpen {
            VStack(alignment: .leading, spacing: Space.s) {
                setupCard
                TCButton("ย่อข้อมูลงาน", systemImage: "chevron.up", kind: .secondary, size: .card) { setupOpen = false }
            }
        } else {
            setupSummary
        }
    }

    private var setupSummary: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ข้อมูลงาน").font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text(summaryText).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            TCButton("แก้", systemImage: "pencil", kind: .secondary, size: .card) { setupOpen = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Space.l)
    }

    private var summaryText: String {
        var parts = [home.mode == .sell ? "ขายไฟส่วนเกิน" : "ผลิตใช้เอง"]
        parts.append("แผง \(home.pvKWp) kWp · อินเวอร์เตอร์ \(home.inverterKW) kW")
        if home.mode == .sell, !home.sellKW.isEmpty { parts.append("ขาย \(home.sellKW) kW") }
        if let p = home.phase { parts.append(p.title) }
        if let w = home.roofKgPerM2 { parts.append(String(format: "%.1f กก./ตร.ม.", w)) }
        if home.teamFiles { parts.append("ทีมยื่นแทน") }
        return parts.joined(separator: " · ")
    }

    private var setupCard: some View {
        PermitSection(title: "ข้อมูลงาน", subtitle: "เลือกเส้นทางแล้วรายการเอกสารจะปรับให้เอง") {
            VStack(alignment: .leading, spacing: 6) {
                TCFieldLabel("เส้นทาง")
                TCSegmented(HomeJob.Mode.allCases.map(\.title),
                            selection: Binding(get: { home.mode.title },
                                               set: { t in home.mode = HomeJob.Mode.allCases.first { $0.title == t } ?? .selfUse }),
                            fontSize: 13.5)
            }
            PermitRow {
                PermitField("แผง PV", text: $home.pvKWp, required: true, keyboard: .decimalPad, unit: "kWp")
                PermitField("Inverter", text: $home.inverterKW, required: true, keyboard: .decimalPad, unit: "kW")
                if home.mode == .sell {
                    PermitField("เสนอขาย", text: $home.sellKW, required: true, keyboard: .decimalPad, unit: "kW",
                                error: (Double(home.sellKW) ?? 0) > 5 ? "ไม่เกิน 5 kW" : nil)
                }
            }
            HStack(spacing: Space.s) {
                ForEach(SelfCertification.Phase.allCases, id: \.self) { p in
                    TCChoiceChip(p.title, selected: home.phase == p) { home.phase = p }
                }
            }
            TCSwitchRow("ทีมยื่นแทนเจ้าของ (ใช้หนังสือมอบอำนาจ)", isOn: $home.teamFiles)
            TCSwitchRow("ลูกค้าใช้สิทธิลดหย่อนภาษี (แผงไม่เกิน 10 kWp)", isOn: $home.wantsTaxDeduction)
            roofRow
            ppimRow
            coeRow
            if home.mode == .selfUse { PermitField("เลขที่คำขอใน PPIM", text: $home.ppimRequestNo) }
            ForEach(home.issues, id: \.self) { issue in
                Text(issue).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
            }
        }
    }

    private var roofRow: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("น้ำหนักบนหลังคา").font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                if let w = home.roofKgPerM2 {
                    Text(String(format: "%.1f กก./ตร.ม. · ", w) + (w > 20 ? "ต้องขออนุญาตดัดแปลงอาคาร (ข.1 → อ.1)" : "ไม่ต้องขออนุญาตเทศบาล"))
                        .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(w > 20 ? Theme.pending : Theme.okText)
                } else {
                    Text("ยังไม่คำนวณ").font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            TCButton("คำนวณ", systemImage: "scalemass", kind: .secondary, size: .card) { showWeight = true }
        }
    }

    private var ppimRow: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ข้อมูลกรอก PPIM ส่วนที่ 3").font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text(ppimSummary)
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            TCButton("กรอก", systemImage: "list.bullet.rectangle", kind: .secondary, size: .card) { showEntry = true }
        }
    }

    private var ppimSummary: String {
        var parts: [String] = []
        if let kw = home.ppim.inverterKW { parts.append("อินเวอร์เตอร์ " + PPIMEntryView.text(kw) + " kW") }
        parts.append(home.ppim.peaMeterNo.isEmpty ? "ยังไม่มีเลขเครื่องวัด" : "PEA No. \(home.ppim.peaMeterNo)")
        if home.ppim.coordinate == nil { parts.append("ยังไม่มีพิกัด") }
        parts += home.ppim.issues
        return parts.joined(separator: " · ")
    }

    /// หนังสือรับรองสภาวิศวกร for slot 6 is valid 120 days.
    private var coeRow: some View {
        HomeDateRow(title: "หนังสือรับรองสภาวิศวกร", date: $home.coeCertIssued, caption: coeText,
                    warning: (home.coeCertDaysLeft() ?? 1) < 0, setLabel: "ใส่วันที่ออก")
    }

    private var coeText: String {
        guard let left = home.coeCertDaysLeft() else { return "ใช้ได้ 120 วันนับจากวันที่ออก" }
        return left < 0 ? "หมดอายุแล้ว \(-left) วัน · ขอฉบับใหม่" : "ใช้ได้อีก \(left) วัน"
    }

    // MARK: Stages

    private var stageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(HomeStage.allCases, id: \.self) { s in
                    let p = home.progress(s)
                    let current = home.currentStage == s
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.sarabun(13.5, .bold, relativeTo: .caption)).foregroundStyle(current ? Theme.primary : Theme.navy)
                        Text(p.done == p.total ? "ครบ" : "\(p.done)/\(p.total)")
                            .font(.sarabun(12, relativeTo: .caption2)).foregroundStyle(p.done == p.total ? Theme.okText : Theme.inkMuted)
                    }
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(current ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(current ? Theme.primary : Theme.borderSubtle))
                }
            }
        }
    }

    @ViewBuilder private func stageCard(_ stage: HomeStage) -> some View {
        let p = home.progress(stage)
        let finished = p.done == p.total && home.currentStage != stage
        if finished && !openStages.contains(stage) {
            stageFolded(stage, count: home.checklist.filter { $0.stage == stage }.count)
        } else {
            PermitSection(title: stage.title, subtitle: p.done == p.total ? "ครบแล้ว" : "เหลือ \(p.total - p.done) รายการ") {
                ForEach(home.checklist.filter { $0.stage == stage }) { spec in documentRow(spec).id(spec.id) }
                if finished {
                    TCButton("พับขั้นนี้", systemImage: "chevron.up", kind: .secondary, size: .card) { openStages.remove(stage) }
                }
            }
        }
    }

    /// A finished stage, one line.
    private func stageFolded(_ stage: HomeStage, count: Int) -> some View {
        Button { openStages.insert(stage) } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.okTick)
                Text(stage.title).font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text("ครบ \(count) รายการ").font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.okText)
                Spacer()
                Image(systemName: "chevron.down").foregroundStyle(Theme.inkMuted)
            }
            .padding(Space.l)
            .frame(minHeight: touchMin)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.title) ครบแล้ว แตะเพื่อดู")
    }

    private func documentRow(_ spec: HomeDocSpec) -> some View {
        let kind = HomeLibrary.Kind(docID: spec.id)
        return HomeDocumentRow(spec: spec, document: binding(spec.id), store: store, optional: spec.isOptional(for: home),
                               libraryItem: library.item(home.libraryPicks[spec.id]),
                               libraryChoices: kind.map { k in library.items(k).filter { !$0.files.isEmpty } } ?? [],
                               onPick: { pick(spec.id, $0) }) { destination(spec) }
    }

    /// Attaches a library item, or detaches it ("" keeps the library from picking again).
    private func pick(_ doc: String, _ itemID: String?) {
        home.libraryPicks[doc] = itemID ?? ""
        var d = home.document(doc)
        if itemID == nil && d.files.isEmpty { d.status = .missing }
        d.updatedAt = .now
        home.documents[doc] = d
    }

    private func binding(_ id: String) -> Binding<HomeDocument> {
        Binding(get: { home.document(id) }, set: { home.documents[id] = $0 })
    }

    @ViewBuilder private func destination(_ spec: HomeDocSpec) -> some View {
        switch spec.form {
        case .powerOfAttorney: PowerOfAttorneyView(job: job)
        case .selfCertification: SelfCertificationView(job: job)
        case .surveyForm: SurveyFormView(job: job)
        case .installLog: JobInstallLogsView(job: job)
        case .inspection: InspectionView(job: job)
        case .photoReport: PhotoReportView(job: job, home: $home)
        case .boq: BOQView(job: job, home: home)
        case .roofWeight, nil: EmptyView()
        }
    }
}

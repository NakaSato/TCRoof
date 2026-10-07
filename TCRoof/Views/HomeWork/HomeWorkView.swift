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
    static let file = "home"

    private var store: PermitStore { PermitStore(job: job) }

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "งานบ้าน", trail: ["หน้าหลัก", job.code], current: "งานบ้าน ครบวงจร") {
                if home.residentialConfirmed {
                    TCButton("ชุดไฟล์ PPIM", systemImage: "tray.and.arrow.up", kind: .secondary, size: .card) { showPack = true }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if home.residentialConfirmed {
                        setupCard
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
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { load() }
        .onAppear { refreshAuto() }
        .onChange(of: home) { _, new in if loaded { store.save(new, Self.file) } }
        .sheet(isPresented: $showWeight) { RoofWeightSheet(result: $home.roofKgPerM2) }
        .sheet(isPresented: $showPack) { PPIMPackView(job: job, home: home) }
        .sheet(isPresented: $showEntry) { PPIMEntryView(home: $home) }
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
        let done: [String: Bool] = [
            "survey": !job.savedSurveys.isEmpty,
            "installLog": !job.logs.isEmpty,
            "icl": job.inspection?.submittedAt != nil,
            "roofWeight": home.roofKgPerM2 != nil,
            "poa": poa.map { $0.issues.isEmpty } ?? false,
            "selfCert": cert.map { $0.issues.isEmpty } ?? false,
            "installCert": cert.map { $0.issues.isEmpty } ?? false,
            "ppimRequest": !home.ppimRequestNo.trimmingCharacters(in: .whitespaces).isEmpty,
            "sitePhotos": !home.photoReport.pages.isEmpty,
        ]
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

    // MARK: Setup

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
            PermitField("เลขที่คำขอใน PPIM", text: $home.ppimRequestNo)
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
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("หนังสือรับรองสภาวิศวกร").font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text(coeText).font(.sarabun(TypeScale.caption, relativeTo: .caption))
                    .foregroundStyle((home.coeCertDaysLeft() ?? 1) < 0 ? Theme.dangerText : Theme.inkMuted)
            }
            Spacer()
            if home.coeCertIssued != nil {
                DatePicker("วันที่ออก", selection: Binding(get: { home.coeCertIssued ?? .now }, set: { home.coeCertIssued = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "th_TH"))
                    .environment(\.calendar, Calendar(identifier: .buddhist))
            } else {
                TCButton("ใส่วันที่ออก", systemImage: "calendar", kind: .secondary, size: .card) { home.coeCertIssued = .now }
            }
        }
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

    private func stageCard(_ stage: HomeStage) -> some View {
        let specs = home.checklist.filter { $0.stage == stage }
        let p = home.progress(stage)
        return PermitSection(title: stage.title, subtitle: p.done == p.total ? "ครบแล้ว" : "เหลือ \(p.total - p.done) รายการ") {
            ForEach(specs) { spec in
                HomeDocumentRow(spec: spec, document: binding(spec.id), store: store, optional: spec.isOptional(for: home)) { destination(spec) }
            }
        }
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
        case .roofWeight, nil: EmptyView()
        }
    }
}

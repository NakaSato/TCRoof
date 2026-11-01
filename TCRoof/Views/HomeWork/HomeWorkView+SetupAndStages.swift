import SwiftUI
import TCRoofUI
import TCRoofCore

extension HomeWorkView {
    // MARK: Setup

    var setupIsOpen: Bool {
        setupOpen ?? (HomeJob.number(home.pvKWp) == nil || HomeJob.number(home.inverterKW) == nil || home.phase == nil)
    }

    @ViewBuilder var setupSection: some View {
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
        parts.append("แผง \(home.pvKWp) kWp | อินเวอร์เตอร์ \(home.inverterKW) kW")
        if home.mode == .sell, !home.sellKW.isEmpty { parts.append("ขาย \(home.sellKW) kW") }
        if let p = home.phase { parts.append(p.title) }
        if let w = home.roofKgPerM2 { parts.append(String(format: "%.1f กก./ตร.ม.", w)) }
        if home.teamFiles { parts.append("ทีมยื่นแทน") }
        return parts.joined(separator: " | ")
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
            TCSwitchRow("ติดตั้งโดยผู้รับเหมา (ใบสั่งงาน รับของ ตรวจรับ)", isOn: $home.usesContractor)
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
                    Text(String(format: "%.1f กก./ตร.ม. | ", w) + (w > 20 ? "ต้องขออนุญาตดัดแปลงอาคาร (ข.1 → อ.1)" : "ไม่ต้องขออนุญาตเทศบาล"))
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
        return parts.joined(separator: " | ")
    }

    /// หนังสือรับรองสภาวิศวกร for slot 6 is valid 120 days.
    private var coeRow: some View {
        HomeDateRow(title: "หนังสือรับรองสภาวิศวกร", date: $home.coeCertIssued, caption: coeText,
                    warning: (home.coeCertDaysLeft() ?? 1) < 0, setLabel: "ใส่วันที่ออก")
    }

    private var coeText: String {
        guard let left = home.coeCertDaysLeft() else { return "ใช้ได้ 120 วันนับจากวันที่ออก" }
        return left < 0 ? "หมดอายุแล้ว \(-left) วัน | ขอฉบับใหม่" : "ใช้ได้อีก \(left) วัน"
    }

    // MARK: Stages

    var stageStrip: some View {
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

    @ViewBuilder func stageCard(_ stage: HomeStage) -> some View {
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
        case .site: ContractorWorkView(job: job, home: $home,
                                       start: spec.id == "delivery" ? .delivery : spec.id == "contractorAccept" ? .accept : .order)
        case .roofWeight, nil: EmptyView()
        }
    }
}

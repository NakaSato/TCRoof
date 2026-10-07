import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

/// Work with the installer on one home job, in five steps: work order → materials → changes → punch list →
/// acceptance. Signatures are taken on this device; each step prints a PDF for the installer.
struct ContractorWorkView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case order = "ใบสั่งงาน", delivery = "รับของ", changes = "เปลี่ยนแปลง", punch = "Punch list", accept = "ตรวจรับ"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .order: "doc.text"
            case .delivery: "shippingbox"
            case .changes: "arrow.triangle.branch"
            case .punch: "checklist"
            case .accept: "checkmark.seal"
            }
        }
    }

    let job: Job
    @Binding var home: HomeJob
    /// Tab to open on: the document row that opened the screen.
    var start: Tab = .order

    @State private var tab: Tab = .order
    @State private var started = false
    @State private var boq: HomeBOQ?
    @State private var library = HomeLibrary()
    @State private var signing: SignTarget?
    @State private var share: URL?

    enum SignTarget: String, Identifiable { case order, delivery, accept; var id: String { rawValue } }

    var store: PermitStore { PermitStore(job: job) }
    var site: Binding<HomeSite> { $home.site }

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "ผู้รับเหมา", trail: ["งานบ้าน", job.code], current: "ผู้รับเหมา") {}
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) { page }
                    .padding(isPhone ? Space.l : Space.xl)
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { load() }
        .sheet(item: $signing) { target in
            SiteSignatureSheet(title: signTitle(target), defaultName: target == .accept ? "" : home.site.workOrder.contractor, store: store) { sig in
                if let sig { apply(sig, to: target) }
                signing = nil
            }
        }
        .sheet(item: Binding(get: { share.map(ShareFile.init) }, set: { share = $0?.url })) { ActivitySheet(items: [$0.url]) }
    }

    struct ShareFile: Identifiable { let url: URL; var id: URL { url } }

    private func load() {
        if !started { tab = start; started = true }
        library = PermitStore.library.load(HomeLibrary.self, PermitStore.libraryFile) ?? HomeLibrary()
        boq = store.load(HomeBOQ.self, BOQView.file)
        var o = home.site.workOrder
        if o.number.isEmpty { o.number = "WO-" + job.code }
        if o.scope.isEmpty { o.scope = HomeWorkOrder.standardScope(home) }
        if o.labor == 0, let b = boq { o.labor = b.lines.reduce(0) { $0 + $1.laborTotal } }
        if o.revision < (boq?.revision ?? 1) { o.revision = boq?.revision ?? 1 }
        if o != home.site.workOrder { home.site.workOrder = o }
    }

    private func signTitle(_ t: SignTarget) -> String {
        switch t {
        case .order: "ผู้รับเหมาเซ็นรับใบสั่งงาน"
        case .delivery: "ผู้รับเหมาเซ็นรับของ"
        case .accept: "ผู้ตรวจรับงาน"
        }
    }

    private func apply(_ sig: HomeSignature, to t: SignTarget) {
        switch t {
        case .order: home.site.workOrder.accepted = sig
        case .delivery: home.site.delivery.received = sig
        case .accept: home.site.accepted = sig
        }
    }

    func exportPDF(_ doc: SiteDocRenderer.Doc, name: String) {
        let data = SiteDocRenderer.pdf(doc, company: library.company, store: store)
        let file = (name + " " + job.code + ".pdf").replacingOccurrences(of: "/", with: "-")
        HomeArchive.keep(data, name: file, job: job)
        share = store.exportURL(data, fileName: file)
    }

    // MARK: Tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(Tab.allCases) { t in
                    Button { tab = t } label: {
                        HStack(spacing: 6) {
                            Image(systemName: done(t) ? "checkmark.circle.fill" : t.icon)
                                .foregroundStyle(done(t) ? Theme.okTick : (tab == t ? Theme.primary : Theme.inkMuted))
                            Text(t.rawValue).font(.sarabun(14, .semibold, relativeTo: .body))
                                .foregroundStyle(tab == t ? Theme.primary : Theme.navy)
                        }
                        .padding(.horizontal, Space.m).frame(minHeight: touchMin)
                        .background(tab == t ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(tab == t ? Theme.primary : Theme.borderSubtle))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
            }
            .padding(.horizontal, isPhone ? Space.l : Space.xl).padding(.vertical, Space.s)
        }
    }

    private func done(_ t: Tab) -> Bool {
        let s = home.site
        switch t {
        case .order: return s.workOrder.accepted != nil
        case .delivery: return s.delivery.isComplete
        case .changes: return !s.changes.isEmpty && s.pendingChanges.isEmpty
        case .punch: return !s.punches.isEmpty && s.openPunches.isEmpty
        case .accept: return s.accepted != nil
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .order: orderPage
        case .delivery: deliveryPage
        case .changes: SiteChangesPage(job: job, home: $home, store: store) { exportPDF($0, name: $1) }
        case .punch: SitePunchPage(home: $home, store: store)
        case .accept: acceptPage
        }
    }

    // MARK: Work order

    private var orderPage: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            orderFacts
            scopeCard
            if !home.site.workOrder.issues.isEmpty { PermitIssuesCard(issues: home.site.workOrder.issues) }
            signCard(title: "ผู้รับเหมาเซ็นรับใบสั่งงาน", sig: home.site.workOrder.accepted, target: .order,
                     disabled: !home.site.workOrder.issues.isEmpty) { exportPDF(orderDoc, name: "ใบสั่งงาน") }
        }
    }

    private var orderFacts: some View {
        PermitSection(title: "ใบสั่งงาน", subtitle: "ทำงานตาม BOQ และชุดแบบ Rev.\(home.site.workOrder.revision)") {
            PermitRow {
                PermitField("เลขที่", text: site.workOrder.number)
                PermitField("ผู้รับเหมา", text: site.workOrder.contractor, required: true)
            }
            PermitRow {
                PermitField("โทรผู้รับเหมา", text: site.workOrder.contractorPhone, keyboard: .phonePad)
                PermitField("ผู้ติดต่อหน้างาน", text: site.workOrder.siteContact)
            }
            HomeDateRow(title: "วันเข้างาน", date: site.workOrder.start, caption: "นัดลูกค้าและส่งของก่อนวันนี้")
            HomeDateRow(title: "วันเสร็จตามแผน", date: site.workOrder.finish, caption: "รวมทดสอบและเก็บกวาด")
            BOQNumberField(title: "ค่าแรงที่ตกลง (ทั้งงาน)", value: site.workOrder.labor, unit: "บาท")
            if let b = boq {
                let fromBOQ = b.lines.reduce(0) { $0 + $1.laborTotal }
                Text("ค่าแรงใน BOQ " + BOQRenderer.money(fromBOQ) + " บาท").font(.sarabun(TypeScale.caption, relativeTo: .caption))
                    .foregroundStyle(Theme.inkMuted)
            } else {
                Text("ยังไม่มี BOQ ทำ BOQ ในขั้นออกแบบก่อนเพื่อดึงค่าแรงและรายการของ").font(.sarabun(TypeScale.caption, relativeTo: .caption))
                    .foregroundStyle(Theme.pending)
            }
            PermitField("หมายเหตุ", text: site.workOrder.notes)
        }
    }

    private var scopeCard: some View {
        PermitSection(title: "ขอบเขตงาน", subtitle: "หนึ่งบรรทัดต่อหนึ่งงาน") {
            ForEach(home.site.workOrder.scope.indices, id: \.self) { i in
                HStack(spacing: Space.s) {
                    TCTextField("งาน", text: Binding(get: { i < home.site.workOrder.scope.count ? home.site.workOrder.scope[i] : "" },
                                                     set: { if i < home.site.workOrder.scope.count { home.site.workOrder.scope[i] = $0 } }))
                    Button(role: .destructive) { home.site.workOrder.scope.remove(at: i) } label: {
                        Image(systemName: "minus.circle").frame(width: touchMin, height: touchMin)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.dangerText).accessibilityLabel("ลบงานนี้")
                }
            }
            HStack(spacing: Space.s) {
                TCButton("เพิ่มงาน", systemImage: "plus", kind: .secondary, size: .card) { home.site.workOrder.scope.append("") }
                TCButton("ขอบเขตมาตรฐาน", systemImage: "arrow.counterclockwise", kind: .secondary, size: .card) {
                    home.site.workOrder.scope = HomeWorkOrder.standardScope(home)
                }
            }
        }
    }

    private var orderDoc: SiteDocRenderer.Doc {
        let o = home.site.workOrder
        var d = SiteDocRenderer.Doc(title: "ใบสั่งงานติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์บนหลังคา", number: o.number, facts: [
            ("ผู้รับเหมา", o.contractor + (o.contractorPhone.isEmpty ? "" : " โทร " + o.contractorPhone)),
            ("สถานที่", job.address),
            ("ลูกค้า / ผู้ติดต่อหน้างาน", [job.customerName, o.siteContact].filter { !$0.isEmpty }.joined(separator: " · ")),
            ("ระบบ", "แผง \(home.pvKWp) kWp · อินเวอร์เตอร์ \(home.inverterKW) kW" + (home.phase.map { " · " + $0.title } ?? "")),
            ("ชุดแบบ / BOQ", "Rev.\(o.revision)"),
            ("ระยะเวลา", [o.start.map(PermitDate.long), o.finish.map(PermitDate.long)].compactMap { $0 }.joined(separator: " ถึง ")),
            ("ค่าแรงที่ตกลง", BOQRenderer.money(o.labor) + " บาท (ไม่รวม VAT)"),
        ])
        d.columns = [("ลำดับ", 0.08, .center), ("ขอบเขตงาน", 0.92, .left)]
        d.rows = o.scope.filter { !$0.isEmpty }.enumerated().map { ["\($0.offset + 1)", $0.element] }
        if !o.notes.isEmpty { d.notes.append("หมายเหตุ: " + o.notes) }
        d.notes.append("ผู้รับเหมาต้องทำตามชุดแบบ Rev. ที่ระบุ การเปลี่ยนแปลงใดๆ ต้องมีใบขอเปลี่ยนแปลงที่อนุมัติแล้วก่อนลงมือ")
        d.signatures = [("ผู้สั่งงาน", nil), ("ผู้รับเหมา", o.accepted)]
        return d
    }

    // MARK: Delivery

    private var deliveryPage: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            deliveryHeader
            ForEach(home.site.delivery.items) { deliveryRow($0.id) }
            if !home.site.delivery.issues.isEmpty { PermitIssuesCard(issues: home.site.delivery.issues) }
            if !home.site.delivery.items.isEmpty {
                signCard(title: "ผู้รับเหมาเซ็นรับของ", sig: home.site.delivery.received, target: .delivery,
                         disabled: home.site.delivery.items.contains { $0.delivered == nil }) { exportPDF(deliveryDoc, name: "ใบส่งของ") }
            }
        }
    }

    private var deliveryHeader: some View {
        PermitSection(title: "ใบส่งของ / รับวัสดุหน้างาน",
                      subtitle: home.site.delivery.items.isEmpty ? "สร้างจาก BOQ ฉบับต้นทุน" : "\(home.site.delivery.items.count) รายการ") {
            HomeDateRow(title: "วันส่งของ", date: site.delivery.deliveredOn, caption: "ของถึงหน้างาน")
            HStack(spacing: Space.s) {
                TCButton(home.site.delivery.items.isEmpty ? "สร้างจาก BOQ" : "สร้างใหม่จาก BOQ", systemImage: "list.bullet.rectangle",
                         kind: .secondary, size: .card) {
                    if let b = boq { home.site.delivery.items = HomeDelivery.from(b).items; home.site.delivery.received = nil }
                }
                .disabled(boq == nil)
                if !home.site.delivery.items.isEmpty {
                    TCButton("ครบตามแผนทุกรายการ", systemImage: "checkmark", kind: .secondary, size: .card) {
                        for i in home.site.delivery.items.indices where home.site.delivery.items[i].delivered == nil {
                            home.site.delivery.items[i].delivered = home.site.delivery.items[i].planned
                        }
                    }
                }
            }
        }
    }

    private func itemBinding(_ id: String) -> Binding<HomeDelivery.Item> {
        Binding(get: { home.site.delivery.items.first { $0.id == id } ?? HomeDelivery.Item(id: id, description: "", unit: "", planned: 0) },
                set: { new in if let i = home.site.delivery.items.firstIndex(where: { $0.id == id }) { home.site.delivery.items[i] = new } })
    }

    private func deliveryRow(_ id: String) -> some View {
        let item = itemBinding(id)
        let v = item.wrappedValue
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top) {
                Text(v.description).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Text("แผน \(HomeBOQ.kw(v.planned)) \(v.unit)").font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            PermitRow {
                BOQNumberField(title: "ส่งจริง", value: Binding(get: { item.wrappedValue.delivered ?? 0 }, set: { item.wrappedValue.delivered = $0 }),
                               unit: v.unit)
                BOQNumberField(title: "คืน", value: item.returned, unit: v.unit)
            }
            if v.needsSerials && (v.delivered ?? 0) > 0 { serialFields(item) }
        }
        .padding(Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(v.delivered != nil && v.short > 0 ? Theme.danger : Theme.borderSubtle))
    }

    private func serialFields(_ item: Binding<HomeDelivery.Item>) -> some View {
        let count = max(1, Int(item.wrappedValue.delivered ?? 1))
        return VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel("Serial No.")
            ForEach(0..<count, id: \.self) { k in
                TCTextField("S/N เครื่องที่ \(k + 1)", text: Binding(
                    get: { k < item.wrappedValue.serials.count ? item.wrappedValue.serials[k] : "" },
                    set: { new in
                        var s = item.wrappedValue.serials
                        while s.count <= k { s.append("") }
                        s[k] = new
                        item.wrappedValue.serials = s
                    }))
            }
        }
    }

    private var deliveryDoc: SiteDocRenderer.Doc {
        let d = home.site.delivery
        var doc = SiteDocRenderer.Doc(title: "ใบส่งของ / รับวัสดุหน้างาน", number: home.site.workOrder.number, facts: [
            ("ผู้รับเหมา", home.site.workOrder.contractor),
            ("สถานที่", job.address),
            ("วันส่งของ", d.deliveredOn.map(PermitDate.long) ?? ""),
        ])
        doc.columns = [("รายการ", 0.46, .left), ("หน่วย", 0.09, .center), ("แผน", 0.09, .center), ("ส่งจริง", 0.09, .center),
                       ("คืน", 0.08, .center), ("S/N", 0.19, .left)]
        doc.rows = d.items.map { i in
            [i.description, i.unit, HomeBOQ.kw(i.planned), i.delivered.map(HomeBOQ.kw) ?? "", i.returned > 0 ? HomeBOQ.kw(i.returned) : "",
             i.serials.filter { !$0.isEmpty }.joined(separator: ", ")]
        }
        doc.notes = d.issues
        doc.signatures = [("ผู้ส่งของ", nil), ("ผู้รับเหมา (ผู้รับของ)", d.received)]
        return doc
    }

    // MARK: Acceptance

    private var acceptPage: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PermitSection(title: "ตรวจรับงานผู้รับเหมา", subtitle: "ใช้เป็นหลักฐานวางบิลค่าแรง") {
                money("ค่าแรงตามใบสั่งงาน", home.site.workOrder.labor)
                money("ใบขอเปลี่ยนแปลงที่อนุมัติ", home.site.approvedLaborDelta)
                BOQNumberField(title: "รายการหัก (ของเสียหาย ของขาด)", value: site.deductions, unit: "บาท")
                if home.site.deductions > 0 { PermitField("เหตุผลที่หัก", text: site.deductionNote) }
                money("ค่าแรงที่ต้องจ่าย", home.site.laborPayable, bold: true)
            }
            if !home.site.acceptanceBlockers.isEmpty { PermitIssuesCard(issues: home.site.acceptanceBlockers) }
            signCard(title: "ตรวจรับงาน", sig: home.site.accepted, target: .accept,
                     disabled: !home.site.acceptanceBlockers.isEmpty) { exportPDF(acceptDoc, name: "ใบตรวจรับงานผู้รับเหมา") }
        }
    }

    private func money(_ label: String, _ v: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.sarabun(15, bold ? .bold : .regular, relativeTo: .body)).foregroundStyle(Theme.navy)
            Spacer()
            Text(BOQRenderer.money(v) + " บาท").font(.sarabun(15, bold ? .bold : .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                .monospacedDigit()
        }
    }

    private var acceptDoc: SiteDocRenderer.Doc {
        let s = home.site
        var d = SiteDocRenderer.Doc(title: "ใบตรวจรับงานผู้รับเหมา", number: s.workOrder.number, facts: [
            ("ผู้รับเหมา", s.workOrder.contractor),
            ("สถานที่", job.address),
            ("ระบบ", "แผง \(home.pvKWp) kWp · อินเวอร์เตอร์ \(home.inverterKW) kW"),
        ])
        d.columns = [("รายการ", 0.7, .left), ("บาท", 0.3, .right)]
        d.rows = [["ค่าแรงตามใบสั่งงาน", BOQRenderer.money(s.workOrder.labor)]]
        for c in s.changes where c.status == .approved && c.laborDelta != 0 {
            d.rows.append(["ใบขอเปลี่ยนแปลงที่ \(c.number): \(c.title)", BOQRenderer.money(c.laborDelta)])
        }
        if s.deductions > 0 { d.rows.append(["หัก: " + (s.deductionNote.isEmpty ? "รายการหัก" : s.deductionNote), "-" + BOQRenderer.money(s.deductions)]) }
        d.rows.append(["ค่าแรงที่ต้องจ่าย (ไม่รวม VAT)", BOQRenderer.money(s.laborPayable)])
        d.notes = ["Punch list ปิดครบ \(s.punches.count) รายการ · ใบขอเปลี่ยนแปลง \(s.changes.count) ใบ"]
        d.signatures = [("ผู้รับเหมา", nil), ("ผู้ตรวจรับงาน", s.accepted)]
        return d
    }

    // MARK: Signing

    func signCard(title: String, sig: HomeSignature?, target: SignTarget, disabled: Bool, pdf: @escaping () -> Void) -> some View {
        PermitSection(title: title, subtitle: sig.map { "\($0.name) · \(PermitDate.long($0.at))" } ?? "เซ็นบนเครื่องนี้ได้เลย") {
            if let sig, let img = store.photo(sig.file).flatMap(UIImage.init(data:)) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 90)
                    .accessibilityLabel("ลายเซ็นของ \(sig.name)")
            }
            HStack(spacing: Space.s) {
                TCButton(sig == nil ? "เซ็น" : "เซ็นใหม่", systemImage: "signature", kind: sig == nil ? .primary : .secondary, size: .card) {
                    signing = target
                }
                .disabled(disabled)
                TCButton("PDF", systemImage: "square.and.arrow.up", kind: .secondary, size: .card) { pdf() }
            }
            if disabled && sig == nil {
                Text("แก้รายการด้านบนให้ครบก่อนเซ็น").font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.pending)
            }
        }
    }
}

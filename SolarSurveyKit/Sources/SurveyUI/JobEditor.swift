#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import SurveyCore
import PDFReport
import DriveSync

/// Editor for one survey: sidebar of sections grouped like the workbook sheets, paper-style form on the right.
struct JobEditorView: View {
    enum Page: Hashable { case summary, info, site, electrical, flood, module(UUID), final }

    @Environment(SurveyModel.self) private var model
    @State private var job: Job
    @State private var page: Page = .info
    @State private var preview: PDFPreviewItem?
    @State private var showExport = false
    @State private var busy: String?
    @State private var error: String?
    @State private var confirmDelete: SurveyModule?
    @State private var sidebarVisible = true
    @State private var pendingExport: PendingExport?
    struct PendingExport: Identifiable { let id = UUID(); let gaps: [String]; let go: () -> Void }
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(job: Job) { _job = State(initialValue: job) }

    /// iPhone (and narrow iPad split view): the section list and the form take turns filling the screen.
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar.frame(width: compact ? nil : 310)
                if !compact { Divider() }
            }
            if !(compact && sidebarVisible) {
                ScrollViewReader { proxy in
                    ScrollView {
                        detail.padding(compact ? 16 : 24).frame(maxWidth: 980).frame(maxWidth: .infinity).id("top")
                    }
                    .background(Paper.page)
                    .onChange(of: page) { _, _ in proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .navigationTitle(job.projectName.isEmpty ? "แบบสำรวจใหม่" : job.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: job) { _, new in model.update(new) }
        .onDisappear { model.flush(job.id) }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "surveyDemoSection") { select(.info) } }
        // `-surveyExport YES` opens the export sheet for simulator checks
        .task { if UserDefaults.standard.bool(forKey: "surveyExport") { try? await Task.sleep(nanoseconds: 600_000_000); showExport = true } }
        #endif
        .sheet(item: $preview) { p in PDFPreview(item: p) }
        // a Drive save stores the folder link on the model's copy — take it back so the next edit keeps it
        .sheet(isPresented: $showExport, onDismiss: { if let d = model.job(job.id)?.drive { job.drive = d } }) {
            ExportSheet(jobID: job.id) { select(.electrical) }.environment(model)
        }
        .overlay { if let busy { BusyOverlay(text: busy) } }
        .errorAlert($error)
        .alert("ภาพหม้อแปลงยังไม่ครบ", isPresented: Binding(get: { pendingExport != nil }, set: { if !$0 { pendingExport = nil } }), presenting: pendingExport) { p in
            Button("ไปถ่ายให้ครบ") { page = .electrical; pendingExport = nil }
            Button("ส่งออกต่อ") { let go = p.go; pendingExport = nil; go() }
            Button("ยกเลิก", role: .cancel) { pendingExport = nil }
        } message: { p in Text(p.gaps.joined(separator: "\n")) }
        .confirmationDialog("ลบหัวข้อนี้?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { m in
            Button("ลบ \(m.title)", role: .destructive) { remove(m) }
        } message: { _ in Text("ข้อมูลและรูปภาพในหัวข้อนี้จะถูกลบ") }
    }

    // MARK: sidebar

    var sidebar: some View {
        List(selection: Binding(get: { compact ? nil : Optional(page) }, set: { if let p = $0 { select(p) } })) {
            Section {
                HStack(spacing: 12) {
                    ProgressRing(value: job.completion.fraction, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NO.\(job.docNo.isEmpty ? "—" : job.docNo)").font(.headline)
                        Text("กรอกแล้ว \(job.completion.filled)/\(job.completion.total) · รูป \(job.photoCount)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                row(.summary, "สรุปภาพรวม 1 หน้า", "doc.text.magnifyingglass", Completion())
            }
            Section(SectionCategory.general.heading) {
                row(.info, "A1 ข้อมูลโครงการ", "doc.text", Schema.info.completion(job.values))
                row(.site, "A2 ภาพสถานที่ติดตั้ง", "map", Schema.site.completion(job.values))
                row(.electrical, "A3 มิเตอร์ หม้อแปลง และตู้ MDB", "bolt", Schema.electrical.completion(job.values))
                row(.flood, "A4 ประวัติน้ำท่วม", "water.waves", Schema.flood.completion(job.values))
            }
            ForEach(job.sectionsByCategory) { group in
                Section(group.category.heading) {
                    ForEach(group.sections) { item in
                        let m = item.module
                        row(.module(m.id), item.title, icon(m.type), m.completion)
                            .contextMenu {
                                Button { duplicate(m) } label: { Label("ทำสำเนาหัวข้อ", systemImage: "plus.square.on.square") }
                                Button(role: .destructive) { confirmDelete = m } label: { Label("ลบหัวข้อ", systemImage: "trash") }
                            }
                            .swipeActions { Button(role: .destructive) { confirmDelete = m } label: { Label("ลบ", systemImage: "trash") } }
                    }
                }
            }
            Section {
                Menu {
                    ForEach([SectionCategory.electrical, .roof, .water]) { cat in
                        Section(cat.heading) {
                            ForEach(ModuleType.byCode.filter { $0.category == cat }) { t in
                                Button { add(t) } label: { Label(t.code + " " + Schema.spec(t).label + "  (แผ่น " + Schema.spec(t).sheet + ")", systemImage: icon(t)) }
                            }
                        }
                    }
                } label: { Label("เพิ่มหัวข้อสำรวจ", systemImage: "plus.circle.fill").font(.body.weight(.semibold)) }
                if !job.stationOverflow.isEmpty {
                    Label("หัวข้อระบบไฟฟ้าเกินช่องในแผ่นงาน — Excel จะเพิ่มแผ่น \"ระบบไฟฟ้า (2)\" ให้อัตโนมัติ", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(SectionCategory.summary.heading) {
                row(.final, "E1 สรุปผลและลงนาม", "signature", job.finalCompletion)
            }
        }
        .listStyle(.sidebar)
    }

    func select(_ p: Page) {
        page = p
        if compact { withAnimation { sidebarVisible = false } }
    }

    func row(_ p: Page, _ title: String, _ symbol: String, _ c: Completion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(Color.accentColor)
            Text(title).lineLimit(2)
            Spacer(minLength: 4)
            if c.total > 0 {
                Text("\(c.filled)/\(c.total)").font(.caption.monospacedDigit())
                    .foregroundStyle(c.isComplete ? Paper.tick : .secondary)
                if c.isComplete { Image(systemName: "checkmark.circle.fill").foregroundStyle(Paper.tick) }
            }
        }
        .tag(p)
    }

    func icon(_ t: ModuleType) -> String {
        switch t {
        case .panel: return "rectangle.split.3x1"
        case .inverter: return "bolt.batteryblock"
        case .water: return "drop"
        case .backfeed: return "arrow.uturn.backward.circle"
        case .fts: return "exclamationmark.octagon"
        case .roof: return "house"
        case .tank: return "cylinder"
        case .sed: return "square.split.bottomrightquarter"
        case .house: return "house.lodge"
        case .roofForm: return "building.2"
        }
    }

    // MARK: detail

    @ViewBuilder var detail: some View {
        switch page {
        case .summary: summaryPage
        case .info: groupPage(Schema.info, code: "A1", title: "ข้อมูลโครงการ", subtitle: "ข้อมูลหัวกระดาษของทุกแผ่นงาน (เลขที่ วันที่ ผู้ประสานงาน ที่อยู่)")
        case .site: groupPage(Schema.site, code: "A2", title: "ภาพสถานที่ติดตั้ง", subtitle: "แผ่น ระบบไฟฟ้า — ภาพสถานที่ติดตั้ง และ LIST")
        case .electrical: groupPage(Schema.electrical, code: "A3", title: "มิเตอร์ หม้อแปลง และตู้ MDB", subtitle: "แผ่น ระบบไฟฟ้า — ผังมิเตอร์ หม้อแปลง และตู้ MDB")
        case .flood: groupPage(Schema.flood, code: "A4", title: "ประวัติน้ำท่วม", subtitle: "ใช้กำหนดความสูงติดตั้งอินเวอร์เตอร์ ตู้ SMDB/กันย้อน และแนวรางสายไฟ · แสดงในรายงาน PDF")
        case .final: groupPage(Schema.final, code: "E1", title: "สรุปผลและลงนาม", subtitle: "หน้าสุดท้ายของรายงาน PDF")
        case .module(let id):
            if let i = job.modules.firstIndex(where: { $0.id == id }) { modulePage(i) }
            else { ContentUnavailableView("เลือกหัวข้อทางซ้าย", systemImage: "sidebar.left") }
        }
    }

    var summaryPage: some View {
        let layout = ReportLayout(job: job, header: model.reportHeader, measure: PDFRenderer.Measure())
        let sheet = Sketch(width: ReportLayout.pageW, height: ReportLayout.pageH, ops: layout.summaryPage().ops)
        let jobID = job.id
        return VStack(spacing: 14) {
            Canvas { ctx, size in
                let k = size.width / CGFloat(sheet.width)
                ctx.withCGContext { cg in
                    cg.scaleBy(x: k, y: k)
                    PDFRenderer.draw(sheet.ops, in: cg, photo: { model.image($0, in: jobID) })
                }
            }
            .aspectRatio(CGFloat(sheet.width / sheet.height), contentMode: .fit)
            .background(Color.white)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            Button { checked { run("กำลังสร้าง PDF สรุป…") { let f = try model.exportSummaryPDF(job); preview = PDFPreviewItem(url: f.url, title: "สรุป " + job.projectName) } } } label: {
                Label("บันทึก PDF สรุป 1 หน้า", systemImage: "doc.richtext")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    func groupPage(_ g: GroupSpec, code: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(code + " " + title, subtitle: subtitle, completion: g.completion(job.values))
            PaperBox(title: g.title ?? "") {
                ForEach(g.fields) { f in
                    if f.isVisible(job.values) && !f.id.hasPrefix("tr") || f.id == "trafos" { FieldView(spec: f, values: $job.values, jobID: job.id, gps: job.values.text("gps")) }
                }
            }
            if page == .flood, let h = Schema.recommendedEquipHeight(job.values) {
                Label("แนะนำติดตั้งอุปกรณ์สูงจากพื้นดินอย่างน้อย \(h) ซม. (ระดับน้ำสูงสุด + 50 ซม.)", systemImage: "arrow.up.to.line")
                    .font(.callout).foregroundStyle(.blue)
            }
            if page == .electrical, job.values.transformers("trafos").isEmpty == false || !job.values.text("meterNo").isEmpty {
                Text("ค่าที่กรอกจะลงในผัง SmartArt ของแผ่น ระบบไฟฟ้า").font(.footnote).foregroundStyle(.secondary)
            }
            nextButton
        }
    }

    func modulePage(_ i: Int) -> some View {
        let m = job.modules[i], spec = m.spec
        let number = job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? spec.code
        return VStack(alignment: .leading, spacing: 16) {
            header(number + " " + spec.label, subtitle: "ไฟล์ Excel แผ่น \(spec.sheet) · ในรายงาน: \(spec.reportTitle)", completion: m.completion)
            HStack {
                Text("ชื่อ/อาคาร").foregroundStyle(.secondary)
                TextField(spec.namePlaceholder, text: $job.modules[i].name).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            }
            ForEach(spec.groups) { g in
                let c = g.completion(m.values)
                let title: String = g.title ?? (m.name.isEmpty ? spec.reportTitle : spec.reportTitle + " " + m.name)
                let trailing: String? = c.total > 0 ? "\(c.filled)/\(c.total)" : nil
                let number: String? = g.no.map { $0 + "." }
                PaperBox(title: title, number: number, trailing: trailing) {
                    ForEach(g.fields) { f in
                        if f.isVisible(job.modules[i].values) { FieldView(spec: f, values: $job.modules[i].values, jobID: job.id, moduleType: m.type, gps: job.values.text("gps")) }
                    }
                }
            }
            nextButton
        }
    }

    func header(_ title: String, subtitle: String, completion c: Completion) -> some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if !compact { Spacer() }
            if c.total > 0 {
                VStack(alignment: compact ? .leading : .trailing, spacing: 2) {
                    ProgressView(value: c.fraction).frame(width: 140).tint(c.isComplete ? Paper.tick : .accentColor)
                    Text("กรอกแล้ว \(c.filled) จาก \(c.total)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    var pages: [Page] {
        [.summary, .info, .site, .electrical, .flood] + job.sectionsByCategory.flatMap { $0.sections.map { Page.module($0.id) } } + [.final]
    }
    @ViewBuilder var nextButton: some View {
        if let i = pages.firstIndex(of: page), i + 1 < pages.count {
            HStack {
                Spacer()
                Button { withAnimation { page = pages[i + 1] } } label: { Label("หัวข้อถัดไป", systemImage: "arrow.right") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    // MARK: toolbar

    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { withAnimation { sidebarVisible.toggle() } } label: { Image(systemName: "sidebar.left") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { model.flush(job.id); showExport = true } label: {
                if compact { Label("ส่งออก", systemImage: "square.and.arrow.up") }
                else { Label("ส่งออก", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon) }
            }
            .overlay(alignment: .topTrailing) {
                // the export sheet explains the gap; this dot just says there is one
                if !job.transformerGaps.isEmpty { Circle().fill(.orange).frame(width: 8, height: 8).offset(x: 4, y: -2) }
            }
        }
    }

    /// Transformer photos are compulsory: warn before any export while some are missing.
    func checked(_ go: @escaping () -> Void) {
        let gaps = job.transformerGaps
        if gaps.isEmpty { go() } else { pendingExport = PendingExport(gaps: gaps, go: go) }
    }

    /// Runs an export on the next run-loop turn so the busy overlay shows first.
    func run(_ message: String, _ work: @escaping () throws -> Void) {
        busy = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            do { try work() } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }

    // MARK: sections

    func add(_ t: ModuleType) {
        let m = SurveyModule(type: t)
        // insert after the last section of the same sheet so the order follows the workbook
        if let last = job.modules.lastIndex(where: { $0.spec.sheet == m.spec.sheet }) { job.modules.insert(m, at: last + 1) } else { job.modules.append(m) }
        page = .module(m.id)
    }
    func duplicate(_ m: SurveyModule) {
        guard let i = job.modules.firstIndex(where: { $0.id == m.id }) else { return }
        var c = SurveyModule(type: m.type, name: m.name)
        // text answers only; photos stay with the original
        for (k, v) in m.values.storage { switch v { case .photo, .photos: continue; default: c.values[k] = v } }
        job.modules.insert(c, at: i + 1)
        page = .module(c.id)
    }
    func remove(_ m: SurveyModule) {
        if page == .module(m.id) { page = .info }
        job.modules.removeAll { $0.id == m.id }
        confirmDelete = nil
    }
}

struct BusyOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) { ProgressView().controlSize(.large); Text(text) }
                .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct PDFPreviewItem: Identifiable { let id = UUID(); let url: URL; let title: String }

struct PDFPreview: View {
    let item: PDFPreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    var body: some View {
        NavigationStack {
            PDFKitView(url: item.url)
                .navigationTitle("รายงาน " + item.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button { sharing = true } label: { Label("แชร์", systemImage: "square.and.arrow.up") } }
                }
                .sheet(isPresented: $sharing) { ShareSheet(items: [item.url]) }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .secondarySystemBackground
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}
#endif

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
    @State private var collapsed: Set<SectionCategory> = []
    @State private var pendingExport: PendingExport?
    struct PendingExport: Identifiable { let id = UUID(); let gaps: [String]; let target: MissingGroup.Target; let go: () -> Void }
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
            ExportSheet(jobID: job.id) { select(page(for: $0)) }.environment(model)
        }
        .overlay { if let busy { BusyOverlay(text: busy) } }
        .errorAlert($error)
        .alert("ข้อมูลยังไม่ครบ", isPresented: Binding(get: { pendingExport != nil }, set: { if !$0 { pendingExport = nil } }), presenting: pendingExport) { p in
            Button("ไปกรอกให้ครบ") { let t = p.target; pendingExport = nil; select(page(for: t)) }
            Button("ส่งออกต่อ") { let go = p.go; pendingExport = nil; go() }
            Button("ยกเลิก", role: .cancel) { pendingExport = nil }
        } message: { p in Text(p.gaps.joined(separator: "\n")) }
        .confirmationDialog("ลบหัวข้อนี้?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { m in
            Button("ลบ \(m.title)", role: .destructive) { remove(m) }
        } message: { _ in Text("ข้อมูลและรูปภาพในหัวข้อนี้จะถูกลบ") }
    }

    // MARK: sidebar

    /// One entry in the sidebar: code badge, short title, and how much of it is filled.
    struct SidebarItem: Identifiable {
        let page: Page
        let code: String
        let title: String
        let completion: Completion
        var module: SurveyModule? = nil
        var id: Page { page }
    }
    struct SidebarGroup: Identifiable {
        let category: SectionCategory
        let items: [SidebarItem]
        var id: SectionCategory { category }
    }

    /// Sections in workbook order, grouped by category (A general, B–D added sections, E sign-off).
    var sidebarGroups: [SidebarGroup] {
        let general = SidebarGroup(category: .general, items: [
            SidebarItem(page: .info, code: "A1", title: "ข้อมูลโครงการ", completion: Schema.info.completion(job.values)),
            SidebarItem(page: .site, code: "A2", title: "ภาพสถานที่ติดตั้ง", completion: Schema.site.completion(job.values)),
            SidebarItem(page: .electrical, code: "A3", title: "มิเตอร์ หม้อแปลง และตู้ MDB", completion: Schema.electrical.completion(job.values)),
            SidebarItem(page: .flood, code: "A4", title: "ประวัติน้ำท่วม", completion: Schema.flood.completion(job.values)),
        ])
        let added = job.sectionsByCategory.map { g in
            SidebarGroup(category: g.category, items: g.sections.map {
                SidebarItem(page: .module($0.id), code: $0.number, title: $0.module.title, completion: $0.module.completion, module: $0.module)
            })
        }
        let final = SidebarGroup(category: .summary, items: [SidebarItem(page: .final, code: "E1", title: "สรุปผลและลงนาม", completion: job.finalCompletion)])
        return [general] + added + [final]
    }

    /// First section with required fields still empty — the header's "continue" shortcut.
    var nextIncomplete: SidebarItem? {
        sidebarGroups.flatMap(\.items).first { $0.completion.total > 0 && !$0.completion.isComplete }
    }

    func category(of p: Page) -> SectionCategory? {
        switch p {
        case .summary: return nil
        case .info, .site, .electrical, .flood: return .general
        case .final: return .summary
        case .module(let id): return job.modules.first { $0.id == id }?.spec.category
        }
    }

    var sidebar: some View {
        let groups = sidebarGroups
        return List(selection: Binding(get: { compact ? nil : Optional(page) }, set: { if let p = $0 { select(p) } })) {
            Section { sidebarHeader }.listRowBackground(Color(uiColor: .systemBackground))
            Section {
                row(SidebarItem(page: .summary, code: "", title: "สรุปภาพรวม 1 หน้า", completion: Completion()), symbol: "doc.text.magnifyingglass")
            }
            ForEach(groups) { g in
                Section(isExpanded: expanded(g.category)) {
                    ForEach(g.items) { item in
                        if let m = item.module {
                            row(item)
                                .contextMenu {
                                    Button { duplicate(m) } label: { Label("ทำสำเนาหัวข้อ", systemImage: "plus.square.on.square") }
                                    Button(role: .destructive) { confirmDelete = m } label: { Label("ลบหัวข้อ", systemImage: "trash") }
                                }
                                .swipeActions { Button(role: .destructive) { confirmDelete = m } label: { Label("ลบ", systemImage: "trash") } }
                        } else {
                            row(item)
                        }
                    }
                } header: {
                    groupHeader(g)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Paper.page)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
        // keep the open section visible when "next" or "continue" jumps into a collapsed group
        .onChange(of: page) { _, p in if let c = category(of: p) { collapsed.remove(c) } }
    }

    func expanded(_ c: SectionCategory) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(c) }, set: { open in withAnimation { if open { collapsed.remove(c) } else { collapsed.insert(c) } } })
    }

    var sidebarHeader: some View {
        let c = job.completion
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NO.\(job.docNo.isEmpty ? "—" : job.docNo)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(job.projectName.isEmpty ? "(ยังไม่ได้ตั้งชื่อโครงการ)" : job.projectName).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text("\(c.percent)%").font(.title2.bold()).monospacedDigit().foregroundStyle(c.isComplete ? Paper.tick : .primary)
            }
            ProgressView(value: c.fraction).tint(c.isComplete ? Paper.tick : .accentColor)
            HStack {
                Text("กรอกแล้ว \(c.filled)/\(c.total)")
                Spacer()
                Label("\(job.photoCount)", systemImage: "photo")
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let next = nextIncomplete, next.page != page {
                Button { select(next.page) } label: {
                    Label("ไปต่อ: \(next.code) \(next.title)", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    func groupHeader(_ g: SidebarGroup) -> some View {
        let done = g.items.filter(\.completion.isComplete).count
        return HStack {
            Text(g.category.heading)
            Spacer()
            Text("\(done)/\(g.items.count)").monospacedDigit()
                .foregroundStyle(done == g.items.count ? Paper.tick : .secondary)
        }
    }

    var sidebarFooter: some View {
        VStack(spacing: 8) {
            if !job.stationOverflow.isEmpty {
                Label("หัวข้อระบบไฟฟ้าเกินช่องในแผ่นงาน — Excel จะเพิ่มแผ่น \"ระบบไฟฟ้า (2)\" ให้อัตโนมัติ", systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Menu {
                ForEach([SectionCategory.electrical, .roof, .water]) { cat in
                    Section(cat.heading) {
                        ForEach(ModuleType.byCode.filter { $0.category == cat }) { t in
                            Button { add(t) } label: { Label(t.code + " " + Schema.spec(t).label + "  (แผ่น " + Schema.spec(t).sheet + ")", systemImage: icon(t)) }
                        }
                    }
                }
            } label: {
                Label("เพิ่มหัวข้อสำรวจ", systemImage: "plus").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .menuStyle(.button).buttonStyle(.bordered).controlSize(.large)
        }
        .padding(12)
        .background(.bar)
    }

    func select(_ p: Page) {
        page = p
        if compact { withAnimation { sidebarVisible = false } }
    }

    /// Code badge, one-line title, status mark; finished sections step back so open work stands out.
    func row(_ item: SidebarItem, symbol: String? = nil) -> some View {
        let c = item.completion
        let selected = !compact && page == item.page
        return HStack(spacing: 10) {
            Group {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
                else { Text(item.code).font(.caption.weight(.bold)).monospacedDigit() }
            }
            .foregroundStyle(selected ? Color.white : Paper.ink)
            .frame(minWidth: 38, minHeight: 22)
            .padding(.horizontal, 2)
            .background(selected ? Color.accentColor : Paper.band, in: RoundedRectangle(cornerRadius: 6))
            Text(item.title).lineLimit(1)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.accentColor : c.isComplete ? .secondary : .primary)
            Spacer(minLength: 4)
            StatusMark(completion: c)
        }
        .tag(item.page)
        // own selection look: the system one turns solid blue while the list has focus and hides the badge and status
        .listRowBackground(selected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityValue(c.total > 0 ? "กรอกแล้ว \(c.filled) จาก \(c.total)" : "")
        .help(item.code + " " + item.title)
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
        [.summary] + sidebarGroups.flatMap { $0.items.map(\.page) }
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
                if !job.missingGroups.isEmpty { Circle().fill(.orange).frame(width: 8, height: 8).offset(x: 4, y: -2) }
            }
        }
    }

    /// Warns before an export while required answers are missing, listing them per page.
    func checked(_ go: @escaping () -> Void) {
        let groups = job.missingGroups
        guard let first = groups.first else { return go() }
        pendingExport = PendingExport(gaps: groups.map { "\($0.title): \($0.items.count) รายการ" }, target: first.target, go: go)
    }

    func page(for target: MissingGroup.Target) -> Page {
        switch target {
        case .info: return .info
        case .site: return .site
        case .electrical: return .electrical
        case .flood: return .flood
        case .module(let id): return .module(id)
        case .final: return .final
        }
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

/// Sidebar status: empty circle, partial ring with count, or a green check.
struct StatusMark: View {
    let completion: Completion
    var body: some View {
        let c = completion
        if c.total == 0 {
            EmptyView()
        } else if c.isComplete {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Paper.tick)
        } else if c.filled == 0 {
            Circle().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1.5).frame(width: 17, height: 17)
        } else {
            HStack(spacing: 5) {
                Text("\(c.filled)/\(c.total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                    Circle().trim(from: 0, to: c.fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
            }
        }
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

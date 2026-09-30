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

    @Environment(SurveyModel.self) var model
    @State var job: Job
    @State var page: Page = .info
    @State var preview: PDFPreviewItem?
    @State var showExport = false
    @State var busy: String?
    @State var error: String?
    @State var confirmDelete: SurveyModule?
    @State var sidebarVisible = true
    @State var collapsed: Set<SectionCategory> = []
    @State var pendingExport: PendingExport?
    struct PendingExport: Identifiable { let id = UUID(); let gaps: [String]; let target: MissingGroup.Target?; let go: () -> Void }
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) var dismiss

    /// - Parameter start: page to open on (the home card's "continue" step); nil opens A1.
    init(job: Job, start: MissingGroup.Target? = nil) {
        _job = State(initialValue: job)
        if let start {
            _page = State(initialValue: Self.page(for: start))
            _startedOnPage = State(initialValue: true)
        }
    }
    @State var startedOnPage = false

    /// iPhone (and narrow iPad split view): the section list and the form take turns filling the screen.
    var compact: Bool { sizeClass == .compact }

    @State var detailSize: CGSize = .zero
    /// A1 in the card layout on iPad (docs/ui/survey-a1); iPhone keeps the one-column `groupPage`.
    var cardInfo: Bool { page == .info && !compact }
    /// Two columns on one screen in landscape; portrait stacks the same cards in one column.
    var infoColumns: Int {
        guard detailSize.width >= 860 else { return 1 }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "surveyWideA1") { return 2 }
        #endif
        return detailSize.width > detailSize.height ? 2 : 1
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar.frame(width: compact ? nil : 310)
                if !compact { Divider() }
            }
            if !(compact && sidebarVisible) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if cardInfo {
                                InfoPageWide(job: $job, width: min(detailSize.width, 1240 + 48) - 48, twoColumns: infoColumns == 2)
                                    .padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 1240 + 48)
                            } else {
                                detail.padding(compact ? 16 : 24).frame(maxWidth: 980)
                            }
                        }
                        .frame(maxWidth: .infinity).id("top")
                    }
                    .background(Paper.page)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if cardInfo {
                            InfoPageHeader(job: job, back: { dismiss() },
                                           toggleSidebar: { withAnimation { sidebarVisible.toggle() } },
                                           export: { model.flush(job.id); showExport = true })
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if cardInfo { InfoPageBar(job: job, narrow: detailSize.width < 900, next: nextPage.map { p in { withAnimation { page = p } } }) }
                    }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { detailSize = $0 }
                    .onChange(of: page) { _, _ in proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .navigationTitle(job.projectName.isEmpty ? "แบบสำรวจใหม่" : job.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // A1's blue header carries back, sidebar and export itself
        .toolbar(cardInfo ? .hidden : .visible, for: .navigationBar)
        // the model owns the Drive link (uploads and other devices change it); this copy only mirrors it
        .onChange(of: job) { _, new in var j = new; j.drive = model.job(new.id)?.drive ?? new.drive; model.update(j) }
        // the Drive link changes elsewhere (export sheet, another device) — take it so the next edit doesn't drop it
        .onChange(of: model.job(job.id)?.drive) { _, d in if let d, d != job.drive { job.drive = d } }
        // photos taken on another iPad: fetch them from Drive now, and again when that iPad uploads more
        .task(id: model.job(job.id)?.drive?.photoFiles?.count ?? 0) { await model.fetchMissingPhotos(job.id) }
        // photos an earlier upload didn't finish, or taken before signing in to Google
        .onAppear { model.autoUploadPhotos(job.id, after: 2) }
        .onDisappear { model.flush(job.id) }
        // opened from "continue": on iPhone show that form rather than the section list
        .onAppear { if startedOnPage && compact { sidebarVisible = false } }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "surveyDemoSection") { select(.info) } }
        // `-surveyWideA1 YES` shows A1's two-column (landscape) layout in any orientation, sidebar hidden (simulators can't be turned from the command line)
        .onAppear { if UserDefaults.standard.bool(forKey: "surveyWideA1") { sidebarVisible = false } }
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
            if let t = p.target { Button("ไปกรอกให้ครบ") { pendingExport = nil; select(page(for: t)) } }
            Button("ส่งออกต่อ") { let go = p.go; pendingExport = nil; go() }
            Button("ยกเลิก", role: .cancel) { pendingExport = nil }
        } message: { p in Text(p.gaps.joined(separator: "\n")) }
        .confirmationDialog("ลบหัวข้อนี้?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { m in
            Button("ลบ \(m.title)", role: .destructive) { remove(m) }
        } message: { _ in Text("ข้อมูลและรูปภาพในหัวข้อนี้จะถูกลบ") }
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

    /// Warns before a PDF export while required answers or signatures are missing, listing them per page.
    func checked(_ go: @escaping () -> Void) {
        let groups = job.missingGroups
        let photos = PhotoGap(model: model, job: job)
        let unsigned = job.missingSignatures
        guard !groups.isEmpty || photos.missing > 0 else { return go() }
        let lines = (unsigned.isEmpty ? [] : ["PDF ที่ส่ง กปภ. ยังไม่มี" + unsigned.joined(separator: " และ")])
            + (photos.missing > 0 ? [photos.message] : []) + groups.map { "\($0.title): \($0.items.count) รายการ" }
        pendingExport = PendingExport(gaps: lines, target: unsigned.isEmpty ? groups.first?.target : .final, go: go)
    }

    func page(for target: MissingGroup.Target) -> Page { Self.page(for: target) }
    static func page(for target: MissingGroup.Target) -> Page {
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
        job.insertModule(m)
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

extension Job {
    /// Adds a section after the last one of the same sheet so the order follows the workbook.
    mutating func insertModule(_ m: SurveyModule) {
        if let last = modules.lastIndex(where: { $0.spec.sheet == m.spec.sheet }) { modules.insert(m, at: last + 1) } else { modules.append(m) }
    }
}
#endif

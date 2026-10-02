#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
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
        // a survey moved to installation opens on its report summary
        if start == nil, job.stage != .survey { _page = State(initialValue: .summary) }
        if let start {
            _page = State(initialValue: Self.page(for: start))
            _startedOnPage = State(initialValue: true)
        }
    }
    @State var startedOnPage = false

    /// iPhone (and narrow iPad split view): the section list and the form take turns filling the screen.
    var compact: Bool { sizeClass == .compact }

    /// A survey moved to installation is kept as it was: view and export only.
    var readOnly: Bool { job.stage != .survey }

    @State var detailSize: CGSize = .zero
    /// A1 in the card layout (docs/ui/survey-a1); one column on iPad portrait and iPhone.
    var cardInfo: Bool { page == .info && !compact }
    /// A2's picture page (docs/ui/survey-a2): side by side in landscape, stacked in portrait; iPhone keeps `groupPage`.
    var cardSite: Bool { page == .site && !compact }
    /// A3's power-flow diagram (docs/ui/survey-a3) zooms to fit, so portrait iPad uses it too; iPhone keeps `groupPage`.
    var cardElectrical: Bool { page == .electrical && !compact }
    /// A4's flood page (docs/ui/survey-a4): side by side in landscape, stacked in portrait; iPhone keeps `groupPage`.
    var cardFlood: Bool { page == .flood && !compact }
    /// B2 on iPad (docs/ui/survey-b2): the section being shown, side by side in landscape and stacked in portrait;
    /// iPhone keeps `groupPage`.
    var cardInverter: SurveyModule? {
        guard case .module(let id) = page, !compact else { return nil }
        return job.modules.first { $0.id == id && $0.type == .inverter }
    }
    /// B1 on iPad (docs/ui/survey-b1): every building on one page, side by side in landscape and stacked in portrait;
    /// iPhone, and a building whose old form was asked for, keep `groupPage`.
    var cardPanels: SurveyModule? {
        guard case .module(let id) = page, !compact, panelForm != id else { return nil }
        return job.modules.first { $0.id == id && $0.type == .panel }
    }
    /// B3 on iPad (docs/ui/survey-b3): the water point on the A2 picture, the mode, photos and details; one screen in
    /// landscape, one scrolling column in portrait. iPhone keeps `groupPage`.
    var cardWater: SurveyModule? {
        guard case .module(let id) = page, !compact else { return nil }
        return job.modules.first { $0.id == id && $0.type == .water }
    }
    /// B5 on iPad landscape (docs/ui/survey-b5): the Emergency button, its point on the A2 picture and the SLD crop;
    /// iPad portrait and iPhone keep `groupPage`.
    var cardFts: SurveyModule? {
        guard case .module(let id) = page, !compact, infoColumns == 2 else { return nil }
        return job.modules.first { $0.id == id && $0.type == .fts }
    }
    /// C1 roof on iPad (docs/ui/survey-c1): the roof plan, section A-A, members and photo angles; one screen side by side
    /// at 1100 pt and wider in landscape, else one scrolling column. iPhone keeps `groupPage`.
    var cardRoof: SurveyModule? {
        guard case .module(let id) = page, !compact else { return nil }
        return job.modules.first { $0.id == id && $0.type == .roof }
    }
    /// D1 tank on iPad landscape (docs/ui/survey-d1-size): the sub-step tab bar, the tank plan and its data; one column
    /// under 1100 pt. iPad portrait and iPhone keep `groupPage`.
    var cardTank: SurveyModule? {
        guard case .module(let id) = page, !compact, infoColumns == 2 else { return nil }
        return job.modules.first { $0.id == id && $0.type == .tank }
    }
    /// E1 on iPad landscape (docs/ui/survey-e1): verdict, remarks with suggestions, gaps elsewhere and both signatures on one
    /// screen; one column under 1100 pt. iPad portrait and iPhone keep `groupPage`.
    var cardFinal: Bool { page == .final && !compact && infoColumns == 2 }
    /// The B1 building shown with its old per-section form; cleared when the page changes.
    @State var panelForm: UUID?
    /// Pages with the blue header and bottom bar instead of the navigation bar.
    var cardPage: Bool { cardInfo || cardSite || cardElectrical || cardFlood || cardInverter != nil || cardPanels != nil || cardWater != nil || cardFts != nil || cardRoof != nil || cardTank != nil || cardFinal }
    var cardTitle: String {
        if cardFinal { return "E1 สรุปผลและลงนาม" }
        if let m = cardPanels { return m.type.code + " " + m.spec.label }
        if let m = cardRoof {
            return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "C1") + " " + m.spec.short + (m.name.isEmpty ? "" : " · " + m.name)
        }
        if let m = cardTank {
            return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "D1") + " " + m.spec.short + (m.name.isEmpty ? "" : " " + m.name)
        }
        if let m = cardFts { return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "B5") + " ปุ่ม Emergency" }
        if let m = cardWater { return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "B3") + " " + m.spec.label }
        if let m = cardInverter { return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "B2") + " " + m.spec.label }
        return cardFlood ? "A4 น้ำท่วม" : cardElectrical ? "A3 หม้อแปลง · MDB" : cardSite ? "A2 ภาพสถานที่ติดตั้ง" : "A1 ข้อมูลโครงการ"
    }
    /// A LIST item the A2 bottom bar's "ยังขาด" chip points to.
    @State var siteRequest: String?
    /// A transformer the A3 bottom bar's "ยังขาดภาพ" chip points to.
    @State var electricalRequest: Int?
    /// A breaker / board the single line diagram sent us to; A3 opens it.
    @State var electricalFocus: SLTarget?
    /// The single line diagram page (docs/ui/survey-sld), opened from A3.
    @State var showSLD = false
    /// Two columns on one screen in landscape; portrait stacks the same cards in one column.
    var infoColumns: Int {
        guard detailSize.width >= 860 else { return 1 }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "surveyWideA1") { return 2 }
        if UserDefaults.standard.bool(forKey: "surveyStacked") { return 1 }
        #endif
        return detailSize.width > detailSize.height ? 2 : 1
    }

    static let sidebarWidth: CGFloat = 310

    var body: some View {
        // The detail's size is the screen minus the sidebar, never the detail's own size: a page wider than the free
        // space would otherwise grow detailSize, which widens the page again (layout loop, clipped header and bar).
        GeometryReader { geo in
            let side: CGFloat = sidebarVisible && !compact ? Self.sidebarWidth + 1 : 0
            let free = CGSize(width: max(0, geo.size.width - side), height: geo.size.height)
            editorBody(free)
                .onAppear { detailSize = free }
                .onChange(of: free) { _, f in detailSize = f }
        }
        .navigationTitle(job.projectName.isEmpty ? "แบบสำรวจใหม่" : job.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // the card pages' blue header carries back, sidebar and export itself
        .toolbar(cardPage ? .hidden : .visible, for: .navigationBar)
        // the model owns the Drive link (uploads and other devices change it); this copy only mirrors it
        .onChange(of: job) { _, new in var j = new; j.drive = model.job(new.id)?.drive ?? new.drive; model.update(j) }
        // the Drive link changes elsewhere (export sheet, another device) — take it so the next edit doesn't drop it
        .onChange(of: model.job(job.id)?.drive) { _, d in if let d, d != job.drive { job.drive = d } }
        // photos taken on another iPad: fetch them from Drive now, and again when that iPad uploads more
        .task(id: model.job(job.id)?.drive?.photoFiles?.count ?? 0) { await model.fetchMissingPhotos(job.id) }
        // photos an earlier upload didn't finish, or taken before signing in to Google
        .onAppear { model.autoUploadPhotos(job.id, after: 2) }
        .onDisappear { model.flush(job.id) }
        .onChange(of: page) { _, _ in panelForm = nil }
        // opened from "continue": on iPhone show that form rather than the section list
        .onAppear { if startedOnPage && compact { sidebarVisible = false } }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "surveyDemoSection") { select(.info) } }
        // `-surveyPage site|electrical|sld|inverter|panels|flood|water|fts|roof|tank` opens that page
        .onAppear { openDebugPage() }
        // `-surveyWideA1 YES` shows A1's two-column (landscape) layout in any orientation, sidebar hidden (simulators can't be turned from the command line)
        .onAppear { if UserDefaults.standard.bool(forKey: "surveyWideA1") { sidebarVisible = false } }
        // `-surveyExport YES` opens the export sheet for simulator checks
        .task { if UserDefaults.standard.bool(forKey: "surveyExport") { try? await Task.sleep(nanoseconds: 600_000_000); showExport = true } }
        #endif
        .sheet(item: $preview) { p in PDFPreview(item: p) }
        .fullScreenCover(isPresented: $showSLD) {
            SingleLinePage(job: $job, open: { openFromDiagram($0) }, close: { showSLD = false })
                .environment(model)
        }
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

    #if DEBUG
    /// `-surveyPage site` opens A2, `electrical` A3, `sld` the single line diagram, `inverter` the first B2, `panels` the first B1, `flood` A4,
    /// `water` the first B3, `fts` the first B5, `roof` the first C1, `tank` the first D1, `final` E1.
    func openDebugPage() {
        let first: (ModuleType) -> Page? = { t in job.modules.first { $0.type == t }.map { .module($0.id) } }
        switch UserDefaults.standard.string(forKey: "surveyPage") {
        case "site": select(.site)
        case "electrical": select(.electrical)
        case "sld": select(.electrical); showSLD = true
        case "inverter": if let p = first(.inverter) { select(p) }
        case "panels": if let p = first(.panel) { select(p) }
        case "flood": select(.flood)
        case "water": if let p = first(.water) { select(p) }
        case "fts": if let p = first(.fts) { select(p) }
        case "roof":
            if let p = first(.roof) { select(p) }
            // `-surveyRoofRender YES` also writes C1 at free widths 980 / 1100 / 1318 to Documents/roof-<w>.png (no rotation here)
            if UserDefaults.standard.bool(forKey: "surveyRoofRender"), let m = job.modules.first(where: { $0.type == .roof }) { renderRoof(m.id) }
        case "final":
            select(.final)
            // `-surveyFinalRender YES` also writes E1 at free widths 1366 / 1180 to Documents/final-<w>x<h>.png
            if UserDefaults.standard.bool(forKey: "surveyFinalRender") { renderFinal() }
        case "tank":
            if let p = first(.tank) { select(p) }
            // `-surveyTankRender YES` also writes D1 at free widths 1366 / 1180 / 1100 to Documents/tank-<w>x<h>.png
            if UserDefaults.standard.bool(forKey: "surveyTankRender"), let m = job.modules.first(where: { $0.type == .tank }) { renderTank(m.id) }
        default: break
        }
    }
    #endif

    /// A2 fills the screen without scrolling; every other page scrolls.
    @ViewBuilder var detailArea: some View {
        if cardElectrical {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                ElectricalPageWide(job: $job, request: $electricalRequest, focus: $electricalFocus, openDiagram: { showSLD = true })
                    .disabled(readOnly)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1240 + 48 + 200, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if let m = cardPanels {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                PanelsPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1240 + 48) - 48, stacked: infoColumns != 2,
                               select: { id in withAnimation { page = id.map { .module($0) } ?? .info } },
                               openForm: { panelForm = m.id })
                    .disabled(readOnly)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1240 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if let m = cardInverter {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                InverterPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - 48, stacked: infoColumns != 2)
                    .disabled(readOnly)
                    .id(m.id)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if let m = cardWater {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                WaterPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - 48, openSite: { select(.site) },
                              stacked: infoColumns != 2)
                    .disabled(readOnly)
                    .id(m.id)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if let m = cardFts {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                FtsPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - 48,
                            openSite: { select(.site) }, openDiagram: { showSLD = true })
                    .disabled(readOnly)
                    .id(m.id)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if let m = cardRoof {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                RoofPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - 48,
                             stacked: infoColumns != 2 || detailSize.width < 1100)
                    .disabled(readOnly)
                    .id(m.id)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if let m = cardTank {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                TankPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - 48, stacked: detailSize.width < 1100)
                    .disabled(readOnly)
                    .id(m.id)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if cardFinal {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                FinalPageWide(job: $job, width: min(detailSize.width, 1240 + 48) - 48, stacked: detailSize.width < 1100,
                              open: { select(page(for: $0)) })
                    .disabled(readOnly)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1240 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if cardFlood {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                FloodPageWide(job: $job, width: min(detailSize.width, 1318 + 48) - 48, stacked: infoColumns != 2)
                    .disabled(readOnly)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else if cardSite {
            VStack(spacing: 12) {
                if readOnly { readOnlyBanner }
                SitePageWide(job: $job, width: min(detailSize.width, 1318 + 48) - 48, request: $siteRequest, stacked: infoColumns != 2)
                    .disabled(readOnly)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    if readOnly { readOnlyBanner.padding(.horizontal, 24).padding(.top, 16).frame(maxWidth: 1240 + 48) }
                    Group {
                        if cardInfo {
                            InfoPageWide(job: $job, width: min(detailSize.width, 1240 + 48) - (compact ? 32 : 48), twoColumns: infoColumns == 2)
                                .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16).frame(maxWidth: 1240 + 48)
                        } else {
                            detail.padding(compact ? 16 : 24).frame(maxWidth: 980)
                        }
                    }
                    // the summary only reads answers; everywhere else fields stay shown but can't be changed
                    .disabled(readOnly && page != .summary)
                    .frame(maxWidth: .infinity).id("top")
                }
                .onChange(of: page) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    #if DEBUG
    func renderRoof(_ id: UUID) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // free width × free height: 13" landscape ≈ 848 pt high, 11" ≈ 636; stacked ones are drawn unscrolled, taller
        for (free, h) in [(1366.0, 848.0), (1318.0, 848.0), (1100.0, 848.0), (1180.0, 636.0), (1100.0, 636.0), (980.0, 1500.0), (820.0, 1500.0)] {
            let w = min(free, 1318 + 48) - 48
            let page = RoofPageWide(job: .constant(job), moduleID: id, width: w, stacked: free < 1100, scrolls: false)
                .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                .frame(width: free, height: h).background(Paper.page)
            let r = ImageRenderer(content: page); r.scale = 1
            if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("roof-\(Int(free))x\(Int(h)).png")) }
        }
    }

    func renderFinal() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            for (free, h) in [(1366.0, 848.0), (1180.0, 636.0)] {
                let w = min(free, 1240 + 48) - 48
                let page = FinalPageWide(job: .constant(job), width: w, scrolls: false)
                    .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("final-\(Int(free))x\(Int(h)).png")) }
            }
        }
    }

    func renderTank(_ id: UUID) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        Task { @MainActor in
            // let `-surveyD1` seed the job first
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            for (free, h) in [(1366.0, 848.0), (1180.0, 636.0), (1100.0, 848.0)] {
                let w = min(free, 1318 + 48) - 48
                let page = TankPageWide(job: .constant(job), moduleID: id, width: w, stacked: free < 1100)
                    .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("tank-\(Int(free))x\(Int(h)).png")) }
            }
        }
    }
    #endif

    /// The sidebar and the detail; the detail gets exactly the free width and clips anything wider.
    func editorBody(_ free: CGSize) -> some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar.frame(width: compact ? nil : Self.sidebarWidth)
                if !compact { Divider() }
            }
            if !(compact && sidebarVisible) {
                detailArea
                    .background(Paper.page)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if cardPage {
                            InfoPageHeader(job: job, title: cardTitle, back: { dismiss() },
                                           toggleSidebar: { withAnimation { sidebarVisible.toggle() } },
                                           export: { model.flush(job.id); showExport = true },
                                           subtitleSuffix: cardFinal ? "หน้าสุดท้ายของรายงาน PDF" : nil)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { if cardPage { cardBar } }
                    .frame(width: free.width)
                    .clipped()
            }
        }
    }

    /// Bottom bar of the card pages; A2's lists the LIST items still unticked.
    @ViewBuilder var cardBar: some View {
        if cardFinal { finalBar } else { pageBar }
    }

    /// E1: the badge and status follow the whole job; the primary button runs the export flow with its gaps alert.
    var finalBar: some View {
        let steps = job.steps
        let before = steps.firstIndex { $0.page == .final }.flatMap { steps[safe: $0 - 1] }.map { page(for: $0.page) }
        let done = FinalSummary.isComplete(job)
        return InfoPageBar(job: job, here: .final, narrow: detailSize.width < 900, tight: detailSize.width < 720,
                           previous: before.map { p in { withAnimation { page = p } } }, next: nil,
                           statusText: FinalSummary.statusLine(job), statusAlert: !done, badgeComplete: done, statusOK: done,
                           finish: (sub: "ขั้นสุดท้าย", title: "สรุปผล · ส่งออก", action: { model.flush(job.id); checked { showExport = true } }))
    }

    var pageBar: some View {
        let go: (Page?) -> (() -> Void)? = { p in p.map { p in { withAnimation { page = p } } } }
        let station = cardInverter.map { InverterStation($0.values) }
        let module = cardInverter ?? cardPanels ?? cardWater ?? cardFts ?? cardRoof ?? cardTank
        let water: String? = cardWater.flatMap { WaterPoint.statusLine($0.values) } ?? cardFts.map { m in EmergencyButton.statusLine(job, m.values) }
            ?? cardRoof.map { Roof.statusLine($0.values) } ?? cardTank.flatMap { Tank.statusLine($0.values) }
        // C1: the six photo angles are a page warning only; completion is unchanged
        let roofMissing = cardRoof.map { !Roof.missingShots($0.values).isEmpty } ?? false
        // D1: the required photos still missing
        let tankMissing = cardTank.map { Tank.statusLine($0.values) != nil } ?? false
        // B5: a button height outside 1.10–1.50 m warns without blocking completion
        let ftsWarn = cardFts != nil && !EmergencyButton.isRecommended(EmergencyButton.heightCm(job))
        let ftsMissing = cardFts.map { m in EmergencyButton.photoMissing(m.values) } ?? false
        let here: MissingGroup.Target = module.map { .module($0.id) } ?? (cardFlood ? .flood : cardElectrical ? .electrical : cardSite ? .site : .info)
        // module pages step back to the section before them in the survey order; B1 shows every building, so it steps over them all
        let steps = job.steps
        let isPanel: (SurveyStep) -> Bool = { s in if case .module(let id) = s.page { return job.modules.first { $0.id == id }?.type == .panel }; return false }
        let first = cardPanels != nil ? steps.firstIndex(where: isPanel) : steps.firstIndex { $0.page == here }
        let last = cardPanels != nil ? steps.lastIndex(where: isPanel) : nil
        let before: Page? = module == nil ? nil : first.flatMap { steps[safe: $0 - 1] }.map { page(for: $0.page) }
        let after: Page? = last.map { steps[safe: $0 + 1].map { page(for: $0.page) } } ?? nextPage
        let panelsMissing = cardPanels != nil && !BuildingPanels.missing(job).isEmpty
        let gaps: [InfoPageBar.Gap] = cardElectrical ? ElectricalPageWide.gaps(job).map { g in InfoPageBar.Gap(title: g.title) { electricalRequest = g.index } }
            : cardSite ? SitePageWide.gaps(job).map { g in InfoPageBar.Gap(title: g.title) { siteRequest = g.item } } : []
        return InfoPageBar(job: job, here: here, narrow: detailSize.width < 900, tight: detailSize.width < 720,
                           previous: module != nil ? go(before) : cardFlood ? go(.electrical) : cardElectrical ? go(.site) : cardSite ? go(.info) : nil, next: go(after), gaps: gaps,
                           statusText: station?.status ?? water ?? (cardPanels != nil ? BuildingPanels.statusLine(job) : cardFlood ? FloodCheck.statusLine(job.floodCheck) : nil),
                           statusAlert: station.map { !$0.isOK } ?? (panelsMissing || (cardWater.map { WaterPoint.missingPhotos($0.values) > 0 } ?? false) ||
                                                                     ftsMissing || roofMissing || tankMissing || (cardFlood && job.floodCheck.fails > 0)),
                           statusWarn: ftsWarn,
                           previousIndex: cardPanels != nil ? first.map { $0 - 1 } : nil, nextIndex: cardPanels != nil ? last.map { $0 + 1 } : nil)
    }

    var readOnlyBanner: some View {
        Label("งานนี้ย้ายไปงานติดตั้งแล้ว · งดแก้ไข ดูและส่งออกได้อย่างเดียว", systemImage: "lock")
            .font(.subheadline.weight(.semibold)).foregroundStyle(Home.navy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Home.lockBadge, in: RoundedRectangle(cornerRadius: 10))
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

    /// A tap or link on the single line diagram: close it and open the page (and item) it points at.
    func openFromDiagram(_ t: SLTarget) {
        showSLD = false
        switch t.page {
        case .info: select(.info)
        case .flood: select(.flood)
        case .module(let type):
            if let m = job.modules.first(where: { $0.type == type }) { select(.module(m.id)) } else { select(.electrical) }
        case .electrical:
            select(.electrical)
            if t.trafo != nil {
                // the page must be on screen before it can open the item
                DispatchQueue.main.async { electricalFocus = t; electricalRequest = t.trafo }
            }
        }
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
        ModuleMarks.removeAll(&job, for: m)
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

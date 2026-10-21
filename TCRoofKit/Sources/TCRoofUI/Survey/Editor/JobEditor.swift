#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
import PDFReport
import DriveSync

/// Editor for one survey: sidebar of sections grouped like the workbook sheets, paper-style form on the right.
struct JobEditorView: View {
    enum Page: Hashable { case summary, info, site, electrical, flood, module(UUID), final, photos, revisions }

    @Environment(SurveyModel.self) var model
    @State var job: Job
    @State var page: Page = .info
    @State var preview: PDFPreviewItem?
    @State var showExport = false
    @State var showCardImport = false
    @State var busy: String?
    @State var error: String?
    @State var confirmDelete: SurveyModule?
    @State var sidebarVisible = true
    @State var collapsed: Set<SectionCategory> = []
    @State var pendingExport: PendingExport?
    struct PendingExport: Identifiable { let id = UUID(); let gaps: [String]; let target: MissingGroup.Target?; var photos = false; let go: () -> Void }
    // review
    @State var showIssueSheet = false
    @State var photoFilter = PhotoReviewPage.Filter.all
    /// The REV the comparison page starts from.
    @State var revisionCompare: String?
    /// The previous issued REV's answers, for the sidebar's change dots.
    @State var revisionBase: FormSnapshot?
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) var dismiss
    /// Issuing a REV (`survey.sign_rev`): the team, or the external engineer assigned to the job.
    @Environment(\.permissions) var permissions

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
    /// Visible height of the scrolling detail (inside the header and the bottom bar); A1 fills it in landscape.
    @State var scrollHeight: CGFloat = 0
    /// A1 in the card layout (docs/ui/survey-a1); one column on iPad portrait and iPhone.
    var cardInfo: Bool { page == .info }
    /// A2's picture page (docs/ui/survey-a2): side by side in landscape, one column on iPad portrait and iPhone.
    var cardSite: Bool { page == .site }
    /// A3's power-flow diagram (docs/ui/survey-a3) zooms and scrolls, so portrait iPad and iPhone use it too.
    var cardElectrical: Bool { page == .electrical }
    /// A4's flood page (docs/ui/survey-a4): side by side in landscape, one column on iPad portrait and iPhone.
    var cardFlood: Bool { page == .flood }
    /// B2 (docs/ui/survey-b2): the section being shown, side by side in landscape, one column on iPad portrait and iPhone.
    var cardInverter: SurveyModule? {
        guard case .module(let id) = page else { return nil }
        return job.modules.first { $0.id == id && $0.type == .inverter }
    }
    /// B1 (docs/ui/survey-b1): every building on one page, side by side in landscape, one column on iPad portrait and
    /// iPhone; a building whose old form was asked for keeps `groupPage`.
    var cardPanels: SurveyModule? {
        guard case .module(let id) = page, panelForm != id else { return nil }
        return job.modules.first { $0.id == id && $0.type == .panel }
    }
    /// B3 (docs/ui/survey-b3): the water point on the A2 picture, the mode, photos and details; one screen in
    /// landscape, one scrolling column on iPad portrait and iPhone.
    var cardWater: SurveyModule? {
        guard case .module(let id) = page else { return nil }
        return job.modules.first { $0.id == id && $0.type == .water }
    }
    /// B4 (docs/ui/survey-b4): the level, four photos, the SLD crop, the A2 crop and the equipment list; side by side on
    /// iPad landscape, one scrolling column on iPad portrait and iPhone.
    var cardBackfeed: SurveyModule? {
        guard case .module(let id) = page else { return nil }
        return job.modules.first { $0.id == id && $0.type == .backfeed }
    }
    /// B5 (docs/ui/survey-b5): the Emergency button, its point on the A2 picture and the SLD crop; side by side in
    /// landscape, one scrolling column on iPad portrait and iPhone.
    var cardFts: SurveyModule? {
        guard case .module(let id) = page else { return nil }
        return job.modules.first { $0.id == id && $0.type == .fts }
    }
    /// C1 roof on iPad (docs/ui/survey-c1): the roof plan, section A-A, members and photo angles; one screen side by side
    /// at 1100 pt and wider in landscape, else one scrolling column (iPad portrait and iPhone).
    var cardRoof: SurveyModule? {
        guard case .module(let id) = page else { return nil }
        return job.modules.first { $0.id == id && $0.type == .roof }
    }
    /// D1 tank (docs/ui/survey-d1-size): the sub-step tab bar, the tank plan and its data; side by side in landscape at
    /// 1100 pt and wider, else one column (iPad portrait and iPhone too).
    var cardTank: SurveyModule? {
        guard case .module(let id) = page else { return nil }
        return job.modules.first { $0.id == id && $0.type == .tank }
    }
    /// E1 (docs/ui/survey-e1): verdict, remarks with suggestions, gaps elsewhere and both signatures on one screen in
    /// landscape at 1100 pt and wider; else one column (iPad portrait and iPhone too).
    var cardFinal: Bool { page == .final }
    /// The B1 building shown with its old per-section form; cleared when the page changes.
    @State var panelForm: UUID?
    /// Pages with the blue header and bottom bar instead of the navigation bar.
    var cardPage: Bool { cardInfo || cardSite || cardElectrical || cardFlood || cardInverter != nil || cardPanels != nil || cardWater != nil || cardBackfeed != nil || cardFts != nil || cardRoof != nil || cardTank != nil || cardFinal }
    var cardTitle: String {
        if cardFinal { return "E1 สรุปผลและลงนาม" }
        if let m = cardPanels { return m.type.code + " " + m.spec.label }
        if let m = cardRoof {
            return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "C1") + " " + m.spec.short + (m.name.isEmpty ? "" : " | " + m.name)
        }
        if let m = cardTank {
            return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "D1") + " " + m.spec.short + (m.name.isEmpty ? "" : " " + m.name)
        }
        if let m = cardBackfeed { return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "B4") + " " + m.spec.label }
        if let m = cardFts { return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "B5") + " ปุ่ม Emergency" }
        if let m = cardWater { return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "B3") + " " + m.spec.label }
        if let m = cardInverter { return (job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "B2") + " " + m.spec.label }
        return cardFlood ? "A4 น้ำท่วม" : cardElectrical ? "A3 หม้อแปลง | MDB" : cardSite ? "A2 ภาพสถานที่ติดตั้ง" : "A1 ข้อมูลโครงการ"
    }
    /// A LIST item the A2 bottom bar's "ยังขาด" chip points to.
    @State var siteRequest: String?
    /// A C1 gap (`Roof.Gap.key`) the bottom bar's status line points to.
    @State var roofRequest: String?
    /// D1's sub-step (1 ขนาดถัง … 4 ภาพถ่าย); the iPhone bar's ‹ › step through it before leaving the page.
    @State var tankTab = 1
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

    /// DEBUG `-surveyWideA1 YES`: the two-column D1 too, below its 1100 pt (the simulator can't be turned).
    var debugWide: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "surveyWideA1")
        #else
        return false
        #endif
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
        // heat, low space or low battery (hardware assist §H8); nothing when all is well
        .safeAreaInset(edge: .top, spacing: 0) { PowerBanner() }
        .navigationTitle(job.projectName.isEmpty ? "แบบสำรวจใหม่" : job.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // the card pages' blue header carries back, sidebar and export itself
        .toolbar(cardPage ? .hidden : .visible, for: .navigationBar)
        // the model owns the Drive link (uploads and other devices change it); this copy only mirrors it
        .onChange(of: job) { old, new in jobChanged(old, new) }
        // the Drive link changes elsewhere (export sheet, another device) — take it so the next edit doesn't drop it
        .onChange(of: model.job(job.id)?.drive) { _, d in if let d, d != job.drive { job.drive = d } }
        // photos taken on another iPad: fetch them from Drive now, and again when that iPad uploads more
        .task(id: model.job(job.id)?.drive?.photoFiles?.count ?? 0) { await model.fetchMissingPhotos(job.id) }
        // photos an earlier upload didn't finish, or taken before signing in to Google
        .onAppear { model.autoUploadPhotos(job.id, after: 2) }
        .onDisappear { model.flush(job.id) }
        .onChange(of: page) { _, _ in panelForm = nil; tankTab = 1 }
        // opened from "continue": on iPhone show that form rather than the section list
        .onAppear { if startedOnPage && compact { sidebarVisible = false } }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "surveyDemoSection") { select(.info) } }
        // `-surveyPage site|electrical|sld|inverter|panels|flood|water|backfeed|fts|roof|tank` opens that page
        .onAppear { openDebugPage() }
        // `-surveyWideA1 YES` shows A1's two-column (landscape) layout in any orientation, sidebar hidden (simulators can't be turned from the command line)
        .onAppear { if UserDefaults.standard.bool(forKey: "surveyWideA1") { sidebarVisible = false } }
        // `-surveyExport YES` opens the export sheet for simulator checks
        .task { if UserDefaults.standard.bool(forKey: "surveyExport") { try? await Task.sleep(nanoseconds: 600_000_000); showExport = true } }
        // `-surveyCardImport YES` opens นำเข้ารูปจากการ์ด / USB with three sample photos
        .task { if UserDefaults.standard.bool(forKey: "surveyCardImport") { try? await Task.sleep(nanoseconds: 600_000_000); showCardImport = true } }
        #endif
        .sheet(item: $preview) { p in PDFPreview(item: p) }
        .sheet(isPresented: $showCardImport) { CardImportSheet(job: $job).environment(model) }
        .fullScreenCover(isPresented: $showSLD) {
            SingleLinePage(job: $job, open: { openFromDiagram($0) }, close: { showSLD = false })
                .environment(model)
        }
        // a Drive save stores the folder link on the model's copy — take it back so the next edit keeps it
        .sheet(isPresented: $showExport, onDismiss: { if let d = model.job(job.id)?.drive { job.drive = d } }) {
            ExportSheet(jobID: job.id) { select(page(for: $0)) }.environment(model)
        }
        // the previous issued REV, for the change dots
        .task(id: "\(job.previousRevision?.rev ?? "")|\(model.revisionArrivals)") { loadRevisionBase() }
        .sheet(isPresented: $showIssueSheet) {
            IssueRevisionSheet(job: job, changes: job.lastRevision == nil ? nil : changedPages.values.reduce(0, +)) { issueRevision($0) }
        }
        .overlay { if let busy { BusyOverlay(text: busy) } }
        .errorAlert($error)
        .alert("ข้อมูลยังไม่ครบ", isPresented: Binding(get: { pendingExport != nil }, set: { if !$0 { pendingExport = nil } }), presenting: pendingExport) { p in
            if p.photos { Button("ไปตรวจรูป") { pendingExport = nil; photoFilter = .missing; select(.photos) } }
            if let t = p.target { Button("ไปกรอกให้ครบ") { pendingExport = nil; select(page(for: t)) } }
            Button("ส่งออกต่อ") { let go = p.go; pendingExport = nil; go() }
            Button("ยกเลิก", role: .cancel) { pendingExport = nil }
        } message: { p in Text(p.gaps.joined(separator: "\n")) }
        .confirmationDialog("ลบหัวข้อนี้?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { m in
            Button("ลบ \(m.title)", role: .destructive) { remove(m) }
        } message: { _ in Text("ข้อมูลและรูปภาพในหัวข้อนี้จะถูกลบ") }
    }

    /// A2 fills the screen without scrolling; every other page scrolls.
    @ViewBuilder var detailArea: some View {
        if cardElectrical {
            AnyView(VStack(spacing: 12) {
                ElectricalPageWide(job: $job, request: $electricalRequest, focus: $electricalFocus, openDiagram: { showSLD = true },
                                   narrow: compact)
            }
            // iPhone: the page pads and scrolls itself
            .padding(.horizontal, compact ? 0 : 24).padding(.vertical, compact ? 0 : 16)
            .frame(maxWidth: 1240 + 48 + 200, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if let m = cardPanels {
            AnyView(VStack(spacing: 12) {
                PanelsPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1240 + 48) - (compact ? 32 : 48),
                               stacked: compact || infoColumns != 2,
                               select: { id in withAnimation { page = id.map { .module($0) } ?? .info } },
                               openForm: { panelForm = m.id })
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1240 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if let m = cardInverter {
            AnyView(VStack(spacing: 12) {
                InverterPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - (compact ? 32 : 48),
                                 stacked: compact || infoColumns != 2)
                    .id(m.id)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if let m = cardWater {
            AnyView(VStack(spacing: 12) {
                WaterPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - (compact ? 32 : 48), openSite: { select(.site) },
                              stacked: compact || infoColumns != 2)
                    .id(m.id)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if let m = cardBackfeed {
            AnyView(VStack(spacing: 12) {
                BackfeedPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - (compact ? 32 : 48),
                                 openSite: { select(.site) }, openDiagram: { showSLD = true }, stacked: compact || infoColumns != 2)
                    .id(m.id)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, compact || infoColumns != 2 ? 0 : 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if let m = cardFts {
            AnyView(VStack(spacing: 12) {
                FtsPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - (compact ? 32 : 48),
                            openSite: { select(.site) }, openDiagram: { showSLD = true }, stacked: compact || infoColumns != 2)
                    .id(m.id)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if let m = cardRoof {
            AnyView(VStack(spacing: 12) {
                RoofPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - (compact ? 32 : 48),
                             stacked: compact || infoColumns != 2 || detailSize.width < 1100, request: $roofRequest)
                    .id(m.id)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if let m = cardTank {
            AnyView(VStack(spacing: 12) {
                TankPageWide(job: $job, moduleID: m.id, width: min(detailSize.width, 1318 + 48) - (compact ? 32 : 48),
                             stacked: compact || infoColumns != 2 || (detailSize.width < 1100 && !debugWide), tab: $tankTab)
                    .id(m.id)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if cardFinal {
            AnyView(VStack(spacing: 12) {
                finalBanners
                FinalPageWide(job: $job, width: min(detailSize.width, 1240 + 48) - (compact ? 32 : 48),
                              stacked: compact || infoColumns != 2 || detailSize.width < 1100,
                              open: { select(page(for: $0)) })
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1240 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if cardFlood {
            AnyView(VStack(spacing: 12) {
                FloodPageWide(job: $job, width: min(detailSize.width, 1318 + 48) - (compact ? 32 : 48), stacked: compact || infoColumns != 2)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if cardSite {
            AnyView(VStack(spacing: 12) {
                SitePageWide(job: $job, width: min(detailSize.width, 1318 + 48) - (compact ? 0 : 48), request: $siteRequest,
                             stacked: compact || infoColumns != 2)
            }
            // iPhone: the bands run edge to edge
            .padding(.horizontal, compact ? 0 : 24).padding(.vertical, compact ? 0 : 16)
            .frame(maxWidth: 1318 + 48, maxHeight: .infinity)
            .frame(maxWidth: .infinity))
        } else if page == .photos || page == .revisions {
            AnyView(reviewDetail.frame(maxWidth: .infinity, maxHeight: .infinity))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if cardInfo {
                            // iPhone: the bands run edge to edge
                            // landscape: the cards fill the visible height (less the 16-pt padding above and below)
                            AnyView(InfoPageWide(job: $job, width: min(detailSize.width, 1240 + 48) - (compact ? 0 : 48), twoColumns: infoColumns == 2,
                                         fillHeight: compact ? 0 : max(0, scrollHeight - 32))
                                .padding(.horizontal, compact ? 0 : 24).padding(.vertical, compact ? 0 : 16).frame(maxWidth: 1240 + 48))
                        } else {
                            AnyView(detail.padding(compact ? 16 : 24).frame(maxWidth: 980))
                        }
                    }
                    .frame(maxWidth: .infinity).id("top")
                }
                .onChange(of: page) { _, _ in proxy.scrollTo("top", anchor: .top) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height - $0.safeAreaInsets.top - $0.safeAreaInsets.bottom } action: { scrollHeight = $0 }
                #if DEBUG
                // `-surveyScrollEnd YES`: open scrolled to the end (the simulator can't be swiped here)
                .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "surveyScrollEnd") ? .bottom : .top)
                #endif
            }
        }
    }

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
                           statusText: FinalSummary.statusLine(job), statusAlert: !done, statusOK: done,
                           finish: (sub: "ขั้นสุดท้าย", title: "สรุปผล | ส่งออก", action: { model.flush(job.id); checked { showExport = true } }))
    }

    var pageBar: some View {
        let go: (Page?) -> (() -> Void)? = { p in p.map { p in { withAnimation { page = p } } } }
        let station = cardInverter.map { InverterStation($0.values) }
        let module = cardInverter ?? cardPanels ?? cardWater ?? cardBackfeed ?? cardFts ?? cardRoof ?? cardTank
        let water: String? = cardWater.flatMap { WaterPoint.statusLine($0.values) } ?? cardBackfeed.map { ZeroExport.statusLine($0.values) }
            ?? cardFts.map { m in EmergencyButton.statusLine(job, m.values) }
            ?? cardRoof.map { Roof.statusLine($0.values) } ?? cardTank.flatMap { Tank.statusLine($0.values) }
        // C1: the missing fields and photo angles; tapping the line opens the first
        let roofGaps = cardRoof.map { Roof.gaps($0.values) } ?? []
        let roofMissing = !roofGaps.isEmpty
        // D1: the required photos still missing
        let tankMissing = cardTank.map { Tank.statusLine($0.values) != nil } ?? false
        // B5: a button height outside 1.10–1.50 m warns without blocking completion
        let ftsWarn = cardFts != nil && !EmergencyButton.isRecommended(EmergencyButton.heightCm(job))
        // B4: fewer than four photos, or the level / pole still to choose
        let backfeedMissing = cardBackfeed.map { !ZeroExport.isComplete($0.values) } ?? false
        let ftsMissing = cardFts.map { m in EmergencyButton.photoMissing(m.values) } ?? false
        let here: MissingGroup.Target = module.map { .module($0.id) } ?? (cardFlood ? .flood : cardElectrical ? .electrical : cardSite ? .site : .info)
        // module pages step back to the section before them in the survey order; B1 shows every building, so it steps over them all
        let steps = job.steps
        let isPanel: (SurveyStep) -> Bool = { s in if case .module(let id) = s.page { return job.modules.first { $0.id == id }?.type == .panel }; return false }
        let first = cardPanels != nil ? steps.firstIndex(where: isPanel) : steps.firstIndex { $0.page == here }
        let last = cardPanels != nil ? steps.lastIndex(where: isPanel) : nil
        let before: Page? = module == nil ? nil : first.flatMap { steps[safe: $0 - 1] }.map { page(for: $0.page) }
        let after: Page? = last.map { steps[safe: $0 + 1].map { page(for: $0.page) } } ?? nextPage
        let status = cardElectrical ? electricalStatus : cardSite ? siteStatus : cardPanels.map(panelsStatus)
        let sub = tankSubSteps
        return InfoPageBar(job: job, here: here, narrow: detailSize.width < 900, tight: detailSize.width < 720,
                           previous: sub?.previous ?? (module != nil ? go(before) : cardFlood ? go(.electrical) : cardElectrical ? go(.site) : cardSite ? go(.info) : nil),
                           next: sub?.next ?? go(after), status: status,
                           statusText: station?.status ?? water ?? (cardFlood ? FloodCheck.statusLine(job.floodCheck) : nil),
                           statusAlert: station.map { !$0.isOK } ?? ((cardWater.map { WaterPoint.missingPhotos($0.values) > 0 } ?? false) ||
                                                                     backfeedMissing || ftsMissing || roofMissing || tankMissing || (cardFlood && job.floodCheck.fails > 0)),
                           statusWarn: ftsWarn,
                           previousIndex: cardPanels != nil ? first.map { $0 - 1 } : nil, nextIndex: cardPanels != nil ? last.map { $0 + 1 } : nil,
                           statusOK: cardRoof != nil && roofGaps.isEmpty,
                           statusAction: roofGaps.first.map { g in { roofRequest = g.key } },
                           previousLabel: sub?.previousLabel, nextLabel: sub?.nextLabel)
    }

    /// A3: the photos still missing per transformer / board; tapping opens the first. nil: the page's field count.
    var electricalStatus: TCBarStatus? {
        let gaps = ElectricalPageWide.gaps(job)
        guard let first = gaps.first else { return nil }
        return .missing("ยังขาดภาพ: " + gaps.map(\.title).joined(separator: " | ") + " | ไปต่อได้ แล้วค่อยกลับมาเติม",
                        action: { electricalRequest = first.index })
    }

    /// A2: the LIST items not ticked yet, in a green chip once the required fields are done; tapping opens the first.
    var siteStatus: TCBarStatus? {
        let gaps = SitePageWide.gaps(job)
        guard let first = gaps.first else { return nil }
        let c = job.steps.first { $0.page == .site }?.completion ?? Completion()
        let list = gaps.map(\.title).joined(separator: ", ")
        let go = { siteRequest = first.item }
        let label = "ยังไม่มี (ไม่บังคับ) \(gaps.count) รายการ: \(list) | แตะเพื่อไปที่รายการ"
        return c.isComplete
            ? .okChip(title: "ครบช่องบังคับแล้ว", sub: "ยังไม่มี (ไม่บังคับ): ", emphasis: list, label: "ครบช่องบังคับแล้ว | " + label, action: go)
            : .gapChip(title: "ครบ \(c.filled)/\(c.total) ช่องในหน้านี้", sub: "ยังไม่มี (ไม่บังคับ): ", emphasis: list,
                       label: "ครบ \(c.filled)/\(c.total) ช่อง | " + label, action: go)
    }

    /// B1: the gaps of every building; tapping opens the first building with gaps, starting from this one.
    func panelsStatus(_ m: SurveyModule) -> TCBarStatus {
        let panels = job.modules.filter { $0.type == .panel }
        let missing = panels.map { BuildingPanels.missingItems($0.values) }
        let total = missing.reduce(0) { $0 + $1.count }
        let at = panels.firstIndex { $0.id == m.id } ?? 0
        guard total > 0, let nx = panels.indices.map({ (at + $0) % panels.count }).first(where: { !missing[$0].isEmpty }) else {
            return .allDone("ครบทุกอาคารแล้ว")
        }
        let name = BuildingPanels.name(panels[nx], in: job), id = panels[nx].id
        return .gapChip(title: "ยังขาด \(total) รายการ ใน \(missing.filter { !$0.isEmpty }.count) อาคาร",
                        sub: (nx == at ? "อาคารนี้: " : "ถัดไป \(name): ") + missing[nx].joined(separator: ", "),
                        label: "ไปยังรายการที่ขาด " + (nx == at ? "ในอาคารนี้" : "ที่ " + name),
                        action: { withAnimation { page = .module(id) } })
    }

    /// iPhone D1: ‹ › move between the four sub-steps first ("ถัดไป D1 2/4 สิ่งกีดขวาง"), then to the pages either side.
    var tankSubSteps: (previous: (() -> Void)?, previousLabel: String?, next: (() -> Void)?, nextLabel: String?)? {
        guard compact, let m = cardTank else { return nil }
        let code = job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "D1"
        let names = TankPageWide.phoneTitles, t = tankTab
        let label: (Int) -> String = { n in "\(code) \(n)/\(names.count) \(names[n - 1])" }
        return (t > 1 ? { withAnimation { tankTab = t - 1 } } : nil, t > 1 ? "ก่อนหน้า " + label(t - 1) : nil,
                t < names.count ? { withAnimation { tankTab = t + 1 } } : nil, t < names.count ? "ถัดไป " + label(t + 1) : nil)
    }

}

extension Job {
    /// Adds a section after the last one of the same sheet so the order follows the workbook.
    mutating func insertModule(_ m: SurveyModule) {
        if let last = modules.lastIndex(where: { $0.spec.sheet == m.spec.sheet }) { modules.insert(m, at: last + 1) } else { modules.append(m) }
    }
}
#endif

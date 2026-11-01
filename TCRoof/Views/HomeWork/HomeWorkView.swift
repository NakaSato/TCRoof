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

    @State var home = HomeJob()
    @State private var loaded = false
    @State private var openStage: HomeStage?
    @State var showWeight = false
    @State private var showPack = false
    @State var showEntry = false
    @State private var showArchive = false
    @State var library = HomeLibrary()
    /// nil = open while the sizes or the phase are missing.
    @State var setupOpen: Bool?
    /// Finished stages the team opened again.
    @State var openStages: Set<HomeStage> = []
    @State private var scrollTarget: String?
    /// iPhone: which part of the job the screen shows; iPad shows every part.
    @State private var tab: HomeTab = .overview
    static let file = "home"

    /// iPhone menu bar of the job: ภาพรวม | สำรวจ | ติดตั้ง | เอกสาร.
    enum HomeTab: CaseIterable {
        case overview, survey, install, docs

        var title: String {
            switch self {
            case .overview: "ภาพรวม"
            case .survey: "สำรวจ"
            case .install: "ติดตั้ง"
            case .docs: "เอกสาร"
            }
        }

        var icon: String {
            switch self {
            case .overview: "house"
            case .survey: "list.clipboard"
            case .install: "hammer"
            case .docs: "doc.text"
            }
        }

        /// Stages whose documents the tab lists. Permits (design to handover) sit under เอกสาร with the PEA steps.
        var stages: [HomeStage] {
            switch self {
            case .overview: []
            case .survey: [.survey]
            case .install: [.install]
            case .docs: [.design, .apply, .connect, .handover]
            }
        }

        static func of(_ stage: HomeStage) -> HomeTab { allCases.first { $0.stages.contains(stage) } ?? .docs }
    }

    var store: PermitStore { PermitStore(job: job) }

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "งานบ้าน", trail: ["หน้าหลัก", job.code], current: "งานบ้าน ครบวงจร") {
                if home.residentialConfirmed { navActions }
            }
            ScrollViewReader { proxy in
                ScrollView { content }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                    .onChange(of: tab) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if isPhone && home.residentialConfirmed { tabBar }
                    }
            }
        }
        .tcPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { load() }
        #if DEBUG
        // `-homeworkSheet weight|pack|entry|archive` opens that sheet for simulator checks
        .task {
            guard let sheet = UserDefaults.standard.string(forKey: "homeworkSheet") else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            switch sheet {
            case "weight": showWeight = true
            case "pack": showPack = true
            case "entry": showEntry = true
            case "archive": showArchive = true
            default: break
            }
        }
        #endif
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
        .sheet(isPresented: $showArchive) { HomeArchiveView(job: job) }
    }

    /// Library and PPIM pack; icons only on iPhone so the bar keeps its title.
    @ViewBuilder private var navActions: some View {
        NavigationLink { HomeLibraryView() } label: { navLabel("คลังเอกสาร", "books.vertical") }
            .buttonStyle(.plain)
            .accessibilityLabel("คลังเอกสาร")
        Button { showPack = true } label: { navLabel("ชุดไฟล์ PPIM", "tray.and.arrow.up") }
            .buttonStyle(.plain)
            .accessibilityLabel("ชุดไฟล์ PPIM")
        Button { showArchive = true } label: { navLabel("แฟ้มเอกสาร (\(job.documents.count))", "folder") }
            .buttonStyle(.plain)
            .accessibilityLabel("แฟ้มเอกสาร \(job.documents.count) ไฟล์")
    }

    private func navLabel(_ title: String, _ icon: String) -> some View {
        Group {
            if isPhone {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(width: touchMin, height: touchMin)
            } else {
                Label(title, systemImage: icon).font(.sarabun(14, .semibold, relativeTo: .body))
                    .padding(.horizontal, Space.m).frame(minHeight: touchMin)
            }
        }
        .foregroundStyle(Theme.navy)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Color.clear.frame(height: 0).id("top")
            if home.residentialConfirmed {
                if !isPhone || tab == .overview {
                    nextCard
                    setupSection.id("setup")
                    if home.mode == .sell { HomeSellCard(home: $home).id("sell") }
                    stageStrip
                }
                if !isPhone || tab == .docs { HomePermitCard(home: home).id("permit") }
                ForEach(isPhone ? tab.stages : HomeStage.allCases, id: \.self) { stageCard($0) }
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
            "workOrder": home.site.workOrder.accepted != nil,
            "delivery": home.site.delivery.isComplete,
            "contractorAccept": home.site.accepted != nil,
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
                      subtitle: "โมดูลนี้ใช้กับผู้ใช้ไฟประเภท 1 (บ้านอยู่อาศัย) ในพื้นที่ PEA | โรงงาน อาคารพาณิชย์ และงาน กปภ. ใช้โมดูลอื่น") {
            PermitField("Rate code บนบิลค่าไฟ (เลข 4 หลัก)", text: $home.caRateCode, required: true, keyboard: .numberPad,
                        error: home.rateCodeIsResidential == false ? "ขึ้นต้นด้วย \(home.caRateCode.prefix(1)) — ไม่ใช่บ้านอยู่อาศัย ใช้โมดูลนี้ไม่ได้" : nil)
            Text("หลักแรก 1 = บ้านอยู่อาศัย | หลักที่ 4 = 5 คือแรงดันต่ำกว่า 400 V | กรุงเทพฯ นนทบุรี สมุทรปราการ เป็นพื้นที่ MEA ใช้ขั้นตอนอื่น")
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
        let target: String
        if let doc = a.docID {
            if let stage = HomeCatalog.spec(doc)?.stage {
                openStages.insert(stage)
                tab = HomeTab.of(stage)
            }
            target = doc
        } else if a.kind == .issue {
            setupOpen = true
            tab = .overview
            target = "setup"
        } else {
            tab = .overview
            target = home.mode == .sell ? "sell" : "setup"
        }
        // after the tab's rows are on screen
        Task { @MainActor in scrollTarget = target }
    }

    // MARK: iPhone menu bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases, id: \.self) { t in
                let on = tab == t
                let left = missingCount(t)
                Button { tab = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.icon).font(.system(size: 19, weight: on ? .semibold : .regular))
                            .frame(width: 52, height: 28)
                            .background(on ? Theme.primarySoft : Color.clear, in: Capsule())
                            .overlay(alignment: .topTrailing) {
                                if left > 0 {
                                    Text("\(left)").font(.sarabun(10, .heavy, relativeTo: .caption2)).foregroundStyle(Color.white)
                                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                                        .background(Theme.danger, in: Capsule())
                                        .offset(x: 2, y: -4)
                                }
                            }
                        Text(t.title).font(.sarabun(11, on ? .bold : .semibold, relativeTo: .caption2))
                    }
                    .foregroundStyle(on ? Theme.primary : Theme.inkTab)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(left > 0 ? "\(t.title) ยังขาด \(left) รายการ" : t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderOutdoor).frame(height: 1) }
    }

    /// Required documents still missing in the tab's stages.
    private func missingCount(_ t: HomeTab) -> Int {
        t.stages.reduce(0) { $0 + home.missing(in: $1).count }
    }
}

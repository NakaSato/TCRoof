import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `เอกสาร PWA` on iPhone (docs/ui/pwa-docs-iphone-v2): every PWA station's papers at once. The header with its
/// growing search and the bell, the view switch (`ตามสถานี`, `ต้องทำ`, `คลังกลาง`), then the summary, the nearest
/// expiring library paper and the selected view. The numbers come from `PWADocs` over `StationDocs`; a station
/// card pushes `StationDocsScreen`, a paper opens its sheet. The main dock's `เอกสาร` tab is its root.
struct PWADocsHomeView: View {
    let isActive: Bool
    @State private var overviewCache = PWADocsOverviewCache()

    init(isActive: Bool = true) { self.isActive = isActive }

    enum Pane: String, CaseIterable { case st, todo, lib }

    /// A paper a row opens: a station's, or a library paper (on any job, since the sheet keeps it in the library).
    struct Paper: Identifiable {
        let job: Job
        let kind: StationDocs.Kind
        var id: String { "\(job.persistentModelID.hashValue)/\(kind.id)" }
    }

    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State var pane = Debug.pane
    @State var filter = Debug.filter
    @State var search = ""
    @State private var searchOpen = Debug.searchOpen
    @State var library = StationDocsStore.loadLibrary()
    @State var station: Job?
    @State var paper: Paper?
    @State private var showNotifications = false
    private var bell = PWABell()
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// The PWA stations, the installing ones first.
    private var stationJobs: [Job] {
        let all = jobs.pwaStations, installing = jobs.pwaInstalling
        // a contractor's, only those assigned to them
        return (installing + all.filter { !installing.contains($0) }).filter { permissions.canView(.stationDocsDrafts, on: $0.access) }
    }

    var today: Date { .now }

    /// The station's papers and the ERC flow are the team's (`stationdocs.drafts`, `erc.flow_record`).
    @Environment(\.permissions) private var permissions

    /// A contractor: their stations only, no library, read only (as `PWADocsPadView.readOnly`).
    private var readOnly: Bool { !permissions.can(.stationDocsDrafts) }

    var body: some View {
        if permissions.canView(.stationDocsDrafts) {
            content
        } else {
            TCEmptyState("เอกสารสำหรับทีมภายใน", systemImage: "lock.doc",
                         description: Text("เอกสาร PWA ร่างและยื่นโดยทีมภายใน"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.pageGradient.ignoresSafeArea())
        }
    }

    private var content: some View {
        let data = self.data
        return VStack(spacing: 0) {
            paneSwitch(data)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    summaryCard(data.summary)
                    if let row = data.expiring { expiryBanner(row) }
                    paneBody(data)
                }
                // 20 pt clear of the dock, which is the stack's bottom safe-area inset
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TCPhoneSearchHeader(title: "เอกสาร PWA", subtitle: nil, search: $search, isOpen: $searchOpen,
                                large: true,
                                bell: .init(unread: bell.unread) { showNotifications = true })
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $station) { StationDocsScreen(job: $0).toolbar(.visible, for: .navigationBar) }
        .sheet(item: $paper, onDismiss: { library = StationDocsStore.loadLibrary() }) { p in
            StationDocSheet(job: p.job, kind: p.kind, library: $library)
        }
        .fullScreenCover(isPresented: $showNotifications) { bell.view().environment(\.homeInk, .outdoor) }
        .onAppear { library = StationDocsStore.loadLibrary() }
    }

    /// The selected view, type-erased: the page's view type is otherwise deep enough to crash a Debug build
    /// (CLAUDE.md, the `View.modifier` SIGSEGV).
    private func paneBody(_ data: Data) -> AnyView {
        switch pane {
        case .st: AnyView(stations(data.rows))
        case .todo: AnyView(todo(data.groups))
        case .lib: readOnly ? AnyView(stations(data.rows)) : AnyView(libraryList(data.library))
        }
    }

    // MARK: data

    /// Everything the page shows, worked out once per render.
    struct Data {
        var summary: PWADocs.Summary
        /// Every station row, unfiltered by search: the filter's counts.
        var allRows: [PWADocs.StationRow]
        var rows: [PWADocs.StationRow]
        var groups: [PWADocs.Group]
        var library: [PWADocs.LibraryRow]
        /// The banner's paper, whatever the search.
        var expiring: PWADocs.LibraryRow?
        /// Open papers ours to move: the switch's red `ต้องทำ n`.
        var ours: Int
    }

    private var data: Data {
        let snapshot: PWADocsOverviewCache.Result
        if isActive {
            let (stations, library) = source
            snapshot = overviewCache.result(stations: stations, library: library, today: today)
        } else {
            snapshot = overviewCache.cached
            return Data(summary: snapshot.summary, allRows: snapshot.rows, rows: snapshot.rows, groups: snapshot.groups,
                        library: snapshot.libraryRows, expiring: snapshot.expiring, ours: snapshot.ours)
        }
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Data(summary: snapshot.summary, allRows: snapshot.rows, rows: snapshot.rows, groups: snapshot.groups,
                        library: snapshot.libraryRows, expiring: snapshot.expiring, ours: snapshot.ours)
        }
        let rows = snapshot.rows, groups = snapshot.groups, lib = snapshot.libraryRows
        let q = search
        return Data(summary: snapshot.summary, allRows: rows,
                    rows: rows.filter { PWADocs.matches($0, search: q) },
                    groups: groups.map { g in
                        var g = g
                        g.items = g.items.filter { PWADocs.matches($0, search: q) }
                        return g
                    },
                    library: lib.filter { PWADocs.matches($0, search: q) }, expiring: snapshot.expiring,
                    ours: snapshot.ours)
    }

    /// The PWA jobs and the device library, or the board's example with `-pwaDocsDemo YES`.
    private var source: ([PWAPlan.Station], StationDocs.Library) {
        #if DEBUG
        if Debug.demo { return (PWADocsDemo.stations(today: today), PWADocsDemo.library(today: today)) }
        #endif
        return (stationJobs.map(\.planStation), readOnly ? StationDocs.Library() : library)
    }

    // MARK: navigation

    /// The job behind a row. The example stations are matched by MP number, so most of them open nothing.
    func job(_ station: PWAPlan.Station) -> Job? {
        stationJobs.first { $0.overviewID == station.id } ?? stationJobs.first { j in j.mpNumber.map { "demo-\($0)" } == station.id }
    }

    func open(_ kind: StationDocs.Kind, station: PWAPlan.Station?) {
        // a library paper is kept in the library whichever job opens it
        guard let job = station.flatMap(job) ?? (kind.scope.isShared ? stationJobs.first ?? jobs.first : nil) else { return }
        paper = Paper(job: job, kind: kind)
    }

    // MARK: switch

    private func paneSwitch(_ data: Data) -> some View {
        TCCountSegments([.init("ตามสถานี", count: data.allRows.count, unit: "สถานี"),
                         .init("ต้องทำ", count: data.ours, alert: data.ours > 0, unit: "รายการ")]
                        + (readOnly ? [] : [.init("คลังกลาง", count: data.library.count, unit: "ฉบับ")]),
                        selection: Binding(get: { Pane.allCases.firstIndex(of: pane) ?? 0 }, set: { select(Pane.allCases[$0]) }))
            .padding(.horizontal, 16).padding(.top, 12)
    }

    func select(_ p: Pane) {
        withAnimation(reduceMotion ? nil : .snappy) { pane = p }
    }

    // MARK: DEBUG

    /// `-pwaDocsView st|todo|lib`, `-pwaDocsFilter todo|wait|all`, `-pwaDocsSearch YES`, `-pwaDocsDemo YES`. Release
    /// builds get the defaults.
    enum Debug {
        #if DEBUG
        private static let d = UserDefaults.standard
        static let pane = d.string(forKey: "pwaDocsView").flatMap(Pane.init) ?? .st
        static let filter: PWADocs.StationFilter = d.string(forKey: "pwaDocsFilter").flatMap {
            $0 == "wait" ? .waiting : PWADocs.StationFilter(rawValue: $0)
        } ?? .todo
        static let searchOpen = d.bool(forKey: "pwaDocsSearch")
        static let demo = d.bool(forKey: "pwaDocsDemo")
        #else
        static let pane = Pane.st
        static let filter = PWADocs.StationFilter.todo
        static let searchOpen = false
        #endif
    }
}

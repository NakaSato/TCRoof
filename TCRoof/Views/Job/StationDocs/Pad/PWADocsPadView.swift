import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `เอกสาร` on iPad (docs/ui/pwa-docs-ipad): the iPhone page's three views laid out for regular width. The large blue
/// header with its search and bell, the view switch and the sync chip, the summary with three origin tiles, then the
/// selected view: stations with the selected one's panel, the to-do columns, or the library. Papers open the document
/// sheet, which edits the same `StationDocs.DocState` as `StationDocSheet`. The iPad dock's `เอกสาร` tab is its root.
struct PWADocsPadView: View {
    typealias Pane = PWADocsHomeView.Pane

    /// A paper a sheet opens: one station's, or a library paper (no station).
    struct PaperRef: Identifiable, Hashable {
        let stationID: String?
        let kindID: String
        var id: String { (stationID ?? "library") + "/" + kindID }
    }

    /// The upload sheet: a station, the package drilled into (nil for all of them) and the slot it opens on.
    /// The upload sheet: a station (nil for a library paper), the package drilled into (nil for all of them) and the
    /// slot it opens on.
    struct UploadRef: Identifiable {
        let stationID: String?
        let package: StationDocs.Package?
        let kindID: String?
        var id: String { (stationID ?? "library") + "/" + (package?.rawValue ?? "") + "/" + (kindID ?? "") }
    }

    @Query(sort: \Job.installStart) var jobs: [Job]
    @State var pane = Debug.pane
    @State var filter = Debug.filter
    @State var contractor = Debug.contractor
    @State var sort = Debug.sort
    @State var search = Debug.query
    @State var searchOpen = Debug.searchOpen || !Debug.query.isEmpty
    @State var library = StationDocsStore.loadLibrary()
    @State var selectedID: String?
    @State var package: StationDocs.Package?
    @State var paper: PaperRef?
    @State var upload: UploadRef?
    @State var libraryPaper: PaperRef?
    @State var openStation: Job?
    @State var ercJob: Job?
    @State var share: SharedLink?
    @State var showNotifications = false
    /// A short message after an action that couldn't run (no approved file to merge).
    @State var notice: String?
    /// `-pwaDocsDemo YES`: what the sheets change in the example stays here; nothing is saved.
    @State var demoEdits: [String: StationDocs.Station] = [:]
    @State var demoLibrary: StationDocs.Library?
    @State var sync = CloudSync.shared
    @State private var debugOpened = false
    var bell = PWABell()
    @Environment(PadDock.self) var dock: PadDock?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var today: Date { .now }

    /// The station's papers and the ERC flow are the team's (`stationdocs.drafts`, `erc.flow_record`).
    @Environment(\.permissions) private var permissions

    var body: some View {
        if permissions.can(.stationDocsDrafts) {
            content
        } else {
            locked
        }
    }

    /// Contractors have no access (decided 18 ต.ค., `states/10`): the header and the lock, nothing loaded. Their site
    /// work (daily reports, the IEC test) is on each station's own page.
    private var locked: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.doc").font(.system(size: 30, weight: .medium)).foregroundStyle(Theme.inkMuted)
                .frame(width: 88, height: 88).background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text("เอกสารสำหรับทีมภายใน").font(.sarabunFixed(24, .bold)).foregroundStyle(Theme.navy)
                .accessibilityAddTraits(.isHeader)
            Text("เอกสาร PWA ร่างและยื่นโดยทีมภายใน · ผู้รับเหมาไม่มีสิทธิ์เข้าถึงหน้านี้")
                .font(.sarabunFixed(16)).foregroundStyle(Theme.inkMuted)
            Text("งานที่ต้องส่งจากหน้างาน เช่น รายงานประจำวันและผลทดสอบ IEC ทำได้ในหน้างานของแต่ละสถานี")
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 63)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pwaDocs.locked")
        .safeAreaInset(edge: .top, spacing: 0) {
            TCPhoneSearchHeader(title: "เอกสาร", subtitle: nil, search: .constant(""), isOpen: .constant(false),
                                showsSearch: false, large: true, wide: true,
                                bell: .init(unread: bell.unread) { withAnimation(.easeOut(duration: 0.2)) { showNotifications.toggle() } })
        }
        .overlay(alignment: .topTrailing) { if showNotifications { bellPanel } }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: dock?.tab) { showNotifications = false }
    }

    private var content: some View {
        let data = self.data
        return page(data)
            .safeAreaInset(edge: .top, spacing: 0) {
                TCPhoneSearchHeader(title: "เอกสาร", subtitle: nil, search: $search, isOpen: $searchOpen,
                                    prompt: "ค้นหาสถานี ชื่อเอกสาร เลขที่หนังสือ", large: true, wide: true,
                                    bell: .init(unread: bell.unread) { withAnimation(.easeOut(duration: 0.2)) { showNotifications.toggle() } })
            }
            .overlay(alignment: .topTrailing) { if searchOpen { AnyView(searchPanel(data)) } }
            .overlay(alignment: .topTrailing) { if showNotifications { bellPanel } }
            .background(Theme.phonePage.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openStation) { StationDocsScreen(job: $0).toolbar(.visible, for: .navigationBar) }
            .navigationDestination(item: $ercJob) { PWADocsERCScreen(job: $0).toolbar(.visible, for: .navigationBar) }
            .modifier(PWADocsPadSheets(page: self, data: data))
            .onChange(of: dock?.tab) { showNotifications = false }
            .onChange(of: dock?.showSettings) { showNotifications = false }
            .onChange(of: searchOpen) { _, open in if open { showNotifications = false } }
            .onAppear { library = StationDocsStore.loadLibrary() }
            // not at launch: a sheet presented before the page is on screen doesn't show
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                openDebugSheets(self.data)
            }
    }

    /// The page under the header: switch and sync, summary and tiles, then the view, ending 116 pt above the bottom
    /// (the dock is the bottom inset, 100 pt).
    private func page(_ data: PageData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            topRow(data)
            summaryRow(data)
            paneBody(data).frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 63).padding(.top, 20).padding(.bottom, 16)
    }

    /// Type-erased: the page is otherwise deep enough to crash a Debug build (CLAUDE.md, the `View.modifier` SIGSEGV).
    private func paneBody(_ data: PageData) -> AnyView {
        switch pane {
        case .st: AnyView(stationsPane(data))
        case .todo: AnyView(todoPane(data))
        case .lib: AnyView(libraryPane(data))
        }
    }

    // MARK: data

    /// Everything the page shows, worked out once per render.
    struct PageData {
        var stations: [PWAPlan.Station]
        var library: StationDocs.Library
        var summary: PWADocs.Summary
        /// Every station row, unfiltered.
        var rows: [PWADocs.StationRow]
        var groups: [PWADocs.Group]
        var libraryRows: [PWADocs.LibraryRow]
        /// Late or due today: the switch's red count.
        var dueNow: Int

        func station(_ id: String?) -> PWAPlan.Station? { stations.first { $0.id == id } }
        func row(_ id: String?) -> PWADocs.StationRow? { rows.first { $0.id == id } }
    }

    var data: PageData {
        let (stations, library) = source
        let groups = PWADocs.todo(stations, library: library)
        return PageData(stations: stations, library: library, summary: PWADocs.summary(stations, library: library),
                        rows: PWADocs.rows(stations, library: library, today: today), groups: groups,
                        libraryRows: PWADocs.library(library, today: today, warnDays: 60),
                        dueNow: PWADocs.dueNow(groups, today: today))
    }

    /// The PWA stations, the installing ones first.
    var stationJobs: [Job] {
        let all = jobs.pwaStations, installing = jobs.pwaInstalling
        return installing + all.filter { !installing.contains($0) }
    }

    var isDemo: Bool {
        #if DEBUG
        Debug.demo
        #else
        false
        #endif
    }

    /// The PWA jobs and the device library, or the board's example with `-pwaDocsDemo YES` (with this page's edits).
    private var source: ([PWAPlan.Station], StationDocs.Library) {
        #if DEBUG
        if Debug.demo {
            let stations = PWADocsDemo.stations(today: today, recent: true).map { st -> PWAPlan.Station in
                var st = st
                if let edited = demoEdits[st.id] { st.docs = edited }
                return st
            }
            return (stations, demoLibrary ?? PWADocsDemo.library(today: today))
        }
        #endif
        return (stationJobs.map(\.planStation), library)
    }

    func job(_ stationID: String?) -> Job? {
        guard let stationID else { return nil }
        return stationJobs.first { $0.overviewID == stationID }
    }

    // MARK: switch, sync and summary

    private func topRow(_ data: PageData) -> some View {
        HStack(spacing: 16) {
            TCCountSegments([.init("ตามสถานี", count: data.rows.count, unit: "สถานี"),
                             .init("ต้องทำ", count: data.dueNow, alert: data.dueNow > 0, unit: "รายการเลยหรือครบกำหนดวันนี้"),
                             .init("คลังกลาง", count: data.libraryRows.count, unit: "ฉบับ")],
                            selection: Binding(get: { Pane.allCases.firstIndex(of: pane) ?? 0 }, set: { select(Pane.allCases[$0]) }),
                            fontSize: 14, countSize: 12)
                .frame(width: 520)
                .accessibilityIdentifier("pwaDocs.switch")
            Spacer(minLength: 8)
            syncChip
        }
    }

    /// `ซิงก์ล่าสุด HH:mm` with a green dot, or amber `ออฟไลน์ · แสดงข้อมูลในเครื่อง`. Nothing before the first sync.
    @ViewBuilder private var syncChip: some View {
        if isOffline {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash").font(.system(size: 11, weight: .semibold))
                Text("ออฟไลน์ · แสดงข้อมูลในเครื่อง").font(.sarabunFixed(13, .semibold))
            }
            .foregroundStyle(Theme.warningText)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Theme.warningSoft, in: Capsule())
            .accessibilityElement(children: .combine)
        } else if let last = lastSync {
            HStack(spacing: 6) {
                Circle().fill(Theme.success).frame(width: 8, height: 8)
                Text("ซิงก์ล่าสุด " + ThaiFormat.time.string(from: last)).font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.navy)
            }
            .accessibilityElement(children: .combine)
        }
    }

    var isOffline: Bool {
        #if DEBUG
        if Debug.offline { return true }
        #endif
        if case .failed = sync.state { return true }
        return sync.refreshFailed
    }

    private var lastSync: Date? {
        #if DEBUG
        if Debug.demo { return sync.lastSync ?? today }
        #endif
        return sync.lastSync
    }

    private func summaryRow(_ data: PageData) -> some View {
        HStack(spacing: 14) {
            PWADocsPadSummary(summary: data.summary)
            tile("ทีมเราทำ", data.summary.open[.internalDoc] ?? 0, StationDocs.Origin.internalDoc.dot)
            tile("รอ กปภ. ลงนาม", data.summary.open[.signoff] ?? 0, StationDocs.Origin.signoff.dot)
            tile("รอหน่วยงานนอก", data.summary.open[.external] ?? 0, StationDocs.Origin.external.dot)
        }
        .frame(height: 92)
    }

    /// One origin's open count; a tap opens `ต้องทำ`.
    private func tile(_ title: String, _ count: Int, _ dot: Color) -> some View {
        Button { select(.todo) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(count)").font(.sarabunFixed(28, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                    Text("รายการ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(.horizontal, 16)
            .frame(width: 190, alignment: .leading).frame(maxHeight: .infinity)
            .padCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(count) รายการ")
        .accessibilityHint("เปิดต้องทำ")
    }

    func select(_ p: Pane) {
        withAnimation(reduceMotion ? nil : .snappy) { pane = p }
    }

    // MARK: bell

    private var bellPanel: some View {
        // the header is 88 pt high; the panel starts 11 pt under its bell (as `PWARoot`)
        ZStack(alignment: .topTrailing) {
            Theme.popoverDim.ignoresSafeArea().allowsHitTesting(false)
            Color.clear.contentShape(Rectangle()).onTapGesture { showNotifications = false }.padding(.top, 88)
            bell.view(large: true) { showNotifications = false }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.navy.opacity(0.28), radius: 20, y: 16)
                .padding(.top, 88 - 22 + 11).padding(.trailing, 58)
        }
        .transition(.opacity)
    }

    // MARK: DEBUG

    private func openDebugSheets(_ data: PageData) {
        #if DEBUG
        guard !debugOpened else { return }
        debugOpened = true
        if let mp = Debug.station, let st = data.stations.first(where: { $0.mpNumber == mp }) { selectedID = st.id }
        package = Debug.package
        let station = data.station(selectedID) ?? shownRows(data).first?.station
        // with `-pwaDocsUpload`, `-pwaDocsPaper` is the slot the upload sheet opens on
        if Debug.upload, let st = station { upload = UploadRef(stationID: st.id, package: package, kindID: Debug.paper) }
        else if let id = Debug.paper, let st = station { paper = PaperRef(stationID: st.id, kindID: id) }
        if let id = Debug.libraryPaper { libraryPaper = PaperRef(stationID: nil, kindID: id) }
        #endif
    }

    /// `-pwaDocsView st|todo|lib`, `-pwaDocsFilter todo|wait|all`, `-pwaDocsSearch YES`, `-pwaDocsDemo YES` (as the
    /// iPhone page), plus `-pwaDocsStation <mp>`, `-pwaDocsPackage building|grid_connection|pk2|handover`,
    /// `-pwaDocsPaper <kind id>`, `-pwaDocsUpload YES`, `-pwaDocsContractor <name>`, `-pwaDocsSort miss`,
    /// `-pwaDocsLibPaper <kind id>`, `-pwaDocsQuery <text>` and `-pwaDocsOffline YES`. Release builds get the defaults.
    enum Debug {
        static let pane = PWADocsHomeView.Debug.pane
        static let filter = PWADocsHomeView.Debug.filter
        static let searchOpen = PWADocsHomeView.Debug.searchOpen
        #if DEBUG
        private static let d = UserDefaults.standard
        static let demo = PWADocsHomeView.Debug.demo
        static let station = d.string(forKey: "pwaDocsStation").flatMap { Int($0) }
        static let package = d.string(forKey: "pwaDocsPackage").flatMap(StationDocs.Package.init)
        static let paper = d.string(forKey: "pwaDocsPaper")
        static let upload = d.bool(forKey: "pwaDocsUpload")
        static let contractor = d.string(forKey: "pwaDocsContractor")
        static let sort: PWADocs.StationSort = d.string(forKey: "pwaDocsSort") == "miss" ? .missing : .handover
        static let libraryPaper = d.string(forKey: "pwaDocsLibPaper")
        static let query = d.string(forKey: "pwaDocsQuery") ?? ""
        static let offline = d.bool(forKey: "pwaDocsOffline")
        #else
        static let contractor: String? = nil
        static let sort = PWADocs.StationSort.handover
        static let query = ""
        #endif
    }
}

/// The summary card: the approved ring and share, one bar stacked by status, and its legend.
struct PWADocsPadSummary: View {
    let summary: PWADocs.Summary

    var body: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(summary.percent)%").font(.sarabunFixed(24, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                    Text("อนุมัติแล้ว \(summary.approved) / \(summary.total) ฉบับ").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                }
                bar
                legend
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padCard()
        .accessibilityElement(children: .combine)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(summary.percent) / 100)
                .stroke(Theme.success, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
    }

    private var bands: [PWADocs.Band] { PWADocs.Band.allCases.filter { (summary.bands[$0] ?? 0) > 0 } }

    private var bar: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(bands.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(bands, id: \.self) { b in
                    Rectangle().fill(b.color)
                        .frame(width: max(0, (geo.size.width - gaps) * CGFloat(summary.bands[b] ?? 0) / CGFloat(max(summary.total, 1))))
                }
            }
        }
        .frame(height: 9)
        .background(Theme.borderOutdoor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(PWADocs.Band.allCases, id: \.self) { b in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(b.color).frame(width: 8, height: 8)
                    Text("\(b.title) \(summary.bands[b] ?? 0)").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
        }
        .minimumScaleFactor(0.8)
    }
}

extension View {
    /// The iPad page's white card: r16 with a hairline border, no shadow.
    func padCard(_ radius: CGFloat = 16) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

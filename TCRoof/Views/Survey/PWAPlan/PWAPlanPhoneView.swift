import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// The PWA module's `แผนงาน` tab on iPhone (docs/ui/pwa-plan-iphone): the header with its growing search, the view
/// switch (`ตารางงาน`, `แผน MP`, `กำหนดส่ง`) and the selected view under it. The PWA home's nav pushes it (`PWARoot`),
/// so the header has a back button. On iPad (docs/ui/pwa-plan-ipad) the PWA home shows it under its own header and
/// nav, given `padSearch`: the three views at once, in two columns (`PWAPlanPhoneView+Pad`).
struct PWAPlanPhoneView: View {
    enum Pane: String, CaseIterable { case schedule, mp, due }
    enum CalendarMode: String, CaseIterable { case week, month }

    /// A screen a row opens.
    enum Route: Hashable {
        case station(Job), schedule(Job), docs(Job), dailies(Job), report(UUID)
    }

    @Query(sort: \Job.installStart) private var jobs: [Job]
    /// iPad: the text of the PWA home's search, which is the page's header there. nil on iPhone.
    var padSearch: String? = nil
    @State var pane = Debug.pane
    @State private var ownSearch = ""
    var search: String { padSearch ?? ownSearch }
    var pad: Bool { padSearch != nil }
    /// iPad: `รายสถานี` past its first eight rows.
    @State var ganttAll = false
    @State var searchOpen = Debug.searchOpen
    // ตารางงาน
    @State var calendarMode = Debug.calendar
    /// The Monday of the week view's week, and the selected day: in that week, or in month view any day of its month.
    @State var weekStart = PWAPlanPhoneView.monday(of: Debug.day ?? PWAPlanPhoneView.today)
    @State var day = PWAPlan.calendar.startOfDay(for: Debug.day ?? PWAPlanPhoneView.today)
    /// Raised to scroll the day list to `day`, smoothly after a tap.
    @State var jump = 0
    @State var jumpAnimated = false
    /// The list's position doesn't select a day before this: while a jump is on its way.
    @State var spyLock = Date.distantFuture
    /// The list's last seen scroll offset.
    @State var spyOffset: CGFloat = 0
    @State var type: PWAPlan.JobType? = Debug.type
    @State var team: String? = Debug.team
    @State var showFilter = Debug.filterOpen
    // กำหนดส่ง
    @State var dueFilter: PWAPlan.DeadlineKind? = Debug.dueFilter
    @State var showDueMenu = Debug.dueMenuOpen
    @State var route: Route?
    @State private var library = StationDocsStore.loadLibrary()
    @State private var survey = SurveyModel.shared
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.isPresented) private var isPushed
    @Environment(\.dismiss) private var dismiss
    /// iPad: the dock under the page (`PadTabs`).
    @Environment(PadDock.self) var dock: PadDock?

    @Environment(\.permissions) private var permissions
    /// `งานของฉัน`: only the stations that name the signed-in member (`Permissions.isNamed`), for the agenda, the plans
    /// and the deadlines alike. The same setting as the PWA home's filter, so one switch serves both pages.
    @AppStorage("solarSurvey.onlyMine") var onlyMine = false

    /// Every PWA station, or with `งานของฉัน` the signed-in member's.
    private var stations: [Job] {
        let all = jobs.pwaStations
        guard onlyMine, let mine = jobs.mine(permissions) else { return all }
        return all.filter { $0.syncID.map(mine.contains) ?? false }
    }

    /// How many PWA stations name the signed-in member; nil before sign-in, which leaves the switch out.
    var mineCount: Int? {
        jobs.mine(permissions).map { mine in jobs.pwaStations.filter { $0.syncID.map(mine.contains) ?? false }.count }
    }

    /// The `งานของฉัน` switch: a person icon, filled when on.
    @ViewBuilder func mineChip(labelled: Bool) -> some View {
        if let n = mineCount {
            Button { onlyMine.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: onlyMine ? "person.crop.circle.fill" : "person.crop.circle").font(.system(size: 17, weight: .semibold))
                    if labelled { Text("งานของฉัน · \(n) สถานี").font(.sarabunFixed(13, .bold)) }
                }
                .foregroundStyle(onlyMine ? Theme.onPrimary : Theme.navySolid)
                .padding(.horizontal, labelled ? 12 : 0)
                .frame(minWidth: 44, minHeight: 44)
                .background(onlyMine ? Theme.primary : Theme.surface, in: Capsule())
                .overlay { if !onlyMine { Capsule().strokeBorder(Theme.borderSubtle) } }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("งานของฉัน \(n) สถานี")
            .accessibilityValue(onlyMine ? "เปิดอยู่" : "ปิด")
            .accessibilityIdentifier("pwaPlan.mine")
        }
    }

    var body: some View {
        let board = self.board
        Group {
            if pad { padPage(board) } else { phonePage(board) }
        }
        .navigationDestination(item: $route) { destination($0) }
        .onAppear { library = StationDocsStore.loadLibrary() }
    }

    private func phonePage(_ board: PWAPlanBoard) -> some View {
        let today = board.agenda([Self.today]).count, due = PWAPlan.groups(board.deadlines, today: Self.today)
        return VStack(spacing: 0) {
            pills(today: today, plans: board.bars.count, due: due)
            if pane == .schedule {
                // the calendar stays; only the list of days scrolls
                schedule(board)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if pane == .mp { mpPlan(board) } else { dueList(due) }
                    }
                    // 20 pt clear of the dock, which is the stack's bottom safe-area inset
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .overlay(alignment: .topTrailing) { if pane == .due && showDueMenu { dueMenu(due) } }
        .safeAreaInset(edge: .top, spacing: 0) {
            TCPhoneSearchHeader(title: "แผนงาน PWA", subtitle: "การประปาส่วนภูมิภาค", search: $ownSearch, isOpen: $searchOpen,
                                onBack: isPushed ? { dismiss() } : nil)
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// What the page shows: worked out from the PWA jobs, or the board's example with `-pwaPlanDemo YES`.
    private var board: PWAPlanBoard {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "pwaPlanDemo") { return PWAPlanDemo.board(today: Self.today) }
        #endif
        return PWAPlanBoard(stations: stations.map(\.planStation), library: library, today: Self.today,
                            threshold: survey.settings.behindThreshold)
    }

    // MARK: pills

    private func pills(today: Int, plans: Int, due: PWAPlan.DeadlineGroups) -> some View {
        HStack(spacing: 6) {
            TCCountSegments([.init("ตารางงาน", count: today), .init("แผน MP", count: plans),
                             .init("กำหนดส่ง", count: due.all.count, alert: due.hasLate)],
                            selection: Binding(get: { Pane.allCases.firstIndex(of: pane) ?? 0 }, set: { select(Pane.allCases[$0]) }))
            if pane == .due { dueFilterButton(due) }
            mineChip(labelled: false)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private func select(_ p: Pane) {
        showDueMenu = false
        // the day list comes back at its top: it scrolls to the selected day again
        if p == .schedule && pane != .schedule { spyLock = .distantFuture }
        withAnimation(reduceMotion ? nil : .snappy) { pane = p }
    }

    // MARK: navigation

    /// The job behind a row. The board's example stations are matched by MP number, so most of them open nothing.
    func open(_ target: PWAPlan.Target, station id: String) {
        guard let job = stations.first(where: { $0.overviewID == id })
                ?? stations.first(where: { j in j.mpNumber.map { "demo-\($0)" } == id }) else { return }
        switch target {
        case .station: route = .station(job)
        case .schedule: route = .schedule(job)
        case .docs: route = .docs(job)
        case .dailies: route = .dailies(job)
        case .survey:
            // the station's NO.224 report when it has one, else the station
            let report = job.syncID.flatMap { survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
            route = report.map { .report($0.id) } ?? .station(job)
        }
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .station(let job): JobDetailView(job: job)
        case .schedule(let job): MPScheduleScreen(job: job)
        case .docs(let job): StationDocsScreen(job: job)
        case .dailies(let job): DailyReportListView(job: job)
        case .report(let id): SurveyReportEditor(jobID: id)
        }
    }

    // MARK: dates

    /// The real date, or `-pwaPlanToday 2026-10-12` in DEBUG builds, to compare with the board.
    static var today: Date {
        #if DEBUG
        if let d = Debug.today { return d }
        #endif
        return .now
    }

    static func monday(of date: Date) -> Date {
        PWAPlan.calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? PWAPlan.calendar.startOfDay(for: date)
    }

    static func isoDay(_ s: String) -> Date? {
        let n = s.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3 else { return nil }
        return PWAPlan.calendar.date(from: DateComponents(year: n[0], month: n[1], day: n[2]))
    }

    // MARK: DEBUG

    /// `-pwaPlanView schedule|mp|due`, `-pwaPlanCalendar week|month`, `-pwaPlanDay 2026-10-13`, `-pwaPlanFilter open|ins-A|empty`,
    /// `-pwaPlanDueFilter open|doc`, `-pwaPlanSearch YES`, `-pwaPlanToday 2026-10-12`, and on iPad `-pwaPlanScrollEnd YES` (the right
    /// column at its end). Release builds get the defaults.
    enum Debug {
        #if DEBUG
        private static let d = UserDefaults.standard
        private static let filter = d.string(forKey: "pwaPlanFilter")
        private static let due = d.string(forKey: "pwaPlanDueFilter")
        static let today = d.string(forKey: "pwaPlanToday").flatMap(PWAPlanPhoneView.isoDay)
        static let pane = d.string(forKey: "pwaPlanView").flatMap(Pane.init) ?? .schedule
        static let calendar = d.string(forKey: "pwaPlanCalendar").flatMap(CalendarMode.init) ?? .week
        static let day = d.string(forKey: "pwaPlanDay").flatMap(PWAPlanPhoneView.isoDay)
        static let searchOpen = d.bool(forKey: "pwaPlanSearch")
        static let scrollEnd = d.bool(forKey: "pwaPlanScrollEnd")
        static let filterOpen = filter == "open"
        static let type: PWAPlan.JobType? = filter == "ins-A" ? .install : filter == "empty" ? .test : nil
        static let team: String? = filter == "ins-A" ? "A" : filter == "empty" ? "B" : nil
        static let dueMenuOpen = due == "open"
        static let dueFilter: PWAPlan.DeadlineKind? = due == "doc" ? .document : nil
        #else
        static let pane = Pane.schedule
        static let calendar = CalendarMode.week
        static let day: Date? = nil
        static let searchOpen = false, filterOpen = false, dueMenuOpen = false, scrollEnd = false
        static let type: PWAPlan.JobType? = nil
        static let team: String? = nil
        static let dueFilter: PWAPlan.DeadlineKind? = nil
        #endif
    }
}

/// Thai dates of the plan page, in Bangkok time.
enum PWAPlanFormat {
    private static func make(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = ThaiFormat.locale
        df.calendar = Calendar(identifier: .buddhist)
        df.timeZone = PWAPlan.calendar.timeZone
        df.dateFormat = format
        return df
    }

    /// `ตุลาคม 2569`
    static let monthYear = make("LLLL yyyy")
    /// `2569`
    static let year = make("yyyy")
    /// `วันจันทร์`
    static let weekday = make("EEEE")
    /// `12 ต.ค.`
    static let dayMonth = make("d MMM")
    /// `ต.ค.`
    static let month = make("MMM")
    /// `15/10`
    static let numeric = make("d/M")
    static let weekdayLetters = ["จ", "อ", "พ", "พฤ", "ศ", "ส", "อา"]

    /// `12–18 ต.ค.`, or `28 ก.ย.–4 ต.ค.` across two months.
    static func range(_ from: Date, _ to: Date) -> String {
        let cal = PWAPlan.calendar
        if cal.component(.month, from: from) == cal.component(.month, from: to) {
            return "\(cal.component(.day, from: from))–\(dayMonth.string(from: to))"
        }
        return "\(dayMonth.string(from: from))–\(dayMonth.string(from: to))"
    }

    static func percent(_ x: Double) -> String { "\(Int(x.rounded()))%" }
}

extension PWAPlan.JobType {
    var ink: Color {
        switch self {
        case .install: Theme.primary
        case .survey: Theme.planSurvey
        case .inspection: Theme.planInspect
        case .document: Theme.warningText
        case .test: Theme.successText
        case .notice: Theme.dangerText
        }
    }

    var fill: Color {
        switch self {
        case .install: Theme.primarySoft
        case .survey: Theme.planSurveySoft
        case .inspection: Theme.planInspectSoft
        case .document: Theme.warningTint
        case .test: Theme.successSoft
        case .notice: Theme.dangerSoft
        }
    }
}

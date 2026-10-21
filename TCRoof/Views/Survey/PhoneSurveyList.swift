import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

/// iPhone survey home (compact width, docs/ui/tcroof-survey-home-iphone): a greeting header, the week strip with
/// the next appointment and the selected day's agenda, every job behind the search field and status chips,
/// and a dock whose main button opens the next survey.
/// The root of the `สำรวจ` tab; when it is pushed (from the home module row) `TCGradientHeader` shows a back chevron.
struct PhoneSurveyList: View {
    @Query(sort: \Job.surveyDate) private var jobs: [Job]
    @State private var selectedDay = Self.debugDay
    @State private var status: JobStatus? = Self.debugStatus
    @State private var search = Self.debugQuery ?? ""
    @State private var showNewJob = false
    @Environment(\.permissions) private var permissions
    @State private var openedJob: Job?
    @State private var surveyJob: Job?
    @StateObject private var drive = DriveEstimate()
    @FocusState private var searching: Bool
    @AppStorage("surveyList.recentSearches") private var recentRaw = ""
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    private var query: String { search.trimmingCharacters(in: .whitespaces) }
    private var recent: [String] { RecentSearches.decode(recentRaw) }

    /// The jobs matching the query; the status chips count over these.
    private var searched: [Job] { jobs.filter { $0.matches(query) } }

    var body: some View {
        // the next appointment and its countdown follow the clock
        TimelineView(.everyMinute) { timeline in
            page(now: timeline.date)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewJob) { NewJobView { openedJob = $0 } }
        .navigationDestination(item: $openedJob) { JobDetailView(job: $0) }
        .navigationDestination(item: $surveyJob) { SurveyFormView(job: $0) }
        .onChange(of: searching) { _, focused in
            if !focused { remember(search) }
        }
        #if DEBUG
        .task {
            seedDraft()
            if UserDefaults.standard.string(forKey: "surveyNewJob") != nil { try? await Task.sleep(for: .milliseconds(500)); showNewJob = true }
            if UserDefaults.standard.bool(forKey: "surveySearchFocus") { try? await Task.sleep(for: .seconds(1)); searching = true }
        }
        #endif
    }

    private func page(now: Date) -> some View {
        let next = SurveyDayHome.next(dates: jobs.map(\.surveyDate), now: now).map { jobs[$0] }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    weekSection(now: now, next: next)
                    listSection(now: now)
                }
                // the last row clears the dock (68 + 10 + 16); the tab bar is already a safe-area inset
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 94)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: searching) { _, focused in
                if focused { withAnimation { proxy.scrollTo(Self.searchID, anchor: .top) } }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header(now: now) }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            SurveyHomeDock(next: next, now: now, open: { surveyJob = $0 }, add: permissions.can(.jobEdit) ? { showNewJob = true } : nil)
                // as a tab root the floating tab dock is the safe-area inset under it, `PhoneTab.barGap` further down
                .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .task(id: next?.persistentModelID) {
            await drive.load(address: next.map { "\($0.address) \($0.province)" } ?? "")
        }
    }

    private static let searchID = "search"

    #if DEBUG
    /// `-surveyDay <0-6>`, `-surveyStatus interested|confirmed|installing|completed`, `-surveySearch <text>` and
    /// `-surveySearchFocus YES` open the states of docs/ui/tcroof-survey-home-iphone/states;
    /// seed `ค้นหาล่าสุด` with `-surveyList.recentSearches "a\nb"`.
    private static var debugDay: Int { min(max(UserDefaults.standard.integer(forKey: "surveyDay"), 0), 6) }
    private static var debugStatus: JobStatus? { UserDefaults.standard.string(forKey: "surveyStatus").flatMap(JobStatus.init) }
    private static var debugQuery: String? { UserDefaults.standard.string(forKey: "surveySearch") }

    /// `-surveyListDraft YES`: today's first job gets a draft with the roof and electrical groups filled
    /// (`ทำต่อ ค่าไฟ`), for simulator checks.
    private func seedDraft() {
        guard UserDefaults.standard.bool(forKey: "surveyListDraft"),
              let job = jobs.first(where: { $0.surveyDate.isToday }), job.surveyDraft == nil else { return }
        let draft = SurveyForm.blankDraft(surveyor: "สมชาย")
        draft.roofType = SurveyOptions.roofTypes[0]; draft.roofAreaSqm = 40
        draft.orientation = SurveyOptions.orientations[0]; draft.shading = SurveyOptions.shadings[0]
        draft.utility = SurveyOptions.utilities[0]; draft.meterPhase = "1 เฟส"; draft.mainBreakerAmp = 63
        context.insert(draft)
        draft.job = job
        try? context.save()
    }
    #else
    private static var debugDay: Int { 0 }
    private static var debugStatus: JobStatus? { nil }
    private static var debugQuery: String? { nil }
    #endif

    // MARK: header

    private func header(now: Date) -> some View {
        let greeting = SurveyGreeting.text(hour: Calendar.current.component(.hour, from: now))
        return TCGradientHeader(title: "สำรวจหน้างาน",
                                subtitle: "\(greeting) | \(ThaiFormat.weekdayShortYear.string(from: now))",
                                large: true) { EmptyView() }
    }

    // MARK: week

    private func weekSection(now: Date, next: Job?) -> some View {
        let week = SurveyDayHome.week(now: now, dates: jobs.map(\.surveyDate))
        let range = "\(ThaiFormat.dayMonthShort.string(from: now)) – \(ThaiFormat.dayMonthShort.string(from: now.adding(days: 6)))"
        return VStack(spacing: 6) {
            SurveyHomeSectionLabel(title: "สัปดาห์นี้", trailing: range)
            SurveyWeekCard(week: week, selectedDay: $selectedDay, next: next,
                           agenda: agenda(now: now, next: next), now: now, driveText: drive.text,
                           open: { openedJob = $0 }, call: call, navigate: navigate)
        }
    }

    /// The selected day's other appointments, by time.
    private func agenda(now: Date, next: Job?) -> [Job] {
        SurveyDayHome.agenda(dates: jobs.map(\.surveyDate), offset: selectedDay, now: now,
                             excluding: next.flatMap { n in jobs.firstIndex { $0 === n } })
            .map { jobs[$0] }
    }

    private func call(_ job: Job) {
        let digits = job.phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel:\(digits)") { openURL(url) }
    }

    private func navigate(_ job: Job) {
        if let url = job.mapsURL { openURL(url) }
    }

    // MARK: all jobs

    private func listSection(now: Date) -> some View {
        let found = searched
        let shown = found.filter { status == nil || $0.status == status }
        let ordered = SurveyDayHome.listOrder(dates: shown.map(\.surveyDate), now: now).map { shown[$0] }
        return VStack(spacing: 10) {
            VStack(spacing: 6) {
                SurveyHomeSectionLabel(title: "งานสำรวจทั้งหมด", trailing: "\(ordered.count) งาน")
                searchField
            }
            .id(Self.searchID)
            if searching && search.isEmpty && !recent.isEmpty { recentChips }
            SurveyStatusChips(selection: $status, total: found.count, counts: SurveyDayHome.counts(found.map(\.status)))
                // the row bleeds to the screen edges
                .padding(.horizontal, -16)
            SurveyHomeList(jobs: ordered, empty: query.isEmpty ? "ไม่มีงานในสถานะนี้" : "ไม่พบงานที่ตรงกับ \"\(query)\"",
                           open: { openedJob = $0 })
            historyRow
        }
    }

    private var searchField: some View {
        PhoneSearchField(text: $search, focused: $searching, height: 50, radius: 10, fontSize: 16, iconSize: 18,
                         border: Theme.searchBorder) { remember(search) }
    }

    private var recentChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ค้นหาล่าสุด").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(recent, id: \.self) { q in
                    Button {
                        search = q
                        searching = false
                    } label: {
                        Text(q).font(.sarabun(13, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderOutdoor))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, -2)
    }

    /// The board has no history button in the header, so the history opens from under the list.
    private var historyRow: some View {
        NavigationLink { SurveyHistoryView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.primary)
                    .frame(width: 40)
                Text("ประวัติการสำรวจ").font(.sarabun(15.5, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SurveyHomeChevron()
            }
            .padding(.leading, 16).padding(.trailing, 14)
            .frame(minHeight: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(SurveyHomePressStyle())
    }

    private func remember(_ q: String) {
        let list = RecentSearches.adding(q, to: recent)
        if list != recent { recentRaw = RecentSearches.encode(list) }
    }
}

extension SurveyCardProgress.Segment {
    /// Done green, current blue, to do grey.
    var color: Color {
        switch self {
        case .done: Theme.stepDone
        case .current: Theme.primary
        case .todo: Theme.borderSubtle
        }
    }
}

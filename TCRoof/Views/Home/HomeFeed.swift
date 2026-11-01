import SwiftUI
import ImageIO
import TCRoofUI
import TCRoofCore

/// A screen a feed post opens: the record it was made from.
enum FeedLink: Hashable, Identifiable {
    case daily(job: String, day: Date)
    case inspection(job: String)
    case job(String)
    case homework(job: String)
    /// `แผนงานถัดไป`: the plan calendar on a day, and a PWA station's papers (docs/ui/tcroof-home-iphone-v4).
    case calendar(Date)
    case stationDocs(job: String)
    case records
    /// เดินทางและเบิกค่าใช้จ่าย on a month, from a claim decision.
    case claims(month: String)

    var id: Self { self }
}

extension Job {
    /// The key a feed post carries for its job.
    var feedKey: String { syncID ?? code }

    /// The job's records that make feed posts: daily reports, the submitted ICL check list, and a home job's punch list.
    var feedStation: FeedBuilder.Station {
        var s = FeedBuilder.Station(id: feedKey, code: code, name: stationName, project: kind == .pwa ? .pwa : .home,
                                    team: teamRaw, mpNumber: mpNumber, installStart: installStart, installDays: installDays)
        s.settings = routineSettings
        s.plan = scheduleInput.map { MasterSchedule.plan($0) } ?? []
        s.reports = dailyLogs.compactMap { log in
            log.report.map {
                FeedBuilder.Report($0, signedAt: log.engineerSignedAt, inspectorAckAt: log.inspectorAckAt, recorder: log.recorder,
                                   photos: log.sortedPhotos.indices.map(String.init))
            }
        }
        s.tests = inspections.compactMap { i in
            guard let at = i.submittedAt else { return nil }
            return FeedBuilder.Test(id: i.syncID ?? "icl", date: at, title: "ใบตรวจรับงาน (ICL)", unit: "ข้อ",
                                    passed: i.results.filter { $0.passed == true }.count, total: InspectionStep.all.count)
        }
        if kind == .home, let home = PermitStore(job: self).load(HomeJob.self, HomeWorkView.file) {
            s.punches = home.site.punches
            s.contractor = home.site.workOrder.contractor
        }
        return s
    }

    /// `feedStation` as the AI digest reads it: named by the project name (or MP number, code), never the customer's
    /// name that `stationName` falls back to.
    func digestStation(_ s: FeedBuilder.Station) -> FeedBuilder.Station {
        var s = s
        s.name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
}

/// Who acknowledged which post, shared by every member: `CloudSync` keeps it in step with the `feedAcks` collection
/// (one document per post, its `members` the emails that acknowledged it) and its listener brings in the others'
/// acknowledgements as they happen. The copy on this device shows the counts before sync connects and offline.
@MainActor @Observable final class FeedAcks {
    static let shared = FeedAcks()
    private static let key = "feed.acks"
    private(set) var members: [String: Set<String>]
    /// Sends one member's acknowledgement of a post (true) or its removal; set by `CloudSync` while it is connected.
    @ObservationIgnored var send: ((_ post: String, _ member: String, _ on: Bool) -> Void)?

    private init() {
        let saved = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: Set<String>].self, from: $0) }
        members = saved ?? [:]
    }

    func has(_ post: String, _ member: String) -> Bool { members[post]?.contains(member) == true }
    func count(_ post: FeedPost) -> Int { post.seedAcks + (members[post.id]?.count ?? 0) }

    func toggle(_ post: String, _ member: String) {
        var set = members[post] ?? []
        let on = set.remove(member) == nil
        if on { set.insert(member) }
        members[post] = set.isEmpty ? nil : set
        save()
        send?(post, member, on)
    }

    /// A post's members as Firestore has them (with this device's writes not yet confirmed); an empty set when its
    /// document was deleted.
    func receive(_ post: String, _ set: Set<String>) {
        guard members[post] ?? [] != set else { return }
        members[post] = set.isEmpty ? nil : set
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(members) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// The project feed under the iPhone home's appointment card (docs/ui/tcroof-home-iphone-v3; the filter is v4's
/// segmented control): the filter, then one card per post, newest first. The iPad home's right column (`layout: .column`, docs/ui/tcroof-home-ipad-v2) is the
/// same feed under a `ฟีดโครงการ` header row that holds the same segmented filter, with larger posts that have no
/// badge and show their stats as one strip (docs/ui/tcroof-home-ipad-v3).
struct HomeFeed: View {
    enum Layout {
        /// iPhone: chips and posts in the home's own scroll view.
        case phone
        /// iPad: the header row stays and the posts scroll under it, or with `scrolls` off they lie in the page's scroll view.
        case column(scrolls: Bool)
    }

    /// The minute the home was drawn at; a new one rebuilds the feed.
    let now: Date
    /// Teams on today's appointments, `ทีมของฉัน` when Settings names none.
    let todayTeams: Set<String>
    /// Shared with the home screen so this feed doesn't issue a second all-project query.
    let jobs: [Job]
    var layout = Layout.phone
    let open: (FeedLink) -> Void

    /// Every server snapshot sync brings in moves `lastSync`: a record added to a job already here rebuilds the feed
    /// then, not at the next minute.
    @State private var sync = CloudSync.shared
    /// Post ids on show while the feed's top was in view; posts beyond them are `มีโพสต์ใหม่`.
    @State private var seen: Set<String>?
    @State private var topVisible = true
    @Environment(GoogleSession.self) private var session
    @AppStorage("userTeam") private var userTeam = ""
    @AppStorage("feed.hidden") private var hiddenRaw = ""
    @State private var acks = FeedAcks.shared
    /// `สรุปโดย AI` of the daily summary, on this device.
    @State private var digest = FeedDigestStore.shared
    @State private var posts: [FeedPost] = []
    @State private var didBuild = false
    @State private var filter = HomeFeed.initialFilter
    @State private var days = FeedBuilder.windowDays
    /// A punch that can't be closed yet: it needs a photo of the fix.
    @State private var needsPhoto: FeedPost?
    /// A contractor's `แก้แล้ว` on a problem of a signed daily report: only the team changes a signed report
    /// (firestore.rules refuse it, which would leave their sync stuck).
    @State private var signedReport = false
    @Environment(\.permissions) private var permissions
    #if DEBUG
    // `-homeFeedIssue fixed`: the demo's issue fixed and its summary acknowledged; the demo keeps neither
    @State private var demoFixed: Set<String> = UserDefaults.standard.string(forKey: "homeFeedIssue") == "fixed" ? ["demo-issue"] : []
    @State private var demoAcked: Set<String> = UserDefaults.standard.string(forKey: "homeFeedIssue") == "fixed" ? ["demo-summary"] : []
    /// `-homeFeedArrive <s>`: a post that came in by sync, not by a pull, that many seconds after the feed appeared.
    @State private var demoArrived = 0
    #endif

    private var me: String { session.email ?? "me" }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: "\n").map(String.init)) }
    private var myTeams: Set<String> {
        if Self.isDemo { return ["TCR01", "TCR03"] }
        return userTeam.isEmpty ? todayTeams : [userTeam]
    }

    var body: some View {
        let shown = FeedBuilder.filter(posts, by: filter, myTeams: myTeams, hidden: hidden)
        let fresh = FeedBuilder.newCount(shown, seen: seen)
        Group {
            switch layout {
            case .phone:
                VStack(spacing: 10) {
                    segments.overlay(alignment: .top) { topMarker }
                    if sync.refreshFailed { offlineLine }
                    list(shown)
                }
            case .column(let scrolls):
                VStack(spacing: 12) {
                    columnHeader
                    if scrolls {
                        // the column scrolls on its own: its pill is its own
                        ScrollViewReader { proxy in
                            ScrollView { VStack(spacing: 14) { list(shown) }.overlay(alignment: .top) { topMarker } }.scrollIndicators(.hidden)
                                .refreshable { await sync.refresh() }
                                .overlay(alignment: .top) {
                                    if !topVisible, fresh > 0 { NewPostsPill(count: fresh) { Self.scrollToTop(proxy) }.padding(.top, 8) }
                                }
                        }
                    } else {
                        VStack(spacing: 14) { list(shown) }
                    }
                }
                .overlay(alignment: .top) { if case .column(false) = layout { topMarker } }
                .tcFeedSize(.pad)
            }
        }
        // the page that scrolls the feed shows the pill
        .preference(key: FeedNewPostsKey.self, value: topVisible ? 0 : fresh)
        .onChange(of: topVisible) { if topVisible { seen = Set(posts.map(\.id)) } }
        .task(id: Refresh(day: RoutineReport.day(now), jobs: jobs.count, days: days, synced: sync.lastSync, pulls: sync.refreshes)) {
            // Firestore can confirm several listeners in a burst. Let their snapshots settle before rebuilding the
            // all-project feed; relative timestamps update from `now` in the view without a full data scan each minute.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rebuild()
        }
        // back from a record a post opened
        .onAppear { if didBuild { rebuild() } }
        #if DEBUG
        .task {
            let s = UserDefaults.standard.double(forKey: "homeFeedArrive")
            guard Self.isDemo, s > 0, demoArrived == 0 else { return }
            try? await Task.sleep(for: .seconds(s))
            demoArrived = 1
            rebuild()
        }
        #endif
        .alert("ยังปิดรายการไม่ได้", isPresented: Binding(get: { needsPhoto != nil }, set: { if !$0 { needsPhoto = nil } }), presenting: needsPhoto) { post in
            Button("เปิด Punch list") { link(post, source: true) }
            Button("ยกเลิก", role: .cancel) {}
        } message: { _ in
            Text("ต้องมีรูปหลังแก้ก่อนปิดรายการ")
        }
        .alert("รายงานนี้ลงนามแล้ว", isPresented: $signedReport) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text("ปัญหาในรายงานที่ลงนามแล้ว ทีมของเราเป็นผู้ปิดหรือเปิดอีกครั้ง")
        }
    }

    private struct Refresh: Equatable { let day: Date; let jobs: Int; let days: Int; let synced: Date?; let pulls: Int }

    /// The posts, the empty state and `ดูโพสต์ก่อนหน้า`, for the layout's stack.
    @ViewBuilder private func list(_ shown: [FeedPost]) -> some View {
        LazyVStack(spacing: 14) {
            ForEach(shown) { card($0) }
            if !didBuild || (jobs.isEmpty && sync.isLoading("jobs")) {
                DataLoadingSkeleton(lines: 2)
                DataLoadingSkeleton(lines: 3)
                DataLoadingSkeleton(lines: 2)
            } else if shown.isEmpty {
                Text("ยังไม่มีความคืบหน้าวันนี้").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            if didBuild { earlier }
        }
    }

    private var isColumn: Bool { if case .column = layout { true } else { false } }

    /// The four filters as equal segments: across the content width on iPhone, 14 pt titles on iPad.
    private var segments: some View {
        let counts = FeedBuilder.counts(posts, myTeams: myTeams, hidden: hidden)
        return TCCountSegments(FeedFilter.allCases.map { .init($0.title, count: counts[$0] ?? 0) },
                               selection: Binding(get: { FeedFilter.allCases.firstIndex(of: filter) ?? 0 }, set: { filter = FeedFilter.allCases[$0] }),
                               fontSize: isColumn ? 14 : 13, countSize: isColumn ? 12.5 : 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("กรองฟีด")
    }

    /// iPad: `ฟีดโครงการ`, the time of the newest post, and the 440 pt filter at the right; in a narrow column the
    /// filter goes under the title, across the width.
    /// After a pull to refresh that couldn't reach the server: the feed is what this device has.
    private var offlineLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash").font(.system(size: 11, weight: .semibold))
            Text(["ออฟไลน์ | แสดงข้อมูลในเครื่อง", sync.lastSync.map { "ซิงก์ล่าสุด " + ThaiFormat.time.string(from: $0) }]
                .compactMap { $0 }.joined(separator: " | "))
                .font(.sarabun(12.5, relativeTo: .caption)).lineLimit(1)
        }
        .foregroundStyle(Theme.warningText)
        .padding(.horizontal, 10).padding(.vertical, 2)
        .background(Theme.warningSoft, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var columnHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                columnTitle
                Spacer(minLength: 0)
                segments.frame(width: 440)
            }
            VStack(alignment: .leading, spacing: 8) {
                columnTitle
                segments
            }
        }
    }

    private var columnTitle: some View {
        HStack(spacing: 10) {
            Text("ฟีดโครงการ").font(.sarabun(20, .bold, relativeTo: .title3)).foregroundStyle(Theme.navy)
                .accessibilityAddTraits(.isHeader)
            if sync.refreshFailed {
                offlineLine
            } else if let latest = posts.map(\.date).max() {
                HStack(spacing: 6) {
                    Circle().fill(Theme.success).frame(width: 7, height: 7)
                    Text("อัปเดตล่าสุด " + ThaiFormat.time.string(from: latest)).font(.sarabun(12.5, relativeTo: .caption))
                }
                .foregroundStyle(Theme.successText)
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(Theme.successSoft, in: Capsule())
            }
        }
        .lineLimit(1).fixedSize()
    }

    private var earlier: some View {
        Button { days += FeedBuilder.windowDays } label: {
            Text("ดูโพสต์ก่อนหน้า").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card(_ p: FeedPost) -> some View {
        let mine = acked(p)
        return TCFeedPost(initials: p.initials, avatar: avatar(p), who: p.who, badge: p.kind.badge, tone: p.kind.tone.ui,
                          detail: p.place + " | " + FeedBuilder.when(p, now: now), text: p.text,
                          stats: p.stats.map { .init($0.value, $0.label, $0.tone.ui) },
                          photoCount: p.photos.count, photoChips: p.chips.map { .init($0.text, $0.tone.ui) },
                          issue: issueBox(p),
                          note: digestNote(p).map { .init("สรุปโดย AI", text: $0.text, detail: $0.detail, busy: $0.busy) },
                          ackLine: FeedBuilder.ackLine(count: ackCount(p), mine: mine), ackFaces: ackCount(p), acknowledged: mine,
                          link: p.kind.link,
                          menu: [.init("ซ่อนโพสต์นี้", symbol: "eye.slash") { hiddenRaw = (hidden.union([p.id])).sorted().joined(separator: "\n") },
                                 .init("เปิดบันทึกต้นทาง", symbol: "doc.text") { link(p, source: true) }],
                          showsBadge: !isColumn,
                          onAck: { acknowledge(p) }, onOpen: { link(p, source: false) }) { i in
            photo(p, i)
        }
    }

    private func acked(_ p: FeedPost) -> Bool {
        #if DEBUG
        if Self.isDemo { return demoAcked.contains(p.id) }
        #endif
        return acks.has(p.id, me)
    }

    private func ackCount(_ p: FeedPost) -> Int {
        #if DEBUG
        if Self.isDemo { return p.seedAcks + (demoAcked.contains(p.id) ? 1 : 0) }
        #endif
        return acks.count(p)
    }

    private func acknowledge(_ p: FeedPost) {
        #if DEBUG
        if Self.isDemo { demoAcked.formSymmetricDifference([p.id]); return }
        #endif
        acks.toggle(p.id, me)
    }

    private func issueBox(_ p: FeedPost) -> TCFeedPost<AnyView>.Issue? {
        guard var issue = p.issue else { return nil }
        #if DEBUG
        if Self.isDemo { issue.fixed = demoFixed.contains(p.id) }
        #endif
        return .init(owner: issue.owner, due: issue.due.map(FeedBuilder.shortDate), fixed: issue.fixed) { setFixed(p, !issue.fixed) }
    }

    /// Issue posts are red; system posts navy; the rest take their team's colour.
    private func avatar(_ p: FeedPost) -> Color {
        if p.kind == .issue { return Theme.dangerText }
        if p.team.isEmpty || p.kind == .testResult { return Theme.heroSolid }
        return Team(rawValue: p.team)?.color ?? Theme.primary
    }

    private func photo(_ p: FeedPost, _ i: Int) -> AnyView {
        #if DEBUG
        if Self.isDemo { return AnyView(TCFeedExamplePhoto(p.photos[i] == "inverters" ? .inverters : .roof)) }
        #endif
        return AnyView(FeedPhoto(key: "\(p.id)-\(i)") { photoData(p, i) })
    }

    private func job(_ key: String) -> Job? { jobs.first { $0.feedKey == key } }

    private func photoData(_ p: FeedPost, _ i: Int) -> Data? {
        switch p.source {
        case .dailyReport(let key, let day):
            let photos = job(key)?.dailyLog(on: day)?.sortedPhotos ?? []
            return photos.indices.contains(i) ? photos[i].data : nil
        case .punch(let key, _):
            return job(key).flatMap { PermitStore(job: $0).photo(p.photos[i]) }
        default: return nil
        }
    }

    // MARK: Actions

    private func rebuild() {
        #if DEBUG
        if Self.isDemo { posts = Self.refreshDemoPosts(now: now, pulls: sync.refreshes + demoArrived) + Self.demoPosts(now: now); markSeen(); didBuild = true; return }
        #endif
#if DEBUG
        let stationsStartedAt = Date()
#endif
        let stations = jobs.map(\.feedStation)
#if DEBUG
        let stationsElapsedMS = Int(Date().timeIntervalSince(stationsStartedAt) * 1_000)
        let postsStartedAt = Date()
#endif
        posts = FeedBuilder.posts(stations, now: now, days: days)
#if DEBUG
        let postsElapsedMS = Int(Date().timeIntervalSince(postsStartedAt) * 1_000)
        print("HomeFeed: built \(stations.count) stations in \(stationsElapsedMS) ms; generated \(posts.count) posts in \(postsElapsedMS) ms")
#endif
        markSeen()
        askDigest(stations)
        didBuild = true
    }

    /// The daily summary on show gets its `สรุปโดย AI` (one question a day on this device, team only).
    private func askDigest(_ stations: [FeedBuilder.Station]) {
        guard permissions.can(.assistantUse), let day = summaryDay(posts.first { $0.kind == .summary }) else { return }
        digest.refresh(zip(jobs, stations).map { $0.digestStation($1) }, day: day, now: now)
    }

    private func summaryDay(_ p: FeedPost?) -> Date? {
        guard let p, case .summary(let day) = p.source else { return nil }
        return day
    }

    /// The AI box of a summary post: its text and time, or a spinner while it is asked; nothing for a contractor, or
    /// before any digest was written.
    private func digestNote(_ p: FeedPost) -> (text: String, detail: String?, busy: Bool)? {
        #if DEBUG
        if Self.isDemo, p.id == "demo-summary" {
            return ("วันนี้ส่งรายงานแล้ว 8 จาก 12 สถานี งานรวมขยับขึ้น 2% ยังมี 4 สถานีที่ไม่ส่ง ควรโทรตามก่อน "
                    + "ส่วนงานบ้าน TC-0012 ยังมีปัญหาค้าง 1 เรื่อง พรุ่งนี้ให้ปิดเรื่องนี้ก่อนเริ่มงานใหม่", "อัปเดต 18:05", false)
        }
        #endif
        guard permissions.can(.assistantUse), let day = summaryDay(p) else { return nil }
        let busy = digest.isBusy(day)
        guard let e = digest.entry(day), !e.text.isEmpty else { return busy ? ("", nil, true) : nil }
        return (e.text, Self.digestTime.string(from: e.at), busy)
    }

    private static let digestTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.dateFormat = "อัปเดต HH:mm"
        return f
    }()

    /// Posts on show while the top is in view, or at the first build, are seen.
    private func markSeen() {
        if seen == nil || topVisible { seen = Set(posts.map(\.id)) }
    }

    // MARK: มีโพสต์ใหม่

    static let topID = "homeFeed.top"

    /// Marks the feed's top for `scrollTo` and tells whether it is in the scroll view's visible part.
    private var topMarker: some View {
        Color.clear.frame(height: 1).id(Self.topID)
            .onGeometryChange(for: Bool.self) { g in
                let y = g.frame(in: .scrollView).minY
                return y > -24 && y < (g.bounds(of: .scrollView)?.height ?? .infinity)
            } action: { topVisible = $0 }
            .accessibilityHidden(true)
    }

    static func scrollToTop(_ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(topID, anchor: .top) }
    }

    /// The post's link (`ดูรายงาน`, `ดูงาน` …), or with `source` the record it was made from.
    private func link(_ p: FeedPost, source: Bool) {
        // nothing to open when the post's job is not on this device (the demo's posts have none)
        switch p.source {
        case .dailyReport(let key, _), .test(let key, _), .problem(let key, _), .punch(let key, _):
            guard job(key) != nil else { return }
        case .summary: break
        }
        switch p.source {
        case .dailyReport(let key, let day): open(.daily(job: key, day: day))
        case .test(let key, _): open(.inspection(job: key))
        case .problem(let key, let id):
            let day = job(key)?.dailyLogs.last { $0.report?.problems.contains { $0.id == id } == true }?.date
            if source, let day { open(.daily(job: key, day: day)) } else { open(.job(key)) }
        case .punch(let key, _): open(.homework(job: key))
        case .summary: open(.records)
        }
    }

    /// `แก้แล้ว` / `เปิดอีกครั้ง`: writes the issue's own record, the daily report's problem or the home job's punch.
    private func setFixed(_ p: FeedPost, _ fixed: Bool) {
        #if DEBUG
        if Self.isDemo { demoFixed.formSymmetricDifference([p.id]); return }
        #endif
        switch p.source {
        case .problem(let key, let id):
            guard let job = job(key) else { return }
            let logs = job.dailyLogs
            var reports = logs.compactMap(\.report)
            guard reports.count == logs.count, FeedBuilder.setProblem(id, fixed: fixed, in: &reports) else { return }
            let changed = zip(logs, reports).filter { $0.0.report != $0.1 }
            if permissions.role == .external, changed.contains(where: { $0.0.engineerSignedAt != nil }) { signedReport = true; return }
            for (log, report) in changed { log.report = report }
        case .punch(let key, let id):
            guard let job = job(key) else { return }
            let store = PermitStore(job: job)
            guard var home = store.load(HomeJob.self, HomeWorkView.file) else { return }
            guard FeedBuilder.setPunch(id, fixed: fixed, in: &home.site, at: .now) else { needsPhoto = p; return }
            store.save(home, HomeWorkView.file)
        default: return
        }
        rebuild()
    }
}

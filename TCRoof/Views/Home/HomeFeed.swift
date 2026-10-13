import SwiftUI
import SwiftData
import ImageIO
import TCRoofUI
import TCRoofCore

/// A screen a feed post opens: the record it was made from.
enum FeedLink: Hashable, Identifiable {
    case daily(job: String, day: Date)
    case inspection(job: String)
    case job(String)
    case homework(job: String)
    case records

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
                                   photos: log.photos.indices.map(String.init))
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
}

/// Who acknowledged which post. Kept on this device: a shared count needs a synced `feedAcks` collection, whose
/// Firestore rule has to be deployed before any build writes to it (docs/ui/tcroof-home-iphone-v3, open question 2).
@Observable final class FeedAcks {
    static let shared = FeedAcks()
    private static let key = "feed.acks"
    private(set) var members: [String: Set<String>]

    private init() {
        let saved = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: Set<String>].self, from: $0) }
        members = saved ?? [:]
    }

    func has(_ post: String, _ member: String) -> Bool { members[post]?.contains(member) == true }
    func count(_ post: FeedPost) -> Int { post.seedAcks + (members[post.id]?.count ?? 0) }

    func toggle(_ post: String, _ member: String) {
        var set = members[post] ?? []
        if set.remove(member) == nil { set.insert(member) }
        members[post] = set.isEmpty ? nil : set
        if let data = try? JSONEncoder().encode(members) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// The project feed under the iPhone home's appointment card (docs/ui/tcroof-home-iphone-v3): filter chips, then one
/// card per post, newest first. The iPad home's right column (`layout: .column`, docs/ui/tcroof-home-ipad-v2) is the
/// same feed under a `ฟีดโครงการ` header row that holds the chips, with larger posts.
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
    var layout = Layout.phone
    let open: (FeedLink) -> Void

    @Query(sort: \Job.installStart) private var jobs: [Job]
    @Environment(GoogleSession.self) private var session
    @AppStorage("userTeam") private var userTeam = ""
    @AppStorage("feed.hidden") private var hiddenRaw = ""
    @State private var acks = FeedAcks.shared
    @State private var posts: [FeedPost] = []
    @State private var filter = HomeFeed.initialFilter
    @State private var days = FeedBuilder.windowDays
    /// A punch that can't be closed yet: it needs a photo of the fix.
    @State private var needsPhoto: FeedPost?
    #if DEBUG
    // `-homeFeedIssue fixed`: the demo's issue fixed and its summary acknowledged; the demo keeps neither
    @State private var demoFixed: Set<String> = UserDefaults.standard.string(forKey: "homeFeedIssue") == "fixed" ? ["demo-issue"] : []
    @State private var demoAcked: Set<String> = UserDefaults.standard.string(forKey: "homeFeedIssue") == "fixed" ? ["demo-summary"] : []
    #endif

    private var me: String { session.email ?? "me" }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: "\n").map(String.init)) }
    private var myTeams: Set<String> {
        if Self.isDemo { return ["TCR01", "TCR03"] }
        return userTeam.isEmpty ? todayTeams : [userTeam]
    }

    var body: some View {
        let shown = FeedBuilder.filter(posts, by: filter, myTeams: myTeams, hidden: hidden)
        Group {
            switch layout {
            case .phone:
                VStack(spacing: 10) {
                    chips
                    list(shown)
                }
            case .column(let scrolls):
                VStack(spacing: 12) {
                    columnHeader
                    if scrolls {
                        ScrollView { VStack(spacing: 14) { list(shown) } }.scrollIndicators(.hidden)
                    } else {
                        VStack(spacing: 14) { list(shown) }
                    }
                }
                .tcFeedSize(.pad)
            }
        }
        .task(id: Refresh(now: now, jobs: jobs.count, days: days)) { rebuild() }
        // back from a record a post opened
        .onAppear { rebuild() }
        .alert("ยังปิดรายการไม่ได้", isPresented: Binding(get: { needsPhoto != nil }, set: { if !$0 { needsPhoto = nil } }), presenting: needsPhoto) { post in
            Button("เปิด Punch list") { link(post, source: true) }
            Button("ยกเลิก", role: .cancel) {}
        } message: { _ in
            Text("ต้องมีรูปหลังแก้ก่อนปิดรายการ")
        }
    }

    private struct Refresh: Equatable { let now: Date; let jobs: Int; let days: Int }

    /// The posts, the empty state and `ดูโพสต์ก่อนหน้า`, for the layout's stack.
    @ViewBuilder private func list(_ shown: [FeedPost]) -> some View {
        ForEach(shown) { card($0) }
        if shown.isEmpty {
            Text("ยังไม่มีความคืบหน้าวันนี้").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        earlier
    }

    private var chipRow: some View {
        let counts = FeedBuilder.counts(posts, myTeams: myTeams, hidden: hidden)
        return HStack(spacing: 6) {
            ForEach(FeedFilter.allCases) { f in
                TCFeedChip(f.title, count: counts[f] ?? 0, selected: filter == f) { filter = f }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("กรองฟีด")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) { chipRow }
            .scrollClipDisabled()
            .padding(.vertical, -2)
    }

    /// iPad: `ฟีดโครงการ`, the time of the newest post, and the chips at the right; in a narrow column the chips
    /// go under the title.
    private var columnHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                columnTitle
                Spacer(minLength: 0)
                chipRow
            }
            VStack(alignment: .leading, spacing: 8) {
                columnTitle
                chips
            }
        }
        .padding(.vertical, -2)
    }

    private var columnTitle: some View {
        HStack(spacing: 10) {
            Text("ฟีดโครงการ").font(.sarabun(20, .bold, relativeTo: .title3)).foregroundStyle(Theme.navy)
                .accessibilityAddTraits(.isHeader)
            if let latest = posts.map(\.date).max() {
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
                          detail: p.place + " · " + FeedBuilder.when(p, now: now), text: p.text,
                          stats: p.stats.map { .init($0.value, $0.label, $0.tone.ui) },
                          photoCount: p.photos.count, photoChips: p.chips.map { .init($0.text, $0.tone.ui) },
                          issue: issueBox(p),
                          ackLine: FeedBuilder.ackLine(count: ackCount(p), mine: mine), ackFaces: ackCount(p), acknowledged: mine,
                          link: p.kind.link,
                          menu: [.init("ซ่อนโพสต์นี้", symbol: "eye.slash") { hiddenRaw = (hidden.union([p.id])).sorted().joined(separator: "\n") },
                                 .init("เปิดบันทึกต้นทาง", symbol: "doc.text") { link(p, source: true) }],
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
        if Self.isDemo { posts = Self.demoPosts(now: now); return }
        #endif
        posts = FeedBuilder.posts(jobs.map(\.feedStation), now: now, days: days)
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
        case .dailyReport(let key, let day): open(p.kind == .waitingInspector && !source ? .job(key) : .daily(job: key, day: day))
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
            for (log, report) in zip(logs, reports) where log.report != report { log.report = report }
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

    // MARK: DEBUG

    private static var isDemo: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "homeFeed") == "demo"
        #else
        false
        #endif
    }

    private static var initialFilter: FeedFilter {
        #if DEBUG
        // `-homeFeedFilter all|pwa|home|mine`
        if let f = UserDefaults.standard.string(forKey: "homeFeedFilter").flatMap(FeedFilter.init) { return f }
        #endif
        return .all
    }

    #if DEBUG
    /// `-homeFeed demo`: the board's five posts (docs/ui/tcroof-home-iphone-v3/states/07), with drawn example photos.
    static func demoPosts(now: Date) -> [FeedPost] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let day = FeedBuilder.calendar.startOfDay(for: now)
        return [
            FeedPost(id: "demo-summary", kind: .summary, project: nil, initials: "TC", who: "TCRoof", place: "ทุกโครงการ",
                     date: FeedBuilder.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now,
                     text: "สรุปวันที่ \(FeedBuilder.shortDate(now)) — ส่งรายงานแล้ว 8/12 สถานี กปภ. ความคืบหน้ารวม +2% ปัญหาค้าง 1 เรื่อง (งานบ้าน TC-0012)",
                     stats: [.init("8/12", "ส่งรายงาน", .blue), .init("+2%", "ความคืบหน้ารวม", .green), .init("1", "ปัญหาค้าง", .red)],
                     source: .summary(day: day), pinned: true, seedAcks: 5),
            FeedPost(id: "demo-issue", kind: .issue, project: .home, team: "TCR01", initials: "B", who: "ทีม B · งานบ้าน",
                     place: "TC-0012 · ติดตั้ง Day 2/5", date: ago(180),
                     text: "พบรอยรั่วที่ครอบหลังคาจุด B3 หลังเจาะยึดราง ต้องอุดซิลิโคนและทดสอบน้ำก่อนวางแผงแถว B",
                     issue: .init(owner: "ทีม B (สมศักดิ์ · ตัวอย่าง)", due: now.adding(days: 1), fixed: false),
                     source: .punch(project: "demo", id: "demo"), seedAcks: 1),
            FeedPost(id: "demo-progress", kind: .progress, project: .pwa, team: "TCR03", initials: "A", who: "ทีม A · ผู้รับเหมา A",
                     place: "MP 189 ทุ่งน้อย · 2.3 ติดตั้งแผง", date: ago(25),
                     text: "วางแผงแถว C เสร็จ 48/120 แผง ขันทอร์กครบ เหลือแถว D พรุ่งนี้เช้า (ฝนบ่ายนี้ หยุดงานบนหลังคา 13:00)",
                     photos: ["roof", "inverters", "roof", "roof"], chips: [.init("+6% วันนี้", .green), .init("38% / แผน 50%", .red)],
                     source: .dailyReport(project: "demo", day: day), seedAcks: 4),
            FeedPost(id: "demo-test", kind: .testResult, project: .pwa, team: "TCR04", initials: "TC", who: "TCRoof",
                     place: "MP 77 โชคชัย · 3.1 Pre-Commissioning", date: ago(60),
                     text: "ผลทดสอบ IEC 62446 ผ่านครบ 12 สตริง พร้อมอบรม O&M 24 ต.ค.",
                     stats: [.init("12/12", "สตริงผ่าน", .green), .init("> 40 MΩ", "ฉนวน", .blue), .init("171 kWp", "กำลังติดตั้ง", .blue)],
                     source: .test(project: "demo", id: "demo"), seedAcks: 7),
            FeedPost(id: "demo-inspector", kind: .waitingInspector, project: .pwa, team: "TCR02", initials: "C", who: "ทีม C · ผู้รับเหมา C",
                     place: "MP 154 แพรกหนามแดง · 2.5 Inverter", date: ago(120),
                     text: "ติดตั้งอินเวอร์เตอร์ 3 ตัวครบ เดินสาย AC เข้าตู้แล้ว ขอผู้แทน กปภ. ตรวจ 10:30 พรุ่งนี้",
                     photos: ["inverters", "roof", "inverters", "roof", "inverters", "roof"], chips: [.init("71% / แผน 68%", .green)],
                     source: .dailyReport(project: "demo", day: day), seedAcks: 2),
        ]
    }
    #endif
}

private extension FeedPost.Tone {
    var ui: TCFeedTone {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        }
    }
}

/// A record's photo in a post, scaled down off the main thread and cached by post and index.
private struct FeedPhoto: View {
    let key: String
    let data: () -> Data?
    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Theme.track
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipped()
            .task(id: key) {
                if let hit = Self.cache.object(forKey: key as NSString) { image = hit; return }
                guard let data = data() else { return }
                let made = await Task.detached(priority: .userInitiated) { Self.scaled(data) }.value
                if let made { Self.cache.setObject(made, forKey: key as NSString) }
                image = made
            }
    }

    private nonisolated static func scaled(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

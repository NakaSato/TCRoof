import SwiftUI
import ImageIO
import TCRoofUI
import TCRoofCore

extension HomeFeed {
    static var isDemo: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "homeFeed") == "demo"
        #else
        false
        #endif
    }

    static var initialFilter: FeedFilter {
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
            FeedPost(id: "demo-issue", kind: .issue, project: .home, team: "TCR01", initials: "B", who: "ทีม B | งานบ้าน",
                     place: "TC-0012 | ติดตั้ง Day 2/5", date: ago(180),
                     text: "พบรอยรั่วที่ครอบหลังคาจุด B3 หลังเจาะยึดราง ต้องอุดซิลิโคนและทดสอบน้ำก่อนวางแผงแถว B",
                     issue: .init(owner: "ทีม B (สมศักดิ์ | ตัวอย่าง)", due: now.adding(days: 1), fixed: false),
                     source: .punch(project: "demo", id: "demo"), seedAcks: 1),
            FeedPost(id: "demo-progress", kind: .progress, project: .pwa, team: "TCR03", initials: "A", who: "ทีม A | ผู้รับเหมา A",
                     place: "MP 189 ทุ่งน้อย | 2.3 ติดตั้งแผง", date: ago(25),
                     text: "วางแผงแถว C เสร็จ 48/120 แผง ขันทอร์กครบ เหลือแถว D พรุ่งนี้เช้า (ฝนบ่ายนี้ หยุดงานบนหลังคา 13:00)",
                     photos: ["roof", "inverters", "roof", "roof"], chips: [.init("+6% วันนี้", .green), .init("38% / แผน 50%", .red)],
                     source: .dailyReport(project: "demo", day: day), seedAcks: 4),
            FeedPost(id: "demo-test", kind: .testResult, project: .pwa, team: "TCR04", initials: "TC", who: "TCRoof",
                     place: "MP 77 โชคชัย | 3.1 Pre-Commissioning", date: ago(60),
                     text: "ผลทดสอบ IEC 62446 ผ่านครบ 12 สตริง พร้อมอบรม O&M 24 ต.ค.",
                     stats: [.init("12/12", "สตริงผ่าน", .green), .init("> 40 MΩ", "ฉนวน", .blue), .init("171 kWp", "กำลังติดตั้ง", .blue)],
                     source: .test(project: "demo", id: "demo"), seedAcks: 7),
            FeedPost(id: "demo-inspector", kind: .waitingInspector, project: .pwa, team: "TCR02", initials: "C", who: "ทีม C | ผู้รับเหมา C",
                     place: "MP 154 แพรกหนามแดง | 2.5 Inverter", date: ago(120),
                     text: "ติดตั้งอินเวอร์เตอร์ 3 ตัวครบ เดินสาย AC เข้าตู้แล้ว ขอผู้แทน กปภ. ตรวจ 10:30 พรุ่งนี้",
                     photos: ["inverters", "roof", "inverters", "roof", "inverters", "roof"], chips: [.init("71% / แผน 68%", .green)],
                     source: .dailyReport(project: "demo", day: day), seedAcks: 2),
        ]
    }

    /// `-homeFeedRefresh YES` (with `-homeFeed demo`): each pull to refresh (and `-homeFeedArrive`'s post) brings one
    /// more example post, as if sync had brought a daily report in. Nothing is saved.
    static func refreshDemoPosts(now: Date, pulls: Int) -> [FeedPost] {
        let d = UserDefaults.standard
        guard d.bool(forKey: "homeFeedRefresh") || d.double(forKey: "homeFeedArrive") > 0, pulls > 0 else { return [] }
        let day = FeedBuilder.calendar.startOfDay(for: now)
        return (1...pulls).reversed().map { n in
            FeedPost(id: "demo-pull-\(n)", kind: .progress, project: .pwa, team: "TCR02", initials: "C", who: "ทีม C | ผู้รับเหมา C",
                     place: "MP 154 แพรกหนามแดง | 2.6 สาย AC", date: now.addingTimeInterval(Double(n - pulls) * 60),
                     text: "รายงานใหม่ \(n) (ตัวอย่าง): เดินสาย AC ช่วงที่ \(n) เสร็จ",
                     chips: [.init("+\(n)% วันนี้", .green)], source: .dailyReport(project: "demo", day: day))
        }
    }
    #endif
}

extension FeedPost.Tone {
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
struct FeedPhoto: View {
    let key: String
    let data: () -> Data?
    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Theme.track
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipped()
            .task(id: key) {
                guard !Task.isCancelled else { return }
                if let hit = Self.cache.object(forKey: key as NSString) { image = hit; return }
                image = nil
                guard let data = data() else { return }
                let made = try? await BackgroundWork.value { Self.scaled(data) }
                guard !Task.isCancelled else { return }
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

/// The number of posts new since the feed's top was last in view, for the page that scrolls it.
struct FeedNewPostsKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value = max(value, nextValue()) }
}

/// `มีโพสต์ใหม่ N`: floats at the top of the scrolled page; a tap goes back to the feed's top.
struct NewPostsPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("มีโพสต์ใหม่ \(count)", systemImage: "arrow.up")
                .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Theme.primary, in: Capsule())
                .shadow(color: Theme.navy.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("feed.newPosts")
    }
}

extension View {
    /// The `มีโพสต์ใหม่` pill over a page's scroll view that holds the home feed.
    func feedNewPostsPill(top: CGFloat = 8) -> some View {
        modifier(FeedNewPostsPillModifier(top: top))
    }
}

private struct FeedNewPostsPillModifier: ViewModifier {
    let top: CGFloat
    @State private var count = 0

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onPreferenceChange(FeedNewPostsKey.self) { v in withAnimation { count = v } }
                .overlay(alignment: .top) {
                    if count > 0 { NewPostsPill(count: count) { HomeFeed.scrollToTop(proxy) }.padding(.top, top) }
                }
        }
    }
}

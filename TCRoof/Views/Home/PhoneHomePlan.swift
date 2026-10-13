import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// One page of the iPhone home's `แผนงานถัดไป` (docs/ui/tcroof-home-iphone-v4): planned work still ahead when today
/// has no survey appointment left.
struct HomePlanItem: Identifiable {
    let id: String
    let type: PWAPlan.JobType
    /// Start of the item's day, and minutes after midnight when it has a time.
    let day: Date
    let start: Int?
    /// `MP 133 บางปะกง — 2.3 ติดตั้งแผงเซลล์`
    let name: String
    let place: String
    /// 0…1, the ring.
    let progress: Double
    let job: Job
}

extension HomePlanItem {
    /// Days ahead the card looks, today included: the two weeks of the PWA plan page's `กำหนดส่ง`.
    static let horizon = 14

    /// The next install days, IEC 62446 tests and PWA document deadlines, the nearest first, one per job and type.
    /// PWA jobs take them from the plan page's agenda (their MP plan and papers). A job the MP plan doesn't cover
    /// (a home job, or a PWA job with no plan yet) gives its install days, the plan calendar's install bars.
    @MainActor static func list(jobs: [Job], survey: SurveyModel, now: Date) -> [HomePlanItem] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "homeHeroPlan") == "demo" { return demo(jobs: jobs, now: now) }
        #endif
        let cal = PWAPlan.calendar
        let today = cal.startOfDay(for: now)
        let days = (0...horizon).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let pwa = jobs.pwaStations
        let stations = pwa.map(\.planStation)
        let threshold = survey.settings.behindThreshold
        let deadlines = PWAPlan.deadlines(stations, library: StationDocsStore.loadLibrary(), today: now, threshold: threshold)
        let bars = Dictionary(PWAPlan.bars(stations, today: now, threshold: threshold).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items = PWAPlan.agenda(stations, deadlines: deadlines, days: days, today: now, threshold: threshold)
        for job in jobs where job.kind != .pwa || job.scheduleInput == nil {
            for d in days {
                guard let n = job.installDay(on: d) else { continue }
                let at = Calendar.current.dateComponents([.hour, .minute], from: job.installStart)
                let minutes = (at.hour ?? 0) * 60 + (at.minute ?? 0)
                items.append(PWAPlan.AgendaItem(id: "home-ins-\(job.overviewID)-\(n)", day: cal.startOfDay(for: d), start: minutes > 0 ? minutes : nil,
                                                type: .install, ref: job.code, title: "ติดตั้ง Day \(n)/\(job.installDays)", subtitle: "",
                                                status: .onPlan, team: job.team.rawValue, station: job.overviewID))
            }
        }
        let byID = Dictionary(jobs.map { ($0.overviewID, $0) }, uniquingKeysWith: { a, _ in a })
        return PWAPlan.next(items, after: now).compactMap { item in
            guard let job = byID[item.station] else { return nil }
            let kWp = job.capacityKW > 0 ? "\(job.capacityKW.plain) kWp" : nil
            if job.kind == .pwa, job.scheduleInput != nil {
                let s = job.planStation, bar = bars[item.station]
                let party = s.contractor.isEmpty ? (s.team.isEmpty ? nil : "ทีม \(s.team)") : PWAPlan.contractorTitle(s.contractor)
                let note: String? = switch item.type {
                case .install: bar.map { $0.behind ? "ช้ากว่าแผน" : "ตามแผน" }
                case .document: deadlines.first { "doc-\($0.id)" == item.id }?.chip
                default: nil
                }
                return HomePlanItem(id: item.id, type: item.type, day: item.day, start: item.start,
                                    name: "\(s.ref) \(s.shortName) — \(item.title)",
                                    place: [party, kWp, note].compactMap { $0 }.joined(separator: " · "),
                                    progress: (bar?.actual ?? 0) / 100, job: job)
            }
            let n = job.installDay(on: item.day) ?? 1
            return HomePlanItem(id: item.id, type: item.type, day: item.day, start: item.start,
                                name: "\(job.code) \(job.stationName) — \(item.title)",
                                place: [job.province.isEmpty ? nil : "จ.\(job.province)", kWp, "ทีม \(job.team.rawValue)"].compactMap { $0 }.joined(separator: " · "),
                                progress: Double(n - 1) / Double(max(job.installDays, 1)), job: job)
        }
    }

    #if DEBUG
    /// `-homeHeroPlan demo` (with `-homeNoAppointments YES`): the board's three example items on the first three jobs,
    /// dated from tomorrow. Nothing is saved.
    private static func demo(jobs: [Job], now: Date) -> [HomePlanItem] {
        let cal = PWAPlan.calendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let rows: [(Int, Int, PWAPlan.JobType, String, String, Double)] = [
            (0, 8 * 60, .install, "MP 133 บางปะกง — 2.3 ติดตั้งแผงเซลล์", "ผู้รับเหมา A · 120.5 kWp · ตามแผน", 0.55),
            (0, 13 * 60 + 30, .test, "MP 77 โชคชัย — 3.1 Pre-Commissioning (IEC 62446)", "ทีม TC · 171 kWp", 0.94),
            (1, 10 * 60, .document, "MP 154 แพรกหนามแดง — ยื่นขอขนานไฟ กฟภ.", "สำนักงาน กฟภ. จ.สมุทรสงคราม", 0.71),
        ]
        return zip(jobs, rows).enumerated().map { i, pair in
            let (job, r) = pair
            return HomePlanItem(id: "demo-plan-\(i)", type: r.2, day: cal.date(byAdding: .day, value: r.0, to: tomorrow) ?? tomorrow,
                                start: r.1, name: r.3, place: r.4, progress: r.5, job: job)
        }
    }
    #endif

    /// This item as a page of the hero card. The button follows the type; an IEC test has no form of its own, so it
    /// opens the station, as the PWA plan page's test rows do.
    @MainActor func heroItem(now: Date, report: TCRoofCore.Job?, open: @escaping (FeedLink) -> Void) -> HeroItem {
        let key = job.feedKey
        let title: String, link: FeedLink
        switch type {
        case .test: (title, link) = ("เปิดฟอร์มทดสอบ ›", .job(key))
        case .document: (title, link) = ("ดูเอกสาร ›", .stationDocs(job: key))
        default: (title, link) = ("ดูแผนงาน ›", .calendar(day))
        }
        let typeTitle = type == .document ? "ยื่นเอกสาร" : type.title
        return HeroItem(id: id, time: start.map(PWAPlan.clock) ?? "ทั้งวัน", kind: "\(typeTitle) · \(PWAPlan.ahead(day, from: now))",
                        name: name, place: place, fraction: progress, percent: Int((progress * 100).rounded()),
                        actionTitle: title, date: day, appointment: TodayAppointment(job: job, report: report)) { open(link) }
    }
}

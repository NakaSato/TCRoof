import SwiftUI
import TCRoofUI
import TCRoofCore

/// The install tracking page's `รายงานประจำวัน` tab (docs/ui/install-tracking-ipad §D): the KPI row, every working day's
/// report (the days `DailyReportListView` lists) and the four cards under the table. Made from the job, or the board's
/// example with `-installDemo YES`. The board's weather forecast and the `x/4` photo quota have no source and are left out.
struct InstallDailyData {
    enum State { case today, missing, draft, signed, stopped }

    struct Row: Identifiable {
        let date: Date
        let state: State
        let weather: RoutineReport.Weather?
        let rainHours: Int
        let crew: Int?
        let work: String
        /// Cumulative actual and planned %, from the MP plan; nil without one.
        let actual: Double?
        let planned: Double?
        let photos: Int
        let signedAt: Date?
        let ackAt: Date?
        let problem: String
        var id: Date { date }

        var needsWork: Bool { state == .today || state == .missing || state == .draft }
        var hasProblem: Bool { !problem.isEmpty }
    }

    /// A day of `ความก้าวหน้าสะสม`.
    struct Point: Identifiable {
        let date: Date
        let actual: Double?
        let planned: Double
        var id: Date { date }
    }

    /// A line of `พรุ่งนี้`: an MP task planned for that day and where it stands.
    struct Next: Identifiable {
        let id: String
        let code: String
        let title: String
        let percent: Double
    }

    var rows: [Row] = []
    var today: Date
    var todayWorking = true
    /// Today falls inside the install window.
    var inWindow = true
    /// Signed reports over working days, through yesterday.
    var sentThroughYesterday = 0
    var workingThroughYesterday = 0
    var drafts: [Date] = []
    var unacknowledged: [Date] = []
    /// The site's working day ends, as `hh.mm`.
    var workEnd = "17.00"
    var manDays = 0
    var workedDays = 0
    /// Days stopped with rain and no progress, and the rain hours over all reports.
    var rainStops = 0
    var rainHours = 0
    var points: [Point] = []
    /// Photos tagged to each MP install task.
    var photosByTask: [(code: String, title: String, count: Int)] = []
    var nextDay: Date?
    var next: [Next] = []
    /// The R3 week of the newest report, with its report count, for `สร้าง Weekly Report Wnn จาก n รายงาน`.
    var week: (number: Int, reports: Int)?
    var hasReports: Bool { rows.contains { $0.state != .today && $0.state != .missing } }

    init(today: Date) { self.today = today }

    @MainActor init(job: Job, today now: Date = .now) {
        let cal = RoutineReport.calendar, day = cal.startOfDay(for: now), settings = job.routineSettings
        today = day
        workEnd = String(format: "%02d.%02d", settings.workEnd / 60, settings.workEnd % 60)
        inWindow = job.installDay(on: day) != nil
        todayWorking = RoutineReport.isWorkingDay(day, settings: settings) && inWindow

        let plan = job.scheduleInput.map { MasterSchedule.plan($0) }, actual = job.scheduleActual
        // the days of DailyReportListView: working days from the start to today, and any day with a report
        let logs = job.dailyLogs
        let start = cal.startOfDay(for: min(logs.first?.date ?? job.installStart, job.installStart))
        let end = min(day, max(cal.startOfDay(for: job.installEnd), logs.last.map { cal.startOfDay(for: $0.date) } ?? start))
        let worked = start <= end ? RoutineReport.workingDays(settings: settings, from: start, to: end) : []
        let days = Array(Set(worked + logs.map { cal.startOfDay(for: $0.date) })).sorted(by: >)
        let all = job.dailyReports
        // looked up once: `job.dailyLog(on:)` fetches and sorts every log on each call
        let logByDay = Dictionary(logs.map { (RoutineReport.dayKey($0.date), $0) }, uniquingKeysWith: { a, _ in a })
        // the plan's status only changes by the week (planned to the week's start, done to the week's key)
        var weekStatus: [String: MasterSchedule.Status] = [:]
        func status(_ d: Date) -> MasterSchedule.Status? {
            guard let plan else { return nil }
            let k = MasterSchedule.Actual.key(d)
            if let s = weekStatus[k] { return s }
            let s = MasterSchedule.status(plan: plan, actual: actual, through: d)
            weekStatus[k] = s
            return s
        }

        rows = days.map { d in
            let log = logByDay[RoutineReport.dayKey(d)], r = log?.report
            let status = status(d)
            let state: State
            if let log, let r {
                state = log.engineerSignedAt == nil ? .draft : r.progress.isEmpty && !r.stopReason.isEmpty ? .stopped : .signed
            } else {
                state = d == day ? .today : .missing
            }
            let weather = r.flatMap { r in Dictionary(grouping: r.weather.compactMap { $0 }, by: { $0 }).max { $0.value.count < $1.value.count }?.key }
            var problem = r?.problems.filter { !$0.closed && !$0.description.isEmpty }.map(\.description).joined(separator: " · ") ?? ""
            if state == .draft {
                let w = RoutineReport.warnings(r!, previous: all.filter { $0.date < d })
                problem = (["ร่างยังไม่ลงนาม"] + w.prefix(1).map(\.text) + (problem.isEmpty ? [] : [problem])).joined(separator: " · ")
            }
            let work: String = switch state {
            case .today: "ยังไม่ได้ทำรายงานวันนี้"
            case .missing: "ไม่มีรายงาน"
            case .stopped: "หยุดงาน: " + (r?.stopReason ?? "")
            default: r.map { $0.progress.isEmpty ? "ไม่มีงานที่บันทึก" : $0.progress.map(\.title).joined(separator: " · ") } ?? ""
            }
            return Row(date: d, state: state, weather: weather, rainHours: r?.rainHours ?? 0, crew: r.flatMap { $0.crewTotal > 0 ? $0.crewTotal : nil },
                       work: work, actual: status?.actual, planned: status?.planned, photos: log?.photos.count ?? 0,
                       signedAt: log?.engineerSignedAt, ackAt: log?.inspectorAckAt, problem: problem)
        }

        let past = rows.filter { $0.date < day }
        workingThroughYesterday = past.filter { RoutineReport.isWorkingDay($0.date, settings: settings) }.count
        sentThroughYesterday = past.filter { $0.signedAt != nil }.count
        drafts = rows.filter { $0.state == .draft }.map(\.date)
        unacknowledged = rows.filter { $0.signedAt != nil && $0.ackAt == nil }.map(\.date)
        let reports = all.filter { cal.startOfDay(for: $0.date) <= day }
        manDays = reports.reduce(0) { $0 + $1.crewTotal }
        workedDays = reports.filter { $0.crewTotal > 0 }.count
        rainStops = reports.filter { $0.progress.isEmpty && $0.rainHours > 0 }.count
        rainHours = reports.reduce(0) { $0 + $1.rainHours }

        if let plan {
            points = RoutineReport.workingDays(settings: settings, from: cal.startOfDay(for: job.installStart), to: cal.startOfDay(for: job.installEnd)).map { d in
                guard let s = status(d) else { return Point(date: d, actual: nil, planned: 0) }
                return Point(date: d, actual: d <= day ? s.actual : nil, planned: s.planned)
            }
            // tomorrow: the next working day and the install tasks planned on it
            var t = cal.date(byAdding: .day, value: 1, to: day) ?? day
            for _ in 0..<14 where !RoutineReport.isWorkingDay(t, settings: settings) { t = cal.date(byAdding: .day, value: 1, to: t) ?? t }
            nextDay = t
            next = plan.compactMap { p in
                guard p.task.part != .permit, p.weight > 0, let s = p.start, let e = p.end, cal.startOfDay(for: s) <= t, t <= cal.startOfDay(for: e) else { return nil }
                let pct = min(max(actual.done(p.task, through: day) / p.weight * 100, 0), 100)
                return Next(id: p.task.rawValue, code: p.task.code, title: p.task.title, percent: pct)
            }
        }

        // photos tagged to a progress line, by its MP task
        var counts: [MasterSchedule.Task: Int] = [:]
        for log in logs {
            guard let r = log.report else { continue }
            let lineTask = Dictionary(r.progress.compactMap { l in l.task.map { (l.id.uuidString, $0) } }) { a, _ in a }
            for p in log.photos { if let t = lineTask[p.tag] { counts[t, default: 0] += 1 } }
        }
        photosByTask = MasterSchedule.Task.allCases.filter { $0.part != .permit && (counts[$0] ?? 0) > 0 }
            .map { ($0.code, $0.title, counts[$0] ?? 0) }

        if let newest = reports.last {
            let w = RoutineReport.week(of: newest.date)
            week = (Calendar(identifier: .iso8601).component(.weekOfYear, from: w.upperBound),
                    reports.filter { w.contains(cal.startOfDay(for: $0.date)) }.count)
        }
    }
}

#if DEBUG
extension InstallDailyData {
    /// The board's example: six days from its 24/9 start, today (30/9) not sent.
    static func demo(today now: Date = .now) -> InstallDailyData {
        let day = RoutineReport.calendar.startOfDay(for: now)
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        var x = InstallDailyData(today: day)
        x.rows = [
            Row(date: d(6), state: .today, weather: .fine, rainHours: 0, crew: nil, work: "ยังไม่ได้ทำรายงานวันนี้", actual: nil, planned: 52,
                photos: 0, signedAt: nil, ackAt: nil, problem: ""),
            Row(date: d(5), state: .draft, weather: .cloudy, rainHours: 0, crew: 7, work: "เดินสายสตริง 1–6 (โซน A) (หลังคา → ตู้ DC)", actual: 47, planned: 44,
                photos: 2, signedAt: nil, ackAt: nil, problem: "ร่างยังไม่ลงนาม · ขาดรูป 2 รูป"),
            Row(date: d(4), state: .signed, weather: .fine, rainHours: 0, crew: 9, work: "ติดตั้งแผงเซลล์แสงอาทิตย์ 164 แผง (หลังคา 1–3)", actual: 40, planned: 36,
                photos: 4, signedAt: d(4), ackAt: nil, problem: ""),
            Row(date: d(3), state: .stopped, weather: .rain, rainHours: 8, crew: nil, work: "หยุดงาน: ฝนตกทั้งช่วงทำงาน", actual: 20, planned: 26,
                photos: 0, signedAt: d(3), ackAt: d(4), problem: "ฝนตกทั้งช่วงทำงาน · แนวทางเร่งงานวันจันทร์"),
            Row(date: d(2), state: .signed, weather: .fine, rainHours: 0, crew: 8, work: "ติดตั้งรางยึดแผง ซีลกันรั่วจุดยึด (หลังคา แถว 7–12)", actual: 20, planned: 18,
                photos: 4, signedAt: d(2), ackAt: nil, problem: ""),
            Row(date: d(1), state: .signed, weather: .cloudy, rainHours: 0, crew: 8, work: "ติดตั้งรางยึดแผง (หลังคา แถว 1–6)", actual: 12, planned: 10,
                photos: 3, signedAt: d(1), ackAt: d(2), problem: ""),
            Row(date: d(0), state: .signed, weather: .fine, rainHours: 0, crew: 6, work: "รับวัสดุเข้าหน้างาน ตรวจนับตามใบส่งของ", actual: 5, planned: 4,
                photos: 2, signedAt: d(0), ackAt: d(1), problem: "")]
        x.sentThroughYesterday = 4; x.workingThroughYesterday = 6
        x.drafts = [d(5)]; x.unacknowledged = [d(2), d(4)]
        x.workEnd = "18.00"; x.manDays = 38; x.workedDays = 5; x.rainStops = 1; x.rainHours = 8
        let plan: [Double] = [4, 10, 18, 26, 36, 44, 52, 60, 70, 80, 90, 100]
        let actual: [Double] = [5, 12, 20, 20, 40, 47]
        x.points = plan.indices.map { Point(date: d($0), actual: $0 < actual.count ? actual[$0] : nil, planned: plan[$0]) }
        x.photosByTask = [("2.1", "โครงสร้าง + ราง", 7), ("2.2", "ระบบไฟฟ้า DC", 2), ("2.3", "แผงเซลล์", 4)]
        x.nextDay = d(7)
        x.next = [Next(id: "dc", code: "2.2", title: "เดินสายสตริง 7–12 (ต่อจากวันนี้)", percent: 50),
                  Next(id: "box", code: "2.2", title: "ติดตั้งตู้ DC combiner", percent: 50),
                  Next(id: "inv", code: "2.5", title: "ยึดอินเวอร์เตอร์ 2 ตัว", percent: 0)]
        x.week = (40, 6)
        return x
    }
}
#endif

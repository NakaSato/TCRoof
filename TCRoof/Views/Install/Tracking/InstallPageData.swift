import SwiftUI
import TCRoofUI
import TCRoofCore

/// What the iPad install tracking page shows of one station (docs/ui/install-tracking-ipad): the header's lines, where
/// it stands against its MP plan, and the open items. Made from the job, or the board's example with `-installDemo YES`.
struct InstallPageData {
    enum Priority { case high, medium }
    /// A screen an open item leads to.
    enum Target: Hashable { case daily, request, docs, plan, weekly, day(Date) }

    struct Action: Identifiable {
        let id: String
        let priority: Priority
        let title: String
        let detail: String
        let target: Target
    }

    var title: String
    var subtitle: String
    /// nil without an MP plan: the strip then shows only what doesn't need one.
    var tracking: InstallTracking?
    var actions: [Action]
    /// Today is a working day and its daily report isn't signed: the dot on `รายงานประจำวัน`.
    var dailyUnsent: Bool
    /// The station's NO.224 survey report, opened read-only from the header.
    var surveyReport: UUID?
    /// `ความคืบหน้าเทียบแผน`: the MP plan's install tasks, and the station's S-curve. nil without a plan.
    var gantt: InstallGantt?
    var curve: PWAPlan.Curve?
    /// Days in the Gantt's span that are not working days (hatched).
    var nonWorking: Set<Date> = []
    /// `เอกสารโครงการ` and the site panel (§C).
    var docs: [DocTile] = []
    var site: Site?

    init(title: String, subtitle: String, tracking: InstallTracking?, actions: [Action], dailyUnsent: Bool, surveyReport: UUID?,
         gantt: InstallGantt? = nil, curve: PWAPlan.Curve? = nil, nonWorking: Set<Date> = []) {
        self.title = title; self.subtitle = subtitle; self.tracking = tracking; self.actions = actions
        self.dailyUnsent = dailyUnsent; self.surveyReport = surveyReport
        self.gantt = gantt; self.curve = curve; self.nonWorking = nonWorking
    }

    @MainActor init(job: Job, survey: SurveyModel, today: Date = .now) {
        let report = job.syncID.flatMap { survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        let ref = report.map(\.docNo).flatMap { $0.isEmpty ? nil : "NO.\($0)" } ?? job.mpNumber.map { "MP \($0)" }
        let site = job.customerName.trimmingCharacters(in: .whitespaces)
        let kWp = job.capacityKW.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        let parts: [String?] = [ref.map { "งานติดตั้ง " + $0 } ?? "งานติดตั้ง", site.isEmpty || site == job.projectName ? nil : site,
                                job.capacityKW > 0 ? kWp + " kWp" : nil, "ทีม " + job.team.rawValue,
                                "เริ่ม " + ThaiFormat.numericDate.string(from: job.installStart),
                                "ส่งมอบ " + ThaiFormat.numericDate.string(from: job.installEnd)]
        title = job.stationName
        subtitle = parts.compactMap { $0 }.joined(separator: " · ")
        surveyReport = report?.id

        if let input = job.scheduleInput {
            let plan = MasterSchedule.plan(input), actual = job.scheduleActual
            let now = MasterSchedule.status(plan: plan, actual: actual, through: today)
            let weekAgo = MasterSchedule.status(plan: plan, actual: actual, through: today.adding(days: -7))
            tracking = InstallTracking(actual: now.actual, planned: now.planned, actualWeekAgo: weekAgo.actual,
                                       start: job.installStart, due: job.installEnd, today: today)
            let g = InstallGantt(plan: plan, actual: actual,
                                 places: RoutineReport.places(reports: job.dailyReports, through: today, settings: job.routineSettings), today: today)
            gantt = g.rows.isEmpty ? nil : g
            curve = PWAPlan.curve([job.planStation], today: today)
        } else {
            tracking = nil
        }

        let cal = RoutineReport.calendar, day = cal.startOfDay(for: today)
        let settings = job.routineSettings
        if let span = gantt?.span() {
            var d = span.lowerBound
            while d <= span.upperBound {
                if !RoutineReport.isWorkingDay(d, settings: settings) { nonWorking.insert(cal.startOfDay(for: d)) }
                d = cal.date(byAdding: .day, value: 1, to: d) ?? span.upperBound.addingTimeInterval(1)
            }
        }
        let working = RoutineReport.isWorkingDay(day, settings: settings) && job.installDay(on: day) != nil
        dailyUnsent = working && job.dailyState(on: day) != .signed

        var items: [Action] = []
        if let input = job.scheduleInput {
            let permits = RoutineReport.permits(plan: MasterSchedule.plan(input), actual: job.scheduleActual, at: today)
            let late = (InstallOverview.permits(permits) ?? []).filter { $0.state == .overdue }
            if !late.isEmpty {
                items.append(.init(id: "permits", priority: .high, title: "ใบอนุญาตเลยกำหนด " + late.map { $0.authority.title }.joined(separator: " · "),
                                   detail: "ตามแผน MP · เปิดแผนก่อสร้าง", target: .plan))
            }
        }
        if dailyUnsent {
            items.append(.init(id: "daily", priority: .medium, title: "รายงานประจำวัน " + ThaiFormat.dayMonth.string(from: day),
                               detail: job.dailyState(on: day) == .draft ? "ร่างไว้ · ยังไม่ลงนาม" : "ยังไม่ได้ทำ", target: .daily))
        }
        let nextWeek = cal.date(byAdding: .day, value: 7, to: RoutineReport.week(of: day).lowerBound) ?? day
        if job.scheduleInput != nil, job.weeklyRequest(for: nextWeek)?.engineerSignedAt == nil {
            items.append(.init(id: "request", priority: .medium, title: "คำขอสัปดาห์หน้า", detail: "ยังไม่ลงนาม", target: .request))
        }
        let waiting = job.papersWaitingToSend
        if waiting > 0 {
            items.append(.init(id: "docs", priority: .medium, title: "เอกสารรอยื่น \(waiting) ฉบับ", detail: "ลงนามแล้ว · ยังไม่ส่ง", target: .docs))
        }
        actions = items
        docs = Self.docTiles(job: job, today: today)
        self.site = Self.site(job: job, gantt: gantt, today: today)
    }
}

#if DEBUG
extension InstallPageData {
    /// `-installDemo YES`: the board's example (บ้านโป่ง, today 30/9 of 24/9 – 6/10), for screenshots only.
    static func demo(today: Date = .now) -> InstallPageData {
        let cal = Calendar.current, day = cal.startOfDay(for: today)
        let start = day.adding(days: -6), due = day.adding(days: 6)
        let ac = Action(id: "ac", priority: .high, title: "ตู้ AC · กันย้อน รออนุมัติ (MA-05)", detail: "ต้องได้ก่อนขั้น 5 · ผู้รับผิดชอบ: จัดซื้อ", target: .docs)
        let wr = Action(id: "wr", priority: .medium, title: "Weekly Report W40 (WR-02)", detail: "ร่างอัตโนมัติพร้อมแล้ว", target: .weekly)
        let rfi = Action(id: "rfi", priority: .medium, title: "ยื่น RFI-03 ตรวจรับงานสาย DC", detail: "ยื่นได้เมื่อรายการตรวจขั้น 4 ครบ", target: .docs)
        let daily = Action(id: "daily", priority: .medium, title: "รายงานประจำวัน", detail: "ยังไม่ได้ทำ", target: .daily)
        // the board's seven steps: days from its 24/9 start, today is day 6
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        typealias Sub = InstallGantt.Sub
        let rows: [InstallGantt.Row] = [
            .init(id: "s1", code: "1", title: "ส่งวัสดุเข้าหน้างาน", status: .done, start: d(0), end: d(0), actualStart: d(0), actualEnd: d(0), percent: 100,
                  subs: ["แผงโซลาร์ 164 แผง", "ราง · แคลมป์ · อุปกรณ์ยึด", "อินเวอร์เตอร์ · ตู้ไฟฟ้า"].map { Sub($0, percent: 100, start: d(0), end: d(0)) }),
            .init(id: "s2", code: "2", title: "ติดตั้งโครงสร้างราง", status: .done, start: d(1), end: d(2), actualStart: d(1), actualEnd: d(2), percent: 100,
                  subs: [Sub("โซน A อาคารผลิต · แถว A1–A4", percent: 100, start: d(1), end: d(1)), Sub("โซน B อาคารสูบน้ำ · แถว B1–B4", percent: 100, start: d(1), end: d(2)),
                         Sub("โซน C โรงเก็บสารเคมี", percent: 100, start: d(2), end: d(2)), Sub("ซีลกันรั่วจุดยึดทุกโซน", percent: 100, start: d(2), end: d(2))]),
            .init(id: "s3", code: "3", title: "ติดตั้งแผงโซลาร์", status: .done, start: d(3), end: d(4), actualStart: d(3), actualEnd: d(4), percent: 100,
                  subs: [Sub("โซน A · 64 แผง", percent: 100, start: d(3), end: d(3)), Sub("โซน B · 60 แผง", percent: 100, start: d(3), end: d(4)),
                         Sub("โซน C · 40 แผง", percent: 100, start: d(4), end: d(4)), Sub("สายดินโครงแผงทุกโซน", percent: 100, start: d(4), end: d(4))]),
            .init(id: "s4", code: "4", title: "เดินสาย DC · ตู้ DC", status: .current, start: d(5), end: d(7), actualStart: d(5), actualEnd: d(6), percent: 50,
                  forecastEnd: d(8), overrunDays: 1,
                  subs: [Sub("เดินสายสตริง 1–6 (โซน A)", percent: 100, start: d(5), end: d(5)), Sub("เดินสายสตริง 7–12 (โซน B, C)", percent: 100, start: d(6), end: d(6)),
                         Sub("ติดตั้งตู้ DC combiner", percent: 100, start: d(6), end: d(6)), Sub("วัด Voc / Isc ทุกสตริง", percent: 0, start: d(7), end: d(7)),
                         Sub("ติดป้ายเตือนสาย DC", percent: 0, start: d(7), end: d(7))]),
            .init(id: "s5", code: "5", title: "ติดตั้งอินเวอร์เตอร์ · ตู้ AC", status: .waiting, start: d(8), end: d(8), percent: 0,
                  subs: ["ยึดอินเวอร์เตอร์", "เดินสาย AC เข้าตู้ MDB", "ติดตั้งกันย้อน", "ต่อสายดินระบบ"].map { Sub($0, percent: 0, start: d(8), end: d(8)) }),
            .init(id: "s6", code: "6", title: "ทดสอบระบบ", status: .waiting, start: d(9), end: d(9), percent: 0,
                  subs: ["วัดค่าฉนวน", "ค่าความต้านทานดิน", "ทดสอบ Anti-islanding", "ทดสอบผลิตไฟจริง"].map { Sub($0, percent: 0, start: d(9), end: d(9)) }),
            .init(id: "s7", code: "7", title: "ขนานไฟ · ส่งมอบ", status: .waiting, start: d(12), end: d(12), percent: 0,
                  subs: ["การไฟฟ้าตรวจและขนานไฟ", "อบรมผู้ใช้งาน", "ส่งเอกสาร As-built · ใบรับประกัน"].map { Sub($0, percent: 0, start: d(12), end: d(12)) })]
        // the plan's weeks from the start to the handover, and the actual to this week
        let weeks = (-1...1).map { MasterSchedule.weekStart(day.adding(days: 7 * $0)) }
        let curve = PWAPlan.Curve(weeks: weeks, plan: [0, 52, 100], actual: [0, 50], todayIndex: 1, planned: 52, done: 50)
        var data = InstallPageData(
            title: "การประปาบ้านโป่ง (ตัวอย่าง)",
            subtitle: "งานติดตั้ง NO.098 · สถานีจ่ายน้ำบ้านโป่ง · 90 kWp · ทีม TCR02 · เริ่ม \(ThaiFormat.numericDate.string(from: start)) · ส่งมอบ \(ThaiFormat.numericDate.string(from: due))",
            tracking: InstallTracking(actual: 50, planned: 52, actualWeekAgo: 36, start: start, due: due, today: day),
            actions: [ac, wr, rfi, daily], dailyUnsent: true, surveyReport: nil,
            gantt: InstallGantt(rows: rows, today: day), curve: curve, nonWorking: [d(10), d(11)])
        data.docs = demoTiles(day: day)
        data.site = demoSite(day: day)
        return data
    }
}
#endif

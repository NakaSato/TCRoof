import SwiftUI
import TCRoofUI
import TCRoofCore

/// What the iPad install tracking page shows of one station (docs/ui/install-tracking-ipad): the header's lines, where
/// it stands against its MP plan, and the open items. Made from the job, or the board's example with `-installDemo YES`.
struct InstallPageData {
    enum Priority { case high, medium }
    /// A screen an open item leads to.
    enum Target: Hashable { case daily, request, docs, plan, weekly, day(Date), iec, devices }

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
    /// `ความคืบหน้าเทียบแผน`: the MP plan's install tasks. nil without a plan.
    var gantt: InstallGantt?
    /// The S-curve by day over the Gantt's span: cumulative plan and actual (to today).
    var curveDays: [CurveDay] = []
    /// Days in the Gantt's span that are not working days (hatched).
    var nonWorking: Set<Date> = []
    /// What the hatched days wait on (`รอการไฟฟ้านัดตรวจ`); the app keeps no such days, so only the board's example has it.
    var waitLabel: String?
    /// `แผนก่อสร้าง`: nil without an MP plan.
    var plan: InstallPlan?

    struct CurveDay: Identifiable {
        let date: Date
        let planned: Double
        let actual: Double?
        var id: Date { date }
    }
    /// `เอกสารโครงการ` and the site panel (§C).
    var docs: [DocTile] = []
    var site: Site?

    init(title: String, subtitle: String, tracking: InstallTracking?, actions: [Action], dailyUnsent: Bool, surveyReport: UUID?,
         gantt: InstallGantt? = nil, nonWorking: Set<Date> = []) {
        self.title = title; self.subtitle = subtitle; self.tracking = tracking; self.actions = actions
        self.dailyUnsent = dailyUnsent; self.surveyReport = surveyReport
        self.gantt = gantt; self.nonWorking = nonWorking
    }

    @MainActor init(job: Job, survey: SurveyModel, today: Date = .now) {
        let report = job.syncID.flatMap { survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        // the station's name is the title, so the line starts with the size
        let kWp = job.capacityKW.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        let parts: [String?] = [job.capacityKW > 0 ? "งานติดตั้ง " + kWp + " kWp" : "งานติดตั้ง", "ทีม " + job.team.rawValue,
                                "เริ่ม " + ThaiFormat.numericDate.string(from: job.installStart),
                                "ส่งมอบ " + ThaiFormat.numericDate.string(from: job.installEnd)]
        title = job.stationName
        subtitle = parts.compactMap { $0 }.joined(separator: " | ")
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
            if let span = gantt?.span() {
                // the MP plan books points by week, so one status a week serves its days
                var byWeek: [Date: MasterSchedule.Status] = [:]
                var d = span.lowerBound
                while d <= span.upperBound {
                    let w = MasterSchedule.weekStart(d)
                    let s = byWeek[w] ?? MasterSchedule.status(plan: plan, actual: actual, through: d)
                    byWeek[w] = s
                    curveDays.append(CurveDay(date: d, planned: s.planned, actual: d <= MasterSchedule.calendar.startOfDay(for: today) ? s.actual : nil))
                    d = MasterSchedule.calendar.date(byAdding: .day, value: 1, to: d) ?? span.upperBound.addingTimeInterval(1)
                }
            }
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
        let todayState = job.dailyState(on: day)
        dailyUnsent = working && todayState != .signed

        var items: [Action] = []
        if let input = job.scheduleInput {
            let permits = RoutineReport.permits(plan: MasterSchedule.plan(input), actual: job.scheduleActual, at: today)
            let late = (InstallOverview.permits(permits) ?? []).filter { $0.state == .overdue }
            if !late.isEmpty {
                items.append(.init(id: "permits", priority: .high, title: "ใบอนุญาตเลยกำหนด " + late.map { $0.authority.title }.joined(separator: " | "),
                                   detail: "ตามแผน MP | เปิดแผนก่อสร้าง", target: .plan))
            }
        }
        if dailyUnsent {
            items.append(.init(id: "daily", priority: .medium, title: "รายงานประจำวัน " + ThaiFormat.dayMonth.string(from: day),
                               detail: todayState == .draft ? "ร่างไว้ | ยังไม่ลงนาม" : "ยังไม่ได้ทำ", target: .daily))
        }
        let nextWeek = cal.date(byAdding: .day, value: 7, to: RoutineReport.week(of: day).lowerBound) ?? day
        if job.scheduleInput != nil, job.weeklyRequest(for: nextWeek)?.engineerSignedAt == nil {
            items.append(.init(id: "request", priority: .medium, title: "คำขอสัปดาห์หน้า", detail: "ยังไม่ลงนาม", target: .request))
        }
        let waiting = job.papersWaitingToSend
        if waiting > 0 {
            items.append(.init(id: "docs", priority: .medium, title: "เอกสารรอยื่น \(waiting) ฉบับ", detail: "ลงนามแล้ว | ยังไม่ส่ง", target: .docs))
        }
        actions = items
        docs = Self.docTiles(job: job, today: today)
        self.site = Self.site(job: job, gantt: gantt, today: today)
        if let g = gantt, let input = job.scheduleInput {
            let tasks = Dictionary(MasterSchedule.plan(input).map { ($0.task, $0) }) { a, _ in a }
            var milestones = [InstallPlan.Milestone(title: "เริ่มงานหน้างาน", date: job.installStart)]
            if let pre = tasks[.preCommissioning]?.start { milestones.append(.init(title: "ทดสอบระบบ (Pre-Commissioning)", date: pre)) }
            milestones.append(.init(title: "ส่งมอบ", date: job.installEnd))
            // the weekly requests' planned crew; the plan itself keeps no crew
            let crew = Dictionary((site?.labour ?? []).compactMap { l in l.plan.map { (cal.startOfDay(for: l.date), $0) } }) { a, _ in a }
            var p = InstallPlan(gantt: g, nonWorking: nonWorking, tracking: tracking, milestones: milestones, crew: crew)
            // a plan from a plan file shows its WBS sub-tasks under each stage, in place of the reports' places
            let wbs = job.scheduleWBS
            if !wbs.isEmpty { p.useWBS(wbs, ticked: Set(job.wbsTicks.keys)) }
            plan = p
        }
    }
}

#if DEBUG
extension InstallPageData {
    /// `-installDemo YES`: the board's example (บ้านโป่ง, today 30/9 of 24/9 – 6/10), for screenshots only. `late` puts
    /// the running stage further behind (docs/ui/install-tracking-iphone state 02).
    static func demo(today: Date = .now, late: Bool = false) -> InstallPageData {
        let cal = Calendar.current, day = cal.startOfDay(for: today)
        let start = day.adding(days: -6), due = day.adding(days: 6)
        let ac = Action(id: "ac", priority: .high, title: "ตู้ AC | กันย้อน รออนุมัติ (MA-05)", detail: "ต้องได้ก่อนขั้น 5 | ผู้รับผิดชอบ: จัดซื้อ", target: .docs)
        let wr = Action(id: "wr", priority: .medium, title: "Weekly Report W40 (WR-02)", detail: "ร่างอัตโนมัติพร้อมแล้ว", target: .weekly)
        let rfi = Action(id: "rfi", priority: .medium, title: "ยื่น RFI-03 ตรวจรับงานสาย DC", detail: "ยื่นได้เมื่อรายการตรวจขั้น 4 ครบ", target: .docs)
        let daily = Action(id: "daily", priority: .medium, title: "รายงานประจำวัน", detail: "ยังไม่ได้ทำ", target: .daily)
        // the board's seven stages and 34 sub-tasks: days from its 24/9 start, today is day 6
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        typealias Sub = InstallGantt.Sub
        func subs(_ list: [(String, Int, Int)], percent: (Int) -> Double) -> [Sub] {
            list.enumerated().map { k, u in Sub(u.0, percent: percent(k), start: d(u.1), end: d(u.2)) }
        }
        let rows: [InstallGantt.Row] = [
            .init(id: "s1", code: "1", title: "เตรียมงาน | รับวัสดุ", status: .done, start: d(0), end: d(0), actualStart: d(0), actualEnd: d(0), percent: 100,
                  subs: subs([("ปฐมนิเทศ | ใบอนุญาตที่สูง", 0, 0), ("Lifeline | ราวกันตก", 0, 0), ("ตรวจรับวัสดุตามใบส่งของ", 0, 0),
                              ("กองวัสดุ | ป้ายกั้นพื้นที่", 0, 0)]) { _ in 100 }),
            .init(id: "s2", code: "2", title: "โครงสร้างรองรับ (Mounting)", status: .done, start: d(1), end: d(2), actualStart: d(1), actualEnd: d(2), percent: 100,
                  subs: subs([("มาร์กจุดยึดตามแบบ", 1, 1), ("L-Feet + ซีลกันรั่ว โซน A–B", 1, 1), ("L-Feet + ซีลกันรั่ว โซน C", 2, 2),
                              ("ติดตั้งรางและต่อราง", 1, 2), ("ตรวจระดับ | ขันแรงบิด", 2, 2)]) { _ in 100 }),
            .init(id: "s3", code: "3", title: "ติดตั้งแผง | สายดินโครง", status: .done, start: d(3), end: d(4), actualStart: d(3), actualEnd: d(4), percent: 100,
                  subs: subs([("ยกแผงขึ้นหลังคา", 3, 3), ("แผงโซน A | 64 แผง", 3, 3), ("แผงโซน B | 60 แผง", 3, 4), ("แผงโซน C | 40 แผง", 4, 4),
                              ("สายดินโครงและแผง", 4, 4)]) { _ in 100 }),
            .init(id: "s4", code: "4", title: "ระบบ DC | สาย | MC4 | ตู้ DC", status: .current, start: d(5), end: d(7), actualStart: d(5), actualEnd: d(6),
                  percent: late ? 30 : 50, forecastEnd: d(late ? 10 : 8), overrunDays: late ? 3 : 1,
                  subs: subs([("สายสตริง 1–6 (โซน A)", 5, 5), ("สายสตริง 7–12 (โซน B, C)", 6, 6), ("ย้ำหัว MC4 | ตู้ DC", 6, 6),
                              ("ตรวจขั้ว | วัด Voc ทุกสตริง", 7, 7), ("ป้ายเตือน | ป้ายสาย DC", 7, 7)]) { $0 < (late ? 1 : 3) ? 100 : $0 == 1 && late ? 40 : 0 }),
            .init(id: "s5", code: "5", title: "อินเวอร์เตอร์ | ระบบ AC", status: .waiting, start: d(8), end: d(8), percent: 0,
                  subs: subs([("ยึดอินเวอร์เตอร์", 8, 8), ("สาย AC เข้า MDB | เบรกเกอร์", 8, 8), ("กันย้อน (Zero Export) + CT", 8, 8),
                              ("ระบบดิน | วัดค่าดิน", 8, 8), ("Data Logger | Monitoring", 8, 8)]) { _ in 0 }),
            .init(id: "s6", code: "6", title: "ทดสอบ IEC 62446-1", status: .waiting, start: d(9), end: d(9), percent: 0,
                  subs: subs([("ตรวจพินิจ (Visual)", 9, 9), ("Continuity | Polarity | Voc/Isc", 9, 9), ("ฉนวน (IR) 1000 V", 9, 9),
                              ("Anti-islanding | อินเวอร์เตอร์", 9, 9), ("เปิดระบบ | ภาพความร้อน", 9, 9)]) { _ in 0 }),
            .init(id: "s7", code: "7", title: "ขนานไฟ | ส่งมอบ", status: .waiting, start: d(12), end: d(12), percent: 0,
                  subs: subs([("การไฟฟ้าตรวจ | เปลี่ยนมิเตอร์", 12, 12), ("ขนานไฟ | ตรวจค่าผลิต", 12, 12), ("อบรมผู้ใช้ | คู่มือ O&M", 12, 12),
                              ("As-built | รายงาน IEC | ประกัน", 12, 12), ("Punch List | ลงนามรับมอบ", 12, 12)]) { _ in 0 })]
        var data = InstallPageData(
            title: "การประปาบ้านโป่ง (ตัวอย่าง)",
            subtitle: "งานติดตั้ง 90 kWp | ทีม TCR02 | เริ่ม \(ThaiFormat.numericDate.string(from: start)) | ส่งมอบ \(ThaiFormat.numericDate.string(from: due))",
            tracking: InstallTracking(actual: late ? 41 : 50, planned: 52, actualWeekAgo: late ? 33 : 36, start: start, due: due, today: day),
            actions: [ac, wr, rfi, daily], dailyUnsent: true, surveyReport: nil,
            gantt: InstallGantt(rows: rows, today: day), nonWorking: [d(10), d(11)])
        data.docs = demoTiles(day: day)
        data.site = demoSite(day: day)
        // the board's cumulative plan and actual by day, flat over the two days waiting on the utility
        let planned: [Double] = [4, 10, 18, 26, 36, 44, 52, 60, 70, 85, 85, 85, 100], actual: [Double] = late ? [5, 12, 18, 18, 30, 36, 41] : [5, 12, 20, 20, 40, 47, 50]
        data.curveDays = planned.indices.map { CurveDay(date: d($0), planned: planned[$0], actual: $0 < actual.count ? actual[$0] : nil) }
        data.waitLabel = "รอการไฟฟ้านัดตรวจ"
        data.plan = InstallPlan.demo(gantt: InstallGantt(rows: rows, today: day), nonWorking: data.nonWorking, tracking: data.tracking, day: day)
        return data
    }
}
#endif

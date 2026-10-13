import Foundation
import TCRoofCore

/// Everything the iPhone `แผนงาน` page shows, for one "today".
struct PWAPlanBoard {
    var today: Date
    var bars: [PWAPlan.Bar]
    var curve: PWAPlan.Curve
    /// Every open deadline; the page shows those of this week and the next (`PWAPlan.groups`).
    var deadlines: [PWAPlan.Deadline]
    /// The agenda rows of some days, sorted.
    var agenda: ([Date]) -> [PWAPlan.AgendaItem]

    /// From the PWA jobs: their MP plans, survey appointments, papers and daily reports.
    init(stations: [PWAPlan.Station], library: StationDocs.Library, today: Date, threshold: Double) {
        let deadlines = PWAPlan.deadlines(stations, library: library, today: today, threshold: threshold)
        self.today = today
        self.bars = PWAPlan.bars(stations, today: today, threshold: threshold)
        self.curve = PWAPlan.curve(stations, today: today)
        self.deadlines = deadlines
        self.agenda = { PWAPlan.agenda(stations, deadlines: deadlines, days: $0, today: today, threshold: threshold) }
    }

    init(today: Date, bars: [PWAPlan.Bar], curve: PWAPlan.Curve, deadlines: [PWAPlan.Deadline], items: [PWAPlan.AgendaItem]) {
        self.today = today; self.bars = bars; self.curve = curve; self.deadlines = deadlines
        self.agenda = { days in
            let keys = Set(days.map { PWAPlan.calendar.startOfDay(for: $0) })
            return PWAPlan.sorted(items.filter { keys.contains($0.day) })
        }
    }
}

extension Job {
    /// This job for the plan page. No record keeps a station's contractor, so it has only our own team; a job is
    /// handed over once its status is `ติดตั้งเสร็จสิ้น`.
    var planStation: PWAPlan.Station {
        PWAPlan.Station(id: overviewID, mpNumber: mpNumber, code: code, name: stationName, kWp: capacityKW, team: team.rawValue,
                        input: scheduleInput, actual: scheduleActual, handedOver: status == .completed,
                        reportSentToday: sentDailyReportToday, surveyAt: surveyDate,
                        workingWeekdays: routineSettings.workingWeekdays, docs: stationDocs, docsContext: stationContext)
    }
}

#if DEBUG
/// `-pwaPlanDemo YES`: the example of docs/ui/pwa-plan-iphone (`assets/sample-data.json`), dated from `today` where
/// the board's today is Monday 12 ต.ค. 2569. The board has an agenda for the 12th and 13th only; the rows of the
/// 14th to 16th are made up to give its week strip the same dots.
enum PWAPlanDemo {
    /// MP, name, kWp, actual, plan, contractor, due as days from today.
    private static let stations: [(Int, String, Double, Double, Double, String, Int)] = [
        (189, "สถานีผลิตน้ำทุ่งน้อย · สาขาเมืองพล", 92.34, 38, 50, "A", 3),
        (120, "การประปาวัดชัย", 250, 22, 28, "B", 18),
        (98, "การประปาบ้านโป่ง", 90, 50, 52, "A", -6),
        (154, "สถานีจ่ายน้ำแพรกหนามแดง", 209.76, 71, 68, "C", 0),
        (77, "สถานีผลิตน้ำโชคชัย", 171, 94, 92, "B", -4),
        (61, "สถานีผลิตน้ำแม่ข่ายชนบท", 145.2, 12, 10, "D", 28),
        (133, "สถานีผลิตน้ำบางปะกง", 120.5, 55, 54, "A", 8),
        (142, "สถานีผลิตน้ำหนองแค", 180, 30, 36, "C", 16),
        (88, "สถานีผลิตน้ำพนัสนิคม", 160.4, 64, 62, "B", 2),
        (171, "สถานีผลิตน้ำสามโคก", 98.2, 8, 8, "D", 44),
        (66, "สถานีผลิตน้ำบ้านบึง", 210, 42, 40, "C", 21),
        (109, "สถานีผลิตน้ำศรีราชา", 115, 80, 78, "A", -2),
    ]

    /// Day offset, start, end, type, ref, title, subtitle, status, opens.
    private static let agenda: [(Int, String, String, PWAPlan.JobType, String, String, String, PWAPlan.AgendaStatus, PWAPlan.Target)] = [
        (0, "08:00", "17:00", .install, "MP 189", "2.3 ติดตั้งแผงเซลล์", "ทุ่งน้อย · ผู้รับเหมา A · TCR01", .doing, .station),
        (0, "08:30", "17:00", .install, "MP 120", "2.1 โครงสร้างรองรับ + Walkway", "วัดชัย · ผู้รับเหมา B · TCR03 · ช้ากว่าแผน 6%", .doing, .station),
        (0, "09:30", "11:30", .survey, "NO.224", "นัดสำรวจ สถานีผลิตน้ำ 1", "กปภ. สาขาตัวอย่าง · TCR02", .booked, .survey),
        (0, "10:30", "12:00", .inspection, "MP 154", "ผู้แทน กปภ. ตรวจ 2.5 Inverter", "แพรกหนามแดง · ผู้รับเหมา C", .waiting, .station),
        (0, "13:00", "", .document, "MP 189", "ยื่นแจ้งเทศบาล (กฎกระทรวงยกเว้น)", "เทศบาลเมืองพล · ครบกำหนดวันนี้", .mustSubmit, .docs),
        (0, "14:00", "16:30", .test, "MP 77", "3.1 Pre-Commissioning (IEC 62446)", "โชคชัย · TCR05 · ใช้เครื่องวัดฉนวน + I-V", .booked, .station),
        (0, "16:00", "", .notice, "รายงาน", "ส่งรายงานประจำวันก่อน 18:00", "ยังไม่ส่ง 4 สถานี · วัดชัย บ้านโป่ง หนองแค บ้านบึง", .alert, .dailies),
        (1, "08:00", "17:00", .install, "MP 189", "2.3 ติดตั้งแผงเซลล์", "ทุ่งน้อย · ผู้รับเหมา A · TCR01", .onPlan, .station),
        (1, "09:00", "11:00", .inspection, "MP 98", "ผู้แทน กปภ. ตรวจ 2.2 สาย DC", "บ้านโป่ง · ผู้รับเหมา A", .waiting, .station),
        (2, "08:00", "17:00", .install, "MP 189", "2.3 ติดตั้งแผงเซลล์", "ทุ่งน้อย · ผู้รับเหมา A · TCR01", .onPlan, .station),
        (2, "13:00", "", .document, "MP 88", "ส่ง Punch List ให้ผู้ว่าจ้างลงนาม", "พนัสนิคม · ผู้รับเหมา B", .mustSubmit, .docs),
        (3, "08:00", "17:00", .install, "MP 120", "2.1 โครงสร้างรองรับ + Walkway", "วัดชัย · ผู้รับเหมา B · TCR03", .onPlan, .station),
        (3, "09:00", "12:00", .test, "MP 109", "3.1 Pre-Commissioning (IEC 62446)", "ศรีราชา · ผู้รับเหมา A", .booked, .station),
        (3, "13:00", "", .document, "MP 154", "รวมเอกสาร พค.2 (กกพ.)", "แพรกหนามแดง · ผู้รับเหมา C", .mustSubmit, .docs),
        (4, "08:00", "17:00", .install, "MP 120", "2.1 โครงสร้างรองรับ + Walkway", "วัดชัย · ผู้รับเหมา B · TCR03", .onPlan, .station),
    ]

    /// Day offset, title, subtitle, kind, chip, tone, MP.
    private static let deadlines: [(Int, String, String, PWAPlan.DeadlineKind, String, PWAPlan.Tone, Int)] = [
        (-4, "ส่งมอบงาน", "MP 77 โชคชัย · Punch list + As-Built", .handover, "เลยกำหนด 4 วัน", .late, 77),
        (0, "ส่งมอบงาน", "MP 154 แพรกหนามแดง · จริง 71% / แผน 68%", .handover, "เสี่ยงช้า", .risk, 154),
        (0, "แจ้งเทศบาล (ยกเว้น ข.1)", "MP 189 ทุ่งน้อย · เทศบาลเมืองพล", .document, "วันนี้", .risk, 189),
        (2, "ส่งมอบงาน", "MP 88 พนัสนิคม · ผู้รับเหมา B", .handover, "ตามแผน", .ok, 88),
        (3, "ส่งมอบงาน", "MP 189 ทุ่งน้อย · จริง 38% / แผน 50%", .handover, "ช้ากว่าแผน", .late, 189),
        (8, "ยื่น พค.2 (กกพ.)", "MP 154 แพรกหนามแดง · 209.76 kWp ≥ 200 kVA", .document, "เอกสาร 18/23", .risk, 154),
        (8, "ส่งมอบงาน", "MP 133 บางปะกง · ผู้รับเหมา A", .handover, "ตามแผน", .ok, 133),
        (10, "ยื่นขอขนานไฟ (กฟภ.)", "MP 109 ศรีราชา · ชุด 4.2 ครบ 11/11", .document, "พร้อมยื่น", .ok, 109),
        (12, "อบรม O&M (3.2)", "MP 77 โชคชัย · คู่มือภาคตะวันออกเฉียงเหนือ", .other, "นัดแล้ว", .ok, 77),
    ]

    /// The project's actual percent by week up to last week; this week's is the weighted average of the stations.
    private static let actualByWeek: [Double] = [0, 0.5, 1.5, 3, 5, 8, 12, 17, 24, 31, 39]

    static func board(today: Date) -> PWAPlanBoard {
        let cal = PWAPlan.calendar, today = cal.startOfDay(for: today)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        func minutes(_ s: String) -> Int? {
            let p = s.split(separator: ":").compactMap { Int($0) }
            return p.count == 2 ? p[0] * 60 + p[1] : nil
        }
        func team(_ subtitle: String) -> String {
            subtitle.components(separatedBy: " · ").first { $0.hasPrefix("TCR") } ?? ""
        }
        func contractor(_ subtitle: String) -> String {
            subtitle.components(separatedBy: " · ").first { $0.hasPrefix("ผู้รับเหมา ") }.map { String($0.dropFirst("ผู้รับเหมา ".count)) } ?? ""
        }

        let bars = stations.map { s in
            PWAPlan.Bar(id: "demo-\(s.0)", ref: "MP \(s.0)", name: PWAPlan.shortName(s.1), fullName: s.1, contractor: s.5,
                        start: day(s.6 - 62), due: day(s.6), actual: s.3, planned: s.4, behind: s.3 - s.4 <= -2)
        }
        .sorted { $0.due < $1.due }

        let items = agenda.enumerated().map { i, a in
            PWAPlan.AgendaItem(id: "demo-\(i)", day: day(a.0), start: minutes(a.1), end: minutes(a.2), type: a.3, ref: a.4, title: a.5,
                               subtitle: a.6, status: a.7, contractor: contractor(a.6), team: team(a.6),
                               station: a.4.hasPrefix("MP ") ? "demo-" + a.4.dropFirst(3) : "", opens: a.8)
        }

        let due = deadlines.enumerated().map { i, d in
            PWAPlan.Deadline(id: "demo-\(i)", date: day(d.0), kind: d.3, title: d.1, subtitle: d.2, chip: d.4, tone: d.5,
                             station: "demo-\(d.6)", opens: d.3 == .document ? .docs : .station)
        }

        // the board's stand-in S-curve: 20 weeks, today in week 11, the plan a logistic curve through the stations' average
        let kWp = stations.reduce(0) { $0 + $1.2 }
        let done = stations.reduce(0) { $0 + $1.3 * $1.2 } / kWp, planned = stations.reduce(0) { $0 + $1.4 * $1.2 } / kWp
        let logistic = (0...20).map { 100 / (1 + exp(-(Double($0) - 11.4) / 2.6)) }
        let scale = planned.rounded() / logistic[11]
        let thisWeek = MasterSchedule.weekStart(today)
        let weeks = (0...20).map { MasterSchedule.calendar.date(byAdding: .day, value: ($0 - 11) * 7, to: thisWeek)! }
        let curve = PWAPlan.Curve(weeks: weeks, plan: logistic.map { min(100, $0 * scale) }, actual: actualByWeek + [done.rounded()],
                                  todayIndex: 11, planned: planned, done: done)

        return PWAPlanBoard(today: today, bars: bars, curve: curve, deadlines: due, items: items)
    }
}
#endif

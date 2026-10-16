import SwiftUI
import TCRoofUI
import TCRoofCore

/// The end of `ภาพรวม` (docs/ui/install-tracking-ipad §C): the `เอกสารโครงการ` tiles and the site panel. Only what
/// the app keeps is shown: the board's Work Permit, MOM, RFI, Material Approval, NCR and Change Order tiles, the
/// installed quantities, PPC and safety days have no model, so they are left out.
extension InstallPageData {
    enum Tone { case ok, warn, danger, info, idle }

    /// One line of a tile's sheet.
    struct DocItem: Identifiable {
        let id: String
        var code = ""
        let title: String
        let detail: String
        let chip: String
        let tone: Tone
        var target: Target?
    }

    /// One tile of `เอกสารโครงการ`: a status dot, its name and chip; tapped, its sheet lists `items`.
    struct DocTile: Identifiable {
        let id: String
        let title: String
        /// The sheet's line under the title.
        let about: String
        let chip: String
        let tone: Tone
        let items: [DocItem]
        /// Counts toward the header's `ต้องดำเนินการ n`.
        var needsAction: Bool { tone == .warn || tone == .danger }
    }

    /// A day of `แรงงาน`: the crew the week's request planned and the crew the daily report booked.
    struct LabourDay: Identifiable {
        let date: Date
        let plan: Int?
        let actual: Int?
        var id: Date { date }
    }

    struct SiteRisk: Identifiable {
        let id: String
        let level: RoutineReport.RiskLevel
        let title: String
        let prevention: String
    }

    /// `ข้อมูลหน้างาน · ความเสี่ยง · แรงงาน`.
    struct Site {
        var asOf: Date
        /// `ความคืบหน้าตามงาน`: the MP install tasks' % (the app keeps no installed quantities).
        var tasks: [(title: String, percent: Double)] = []
        /// Today's report's crew; nil before it is written.
        var peopleToday: Int?
        var manDays = 0
        /// Open problems carried by the latest daily report.
        var issues: [RoutineReport.Problem] = []
        /// Any daily report so far; without one the crew, issue and rain tiles are hidden rather than zero.
        var hasReports = false
        var reportsSent = 0
        var workingDaysSoFar = 0
        var rainHours = 0
        /// This week's request's risks; the tab is hidden without them.
        var risks: [SiteRisk] = []
        /// The install window's working days; the tab is hidden while no report has a crew.
        var labour: [LabourDay] = []
        var plannedManDays: Int? { let p = labour.compactMap(\.plan); return p.isEmpty ? nil : p.reduce(0, +) }
    }

    /// The IEC line: closed with its date and who, or the steps done and what the first open one lacks; and the
    /// photos on Drive.
    static func iecDetail(_ r: IECReport, drive: IECReport.Tally?) -> String {
        let photos = drive.map { " · รูปขึ้น Drive \($0.done)/\($0.total)" } ?? ""
        if let result = r.result {
            let f = DateFormatter()
            f.locale = Locale(identifier: "th_TH"); f.calendar = Calendar(identifier: .buddhist); f.dateFormat = "d MMM yyyy"
            return "ปิดการทดสอบ " + f.string(from: result.completedAt) + (result.by.isEmpty ? "" : " · " + result.by) + photos
        }
        let steps = IECReport.Stage.allCases.filter { $0 != .review }
        let done = steps.filter(r.isDone).count
        let next = steps.first { !r.isDone($0) }.map { " · ขั้น \($0.rawValue) ขาด " + (r.missing($0).first ?? "") } ?? " · พร้อมสรุปผล"
        return "ครบ \(done)/\(steps.count) ขั้น" + next + photos
    }

    @MainActor static func docTiles(job: Job, today: Date) -> [DocTile] {
        let cal = RoutineReport.calendar, day = cal.startOfDay(for: today)
        var tiles: [DocTile] = []

        // Daily Report: every report, newest first
        let logs = job.dailyLogs
        let todayState = job.dailyState(on: day)
        let working = RoutineReport.isWorkingDay(day, settings: job.routineSettings) && job.installDay(on: day) != nil
        let dailyItems = logs.enumerated().reversed().compactMap { i, log -> DocItem? in
            guard let r = log.report else { return nil }
            return DocItem(id: "dr\(i)", code: String(format: "DR-%03d", i + 1), title: dailyTitle(r),
                           detail: dailyDetail(r, photos: log.photos.count), chip: log.engineerSignedAt != nil ? "ส่งแล้ว" : "ร่าง",
                           tone: log.engineerSignedAt != nil ? .ok : .warn, target: .day(cal.startOfDay(for: r.date)))
        }
        if !logs.isEmpty || working {
            let (chip, tone): (String, Tone) = switch todayState {
            case .signed: ("วันนี้ส่งแล้ว", .ok)
            case .draft: ("วันนี้ยังไม่ลงนาม", .warn)
            case .none: working ? ("วันนี้ยังไม่ส่ง", .warn) : ("\(logs.count) ฉบับ", .idle)
            }
            tiles.append(DocTile(id: "daily", title: "Daily Report", about: "รายงานประจำวัน: งานที่ทำ จำนวนคน สภาพอากาศ ปัญหา และรูปหน้างาน",
                                 chip: chip, tone: tone, items: dailyItems))
        }

        // Weekly Report: the R3 summary of each week with a report
        let weeks = Dictionary(grouping: job.dailyReports) { RoutineReport.week(of: $0.date).lowerBound }
        if !weeks.isEmpty {
            let iso = Calendar(identifier: .iso8601)
            let items = weeks.keys.sorted(by: >).map { start -> DocItem in
                let w = RoutineReport.week(of: start), reports = weeks[start] ?? []
                let open = w.upperBound >= day
                return DocItem(id: "w\(RoutineReport.dayKey(start))", code: "W\(iso.component(.weekOfYear, from: w.upperBound))",
                               title: "สรุปงานประจำสัปดาห์ \(ThaiFormat.dayMonth.string(from: w.lowerBound)) – \(ThaiFormat.numericDate.string(from: w.upperBound))",
                               detail: "\(reports.count) รายงาน · \(reports.reduce(0) { $0 + $1.crewTotal }) คน·วัน",
                               chip: open ? "ครบ \(ThaiFormat.dayMonth.string(from: w.upperBound))" : "ครบสัปดาห์", tone: open ? .info : .ok, target: .weekly)
            }
            let this = RoutineReport.week(of: day)
            tiles.append(DocTile(id: "weekly", title: "Weekly Report", about: "สรุปงานประจำสัปดาห์ (R3) จากรายงานประจำวัน",
                                 chip: "W\(iso.component(.weekOfYear, from: this.upperBound)) ครบ \(ThaiFormat.dayMonth.string(from: this.upperBound))",
                                 tone: .info, items: items))
        }

        // ใบอนุญาต: the MP plan's permit tasks
        if let input = job.scheduleInput {
            let rows = RoutineReport.permits(plan: MasterSchedule.plan(input), actual: job.scheduleActual, at: day)
            if !rows.isEmpty {
                let late = rows.filter { $0.state == .late }.count, done = rows.filter { $0.state == .done }.count
                let items = rows.map { r in
                    DocItem(id: r.task.rawValue, code: r.task.code, title: r.task.title,
                            detail: [r.start, r.end].compactMap { $0 }.map(ThaiFormat.dayMonth.string(from:)).joined(separator: " – ").nonEmpty.map { "แผน " + $0 } ?? "ยังไม่มีในแผน",
                            chip: r.state.title, tone: r.state == .done ? .ok : r.state == .late ? .danger : r.state == .inProgress ? .info : .idle, target: .plan)
                }
                tiles.append(DocTile(id: "permits", title: "ใบอนุญาต", about: "งานขออนุญาตในแผน MP (1.x)",
                                     chip: late > 0 ? "เลยกำหนด \(late)" : "ได้ \(done)/\(rows.count)",
                                     tone: late > 0 ? .danger : done == rows.count ? .ok : .idle, items: items))
            }
        }

        // the station papers by submission
        let ctx = job.stationContext, station = job.stationDocs, library = StationDocsStore.loadLibrary()
        func paperItems(_ kinds: [StationDocs.Kind]) -> [DocItem] {
            kinds.map { k in
                let s = StationDocs.state(k, station: station, library: library).status
                let tone: Tone = s.isReady ? .ok : s == .notNeeded ? .idle : s == .missing ? .warn : .info
                return DocItem(id: k.id, title: k.name, detail: k.origin.title, chip: s.title, tone: tone, target: .docs)
            }
        }
        func packageTile(_ id: String, _ title: String, _ package: StationDocs.Package, due: Date?) -> DocTile? {
            guard StationDocs.packages(ctx).contains(package) else { return nil }
            let papers = StationDocs.papers(in: package, ctx)
            guard !papers.isEmpty else { return nil }
            let p = StationDocs.progress(package, station: station, library: library, ctx)
            let left = due.map { cal.dateComponents([.day], from: day, to: cal.startOfDay(for: $0)).day ?? 0 }
            let count = "\(p.ready)/\(p.total)"
            let chip = p.isComplete ? "ครบ " + count
                : due.map { (left ?? 0 < 0 ? "เลยกำหนด " : "กำหนด ") + ThaiFormat.dayMonth.string(from: $0) + " · " + count } ?? count
            let tone: Tone = p.isComplete ? .ok : (left ?? 1) < 0 ? .danger : (left ?? 8) <= 7 ? .warn : .idle
            return DocTile(id: id, title: title, about: "เอกสารชุดยื่น\(package.title)", chip: chip, tone: tone, items: paperItems(papers))
        }
        if var t = packageTile("commissioning", "Test & Commissioning", .commissioning, due: station.due(.commissioning)) {
            // the IEC 62446 test itself first, then the submission's papers
            let iec = job.iecReport
            let line = DocItem(id: "iec", code: "IEC", title: "ทดสอบ IEC 62446 ก่อน / หลังเชื่อมต่อ",
                               detail: iec.map { Self.iecDetail($0, drive: ProjectDriveUpload.iecPhotoUpload(job)) } ?? "ยังไม่ได้ตั้งค่า inverter และสตริง",
                               chip: iec.map { r in r.result.map { $0.passed ? "ผ่าน" : "ไม่ผ่าน" } ?? "\(Int((r.completion * 100).rounded()))%" } ?? "ยังไม่เริ่ม",
                               tone: iec.map { r in r.result.map { $0.passed ? .ok : .danger } ?? .info } ?? .idle, target: .iec)
            t = DocTile(id: t.id, title: t.title, about: t.about, chip: t.chip, tone: t.tone, items: [line] + t.items)
            tiles.append(t)
        }
        if let punch = StationDocs.kind("punch_list"), StationDocs.applies(punch, ctx) {
            let s = StationDocs.state(punch, station: station, library: library).status
            tiles.append(DocTile(id: "punch", title: "Punch List", about: punch.name, chip: s.title,
                                 tone: s.isReady ? .ok : .idle, items: paperItems([punch])))
        }
        if let t = packageTile("grid", "ขออนุญาตขนานไฟ", .gridConnection, due: station.due(.gridConnection)) { tiles.append(t) }

        // อุปกรณ์ที่ติดตั้ง: the serials scanned at the station
        let byKind = Dictionary(grouping: job.devices, by: \.kind)
        tiles.append(DocTile(id: "devices", title: "อุปกรณ์ที่ติดตั้ง", about: "หมายเลข S/N ที่สแกนเข้าสถานีนี้",
                             chip: job.devices.isEmpty ? "ยังไม่สแกน" : "สแกน \(job.devices.count)", tone: .idle,
                             items: DeviceKind.allCases.compactMap { k in
                                 guard let list = byKind[k], let last = list.map(\.scannedAt).max() else { return nil }
                                 return DocItem(id: k.rawValue, title: k.title, detail: "สแกนล่าสุด " + ThaiFormat.numericDate.string(from: last),
                                                chip: "\(list.count) ชิ้น", tone: .ok)
                             }))

        if let t = packageTile("handover", "ส่งมอบงาน", .handover, due: station.due(.handover) ?? job.installEnd) { tiles.append(t) }
        return tiles
    }

    private static func dailyTitle(_ r: RoutineReport.Daily) -> String {
        if !r.progress.isEmpty { return r.progress.prefix(3).map(\.title).joined(separator: " · ") }
        if !r.stopReason.isEmpty { return "หยุดงาน: " + r.stopReason }
        return "ไม่มีงานที่บันทึก"
    }

    private static func dailyDetail(_ r: RoutineReport.Daily, photos: Int) -> String {
        let weather = Dictionary(grouping: r.weather.compactMap { $0 }, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        return [ThaiFormat.numericDate.string(from: r.date), r.crewTotal > 0 ? "\(r.crewTotal) คน" : nil,
                r.rainHours > 0 ? "ฝน \(r.rainHours) ชม." : weather?.title, "\(photos) รูป"].compactMap { $0 }.joined(separator: " · ")
    }

    @MainActor static func site(job: Job, gantt: InstallGantt?, today: Date) -> Site {
        let cal = RoutineReport.calendar, day = cal.startOfDay(for: today), settings = job.routineSettings
        var s = Site(asOf: day)
        s.tasks = gantt?.rows.map { ($0.code + " " + $0.title, $0.percent) } ?? []
        let reports = job.dailyReports.filter { cal.startOfDay(for: $0.date) <= day }
        s.peopleToday = reports.first { cal.isDate($0.date, inSameDayAs: day) }.map(\.crewTotal)
        s.manDays = reports.reduce(0) { $0 + $1.crewTotal }
        s.hasReports = !reports.isEmpty
        s.issues = reports.last?.problems.filter { !$0.closed && !$0.description.isEmpty } ?? []
        s.reportsSent = job.dailyLogs.filter { $0.engineerSignedAt != nil && cal.startOfDay(for: $0.date) <= day }.count
        s.rainHours = reports.reduce(0) { $0 + $1.rainHours }
        s.risks = (job.weeklyRequest(for: day)?.risks ?? []).filter { !$0.description.isEmpty }
            .sorted { rank($0.level) > rank($1.level) }
            .map { SiteRisk(id: $0.id.uuidString, level: $0.level, title: $0.description, prevention: $0.prevention) }

        let start = cal.startOfDay(for: job.installStart), end = cal.startOfDay(for: job.installEnd)
        var d = start, days: [LabourDay] = []
        while d <= end {
            if RoutineReport.isWorkingDay(d, settings: settings) {
                if d <= day { s.workingDaysSoFar += 1 }
                let plan = job.weeklyRequest(for: d).map { $0.crew.reduce(0) { $0 + $1.count } }.flatMap { $0 > 0 ? $0 : nil }
                let actual = reports.first { cal.isDate($0.date, inSameDayAs: d) }.map(\.crewTotal).flatMap { $0 > 0 ? $0 : nil }
                days.append(LabourDay(date: d, plan: plan, actual: actual))
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end.addingTimeInterval(86_400)
        }
        s.labour = days.contains { $0.actual != nil } ? days : []
        return s
    }

    private static func rank(_ l: RoutineReport.RiskLevel) -> Int { switch l { case .high: 2; case .medium: 1; case .low: 0 } }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
extension InstallPageData {
    /// The board's tiles and site panel, kept to the tiles the app has a source for.
    static func demoTiles(day: Date) -> [DocTile] {
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        let daily: [(String, String, Int, String, Int)] = [
            ("เดินสายสตริง 1–12 ครบ ติดตั้งตู้ DC combiner", "แดดจัด", 6, "", 4), ("เริ่มเดินสาย DC สตริง 1–6", "มีเมฆ", 6, "", 5),
            ("ติดตั้งแผงครบ 164 แผง ต่อสายดินโครงแผง", "แดดจัด", 8, "", 10), ("ติดตั้งแผงแถว A–C (96 แผง)", "ฝน 2 ชม.", 8, "", 8),
            ("ติดตั้งรางครบทุกแถว ซีลกันรั่วจุดยึด", "แดดจัด", 6, "", 6), ("วางแนวรางแถว A–C", "มีเมฆ", 6, "", 6),
            ("รับวัสดุเข้าหน้างาน ตรวจนับครบตามใบส่งของ", "แดดจัด", 4, "", 6)]
        let dailyItems = daily.enumerated().map { i, r in
            DocItem(id: "dr\(i)", code: String(format: "DR-%03d", 7 - i), title: r.0,
                    detail: "\(ThaiFormat.numericDate.string(from: d(6 - i))) · \(r.2) คน · \(r.1) · \(r.4) รูป", chip: "ส่งแล้ว", tone: .ok, target: .day(d(6 - i)))
        }
        func papers(_ names: [(String, StationDocs.Status)]) -> [DocItem] {
            names.enumerated().map { i, p in
                DocItem(id: "p\(i)", title: p.0, detail: "ทีมเราทำ", chip: p.1.title,
                        tone: p.1.isReady ? .ok : p.1 == .missing ? .warn : .info, target: .docs)
            }
        }
        return [
            DocTile(id: "daily", title: "Daily Report", about: "รายงานประจำวัน: งานที่ทำ จำนวนคน สภาพอากาศ ปัญหา และรูปหน้างาน",
                    chip: "วันนี้ส่งแล้ว", tone: .ok, items: dailyItems),
            DocTile(id: "weekly", title: "Weekly Report", about: "สรุปงานประจำสัปดาห์ (R3) จากรายงานประจำวัน",
                    chip: "W40 ครบ \(ThaiFormat.dayMonth.string(from: d(10)))", tone: .warn,
                    items: [DocItem(id: "w40", code: "W40", title: "สรุปงานประจำสัปดาห์", detail: "4 รายงาน · 26 คน·วัน", chip: "ร่างพร้อมแล้ว", tone: .info, target: .weekly),
                            DocItem(id: "w39", code: "W39", title: "สรุปงานประจำสัปดาห์", detail: "3 รายงาน · 18 คน·วัน", chip: "ครบสัปดาห์", tone: .ok, target: .weekly)]),
            DocTile(id: "permits", title: "ใบอนุญาต", about: "งานขออนุญาตในแผน MP (1.x)", chip: "ได้ 3/4", tone: .idle, items: []),
            DocTile(id: "commissioning", title: "Test & Commissioning", about: "เอกสารชุดยื่นทดสอบระบบ", chip: "3/10", tone: .idle,
                    items: papers([("ตารางตรวจสอบก่อน / หลังเชื่อมต่อ (IEC 62446)", .draft), ("ภาพถ่ายความร้อน", .missing)])),
            DocTile(id: "punch", title: "Punch List", about: "Punch List Inspection Report", chip: "ยังไม่มี", tone: .idle,
                    items: papers([("Punch List Inspection Report", .missing)])),
            DocTile(id: "grid", title: "ขออนุญาตขนานไฟ", about: "เอกสารชุดยื่นขนานไฟ", chip: "กำหนด \(ThaiFormat.dayMonth.string(from: d(11))) · 4/6", tone: .warn,
                    items: papers([("Single Line Diagram + เอกสารวิศวกรไฟฟ้า", .signed), ("หนังสือแจ้งดับไฟ", .draft)])),
            DocTile(id: "devices", title: "อุปกรณ์ที่ติดตั้ง", about: "หมายเลข S/N ที่สแกนเข้าสถานีนี้", chip: "สแกน 150", tone: .idle,
                    items: [DocItem(id: "panel", title: "แผงโซลาร์เซลล์", detail: "สแกนล่าสุด " + ThaiFormat.numericDate.string(from: d(4)), chip: "150 ชิ้น", tone: .ok)]),
            DocTile(id: "handover", title: "ส่งมอบงาน", about: "เอกสารชุดยื่นส่งมอบงาน", chip: "กำหนด \(ThaiFormat.dayMonth.string(from: d(12))) · 2/9", tone: .warn, items: [])]
    }

    static func demoSite(day: Date) -> Site {
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        var s = Site(asOf: day)
        s.tasks = [("ส่งวัสดุเข้าหน้างาน", 100), ("ติดตั้งโครงสร้างราง", 100), ("ติดตั้งแผงโซลาร์", 100), ("เดินสาย DC · ตู้ DC", 50),
                   ("ติดตั้งอินเวอร์เตอร์ · ตู้ AC", 0), ("ทดสอบระบบ", 0)]
        s.hasReports = true; s.peopleToday = 6; s.manDays = 44; s.reportsSent = 7; s.workingDaysSoFar = 7; s.rainHours = 2
        s.issues = [.init(description: "รออนุมัติตู้ AC ก่อน \(ThaiFormat.dayMonth.string(from: d(8)))", since: d(4))]
        s.risks = [SiteRisk(id: "1", level: .high, title: "ตู้ AC ส่งไม่ทันขั้น 5 (\(ThaiFormat.dayMonth.string(from: d(8))))", prevention: "ติดตาม MA-05 ทุกวัน · สำรองตู้จากคลัง"),
                   SiteRisk(id: "2", level: .medium, title: "ฝนตก \(ThaiFormat.dayMonth.string(from: d(8)))–\(ThaiFormat.dayMonth.string(from: d(9))) (โอกาส 60–70%)", prevention: "ทำงานในร่มก่อน · เผื่อ 1 วันในแผน"),
                   SiteRisk(id: "3", level: .low, title: "การไฟฟ้านัดตรวจหลัง \(ThaiFormat.dayMonth.string(from: d(12)))", prevention: "ยื่นเอกสารขนานไฟให้ครบก่อน")]
        let plan = [4, 6, 6, 8, 8, 6, 6, 6, 4, 4, nil, nil, 4], actual: [Int?] = [4, 6, 6, 8, 8, 6, 6]
        s.labour = plan.indices.compactMap { i in
            guard let p = plan[i] else { return nil }
            return LabourDay(date: d(i), plan: p, actual: i < actual.count ? actual[i] : nil)
        }
        return s
    }
}
#endif

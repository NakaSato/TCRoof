import SwiftUI
import TCRoofUI
import TCRoofCore

/// The end of `ภาพรวม` (docs/ui/install-tracking-ipad §C): the `เอกสารโครงการ` tiles and the site panel. Only what
/// the app keeps is shown: the board's Work Permit, MOM, RFI, Material Approval, NCR and Change Order tiles, the
/// installed quantities, PPC and safety days have no model, so they are left out.
extension InstallPageData {
    /// `waiting`: handed in, waiting on someone outside the team (purple); `info`: the team is working on it.
    enum Tone {
        case ok, warn, danger, info, waiting, idle

        init(_ level: StationDocs.ChipLevel) {
            self = switch level {
            case .done: .ok
            case .waiting: .waiting
            case .working: .info
            case .dueSoon, .open: .warn
            case .late: .danger
            case .none: .idle
            }
        }
    }

    /// One line of a tile's sheet.
    struct DocItem: Identifiable {
        let id: String
        var code = ""
        let title: String
        let detail: String
        let chip: String
        let tone: Tone
        var target: Target?
        /// A button at the row's end instead of the whole row opening `target` (`เปิดบันทึก ›`).
        var button: String?
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

    /// `ข้อมูลหน้างาน | ความเสี่ยง | แรงงาน`.
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
        let photos = drive.map { " | รูปขึ้น Drive \($0.done)/\($0.total)" } ?? ""
        if let result = r.result {
            let f = DateFormatter()
            f.locale = Locale(identifier: "th_TH"); f.calendar = Calendar(identifier: .buddhist); f.dateFormat = "d MMM yyyy"
            return "ปิดการทดสอบ " + f.string(from: result.completedAt) + (result.by.isEmpty ? "" : " | " + result.by) + photos
        }
        if let sent = r.submission {
            return "ส่งผลให้ทีมแล้ว" + (sent.by.isEmpty ? "" : " | " + sent.by) + " | รอทีมภายในปิด" + photos
        }
        let steps = IECReport.Stage.allCases.filter { $0 != .review }
        let done = steps.filter(r.isDone).count
        let next = steps.first { !r.isDone($0) }.map { " | ขั้น \($0.rawValue) ขาด " + (r.missing($0).first ?? "") } ?? " | พร้อมสรุปผล"
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
                           detail: dailyDetail(r, photos: log.sortedPhotos.count), chip: log.engineerSignedAt != nil ? "ส่งแล้ว" : "ร่าง",
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
                               detail: "\(reports.count) รายงาน | \(reports.reduce(0) { $0 + $1.crewTotal }) คน-วัน",
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
        let hasIEC = job.iecReport != nil
        func paperItems(_ kinds: [StationDocs.Kind], code prefix: String? = nil) -> [DocItem] {
            kinds.enumerated().map { i, k in
                let s = StationDocs.state(k, station: station, library: library).status
                // the hand-over's IEC report is the station's own test, when it has one
                let target: Target = k.id == "iec62446_report" && hasIEC ? .iec : .docs
                return DocItem(id: k.id, code: prefix.map { String(format: "%@-%02d", $0, i + 1) } ?? "", title: k.name,
                               detail: k.origin.title, chip: s.title, tone: Tone(StationDocs.level(s)), target: target)
            }
        }
        func packageTile(_ id: String, _ title: String, _ package: StationDocs.Package, about: String,
                         due: Date?, dueWord: String = "กำหนด") -> DocTile? {
            guard StationDocs.packages(ctx).contains(package) else { return nil }
            let papers = StationDocs.papers(in: package, ctx)
            guard !papers.isEmpty else { return nil }
            let statuses = papers.map { StationDocs.state($0, station: station, library: library).status }
            let c = StationDocs.packageChip(statuses, due: due, today: day, calendar: cal)
            let state = c.awaitingApproval ? "ยื่นครบแล้ว รอ กฟภ. นัดตรวจ"
                : due.map { dueWord + " " + ThaiFormat.numericDate.string(from: $0) }
            return DocTile(id: id, title: title, about: [about, state].compactMap { $0 }.joined(separator: " | "),
                           chip: c.text, tone: c.level == .open ? .idle : Tone(c.level), items: paperItems(papers, code: package.codePrefix))
        }
        if var t = packageTile("commissioning", "Test & Commissioning", .commissioning, about: "เอกสารชุดยื่นทดสอบระบบ",
                               due: station.due(.commissioning)) {
            // the IEC 62446 test itself first, then the submission's papers
            let iec = job.iecReport
            let line = DocItem(id: "iec", code: "IEC", title: "ทดสอบ IEC 62446 ก่อน / หลังเชื่อมต่อ",
                               detail: iec.map { Self.iecDetail($0, drive: ProjectDriveUpload.iecPhotoUpload(job)) } ?? "ยังไม่ได้ตั้งค่า inverter และสตริง",
                               chip: iec.map { r in r.result.map { $0.passed ? "ผ่าน" : "ไม่ผ่าน" } ?? (r.isAwaitingClose ? "รอปิด" : "\(Int((r.completion * 100).rounded()))%") } ?? "ยังไม่เริ่ม",
                               tone: iec.map { r in r.result.map { $0.passed ? .ok : .danger } ?? (r.isAwaitingClose ? .waiting : .info) } ?? .idle, target: .iec)
            t = DocTile(id: t.id, title: t.title, about: t.about, chip: t.chip, tone: t.tone, items: [line] + t.items)
            tiles.append(t)
        }
        if let punch = StationDocs.kind("punch_list"), StationDocs.applies(punch, ctx) {
            let s = StationDocs.state(punch, station: station, library: library).status
            tiles.append(DocTile(id: "punch", title: "Punch List", about: punch.name, chip: s.title,
                                 tone: s.isReady ? .ok : .idle, items: paperItems([punch])))
        }
        let grid = StationDocs.Package.gridConnection
        if let t = packageTile("grid", [grid.section, grid.title + " (กฟภ.)"].compactMap { $0 }.joined(separator: " "), grid,
                               about: "ชุดยื่น กปภ. ของสถานีนี้", due: station.due(grid)) { tiles.append(t) }

        tiles.append(devicesTile(job))

        if let t = packageTile("handover", "ส่งมอบงาน", .handover, about: "ชุดส่งมอบ กปภ. ของสถานีนี้",
                               due: station.due(.handover) ?? job.installEnd, dueWord: "กำหนดส่งมอบ") { tiles.append(t) }
        return tiles
    }

    /// `อุปกรณ์ที่ติดตั้ง`: a row per device kind the station has a count or a scan for. The planned count comes from
    /// the IEC set-up (panels on its strings, its inverters); no field holds an installed count, so none is shown.
    @MainActor static func devicesTile(_ job: Job) -> DocTile {
        let scanned = Dictionary(grouping: job.devices, by: \.kind).mapValues(\.count)
        let iec = job.iecReport
        let modules = iec?.inverters.reduce(0) { $0 + $1.moduleCount } ?? 0
        let planned: [DeviceKind: Int] = [.panel: modules, .inverter: iec?.inverters.count ?? 0].filter { $0.value > 0 }
        let size: [DeviceKind: String] = [
            .panel: iec.flatMap { $0.module.powerW > 0 ? "\(Int($0.module.powerW.rounded())) W" : nil },
            .inverter: iec.flatMap { r in
                let kw = r.inverters.map(\.ratedKW).filter { $0 > 0 }
                return kw.isEmpty ? nil : kw.map { $0.formatted(.number.precision(.fractionLength(0...1))) }.joined(separator: " + ") + " kW"
            }].compactMapValues { $0 }
        var missing = 0
        let rows = DeviceKind.allCases.compactMap { k -> DocItem? in
            let c = scanned[k] ?? 0, b = planned[k]
            guard c > 0 || b != nil else { return nil }
            let (chip, tone): (String, Tone)
            if let b {
                missing += max(b - c, 0)
                (chip, tone) = c >= b ? ("ครบ", .ok) : ("ขาด S/N \(b - c)", .warn)
            } else {
                (chip, tone) = ("สแกน \(c)", .idle)
            }
            return DocItem(id: k.rawValue, code: k.equipmentCode, title: [k.title, size[k]].compactMap { $0 }.joined(separator: " | "),
                           detail: b.map { "S/N \(c)/\($0)" } ?? "S/N \(c)", chip: chip, tone: tone, target: .devices, button: "เปิดบันทึก ›")
        }
        let (chip, tone): (String, Tone) = rows.isEmpty ? ("ยังไม่สแกน", .idle) : missing > 0 ? ("S/N ขาด \(missing)", .warn) : ("ครบ", .ok)
        return DocTile(id: "devices", title: "อุปกรณ์ที่ติดตั้ง",
                       about: "ทะเบียนอุปกรณ์ที่ติดตั้งจริง พร้อม Serial No. | ใช้ทำใบรับประกันและ As-built",
                       chip: chip, tone: tone, items: rows)
    }

    private static func dailyTitle(_ r: RoutineReport.Daily) -> String {
        if !r.progress.isEmpty { return r.progress.prefix(3).map(\.title).joined(separator: " | ") }
        if !r.stopReason.isEmpty { return "หยุดงาน: " + r.stopReason }
        return "ไม่มีงานที่บันทึก"
    }

    private static func dailyDetail(_ r: RoutineReport.Daily, photos: Int) -> String {
        let weather = Dictionary(grouping: r.weather.compactMap { $0 }, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        return [ThaiFormat.numericDate.string(from: r.date), r.crewTotal > 0 ? "\(r.crewTotal) คน" : nil,
                r.rainHours > 0 ? "ฝน \(r.rainHours) ชม." : weather?.title, "\(photos) รูป"].compactMap { $0 }.joined(separator: " | ")
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

extension StationDocs.Package {
    /// The code before a paper's number in a tile's sheet (`4.2-01`, `HO-01`); the test's papers go without.
    var codePrefix: String? {
        switch self {
        case .handover: "HO"
        case .commissioning: nil
        default: section
        }
    }
}

extension DeviceKind {
    /// `อุปกรณ์ที่ติดตั้ง`'s row code.
    var equipmentCode: String {
        switch self {
        case .panel: "EQ-PV"
        case .inverter: "EQ-INV"
        case .optimizer: "EQ-OPT"
        case .battery: "EQ-BAT"
        case .meter: "EQ-MTR"
        }
    }
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
                    detail: "\(ThaiFormat.numericDate.string(from: d(6 - i))) | \(r.2) คน | \(r.1) | \(r.4) รูป", chip: "ส่งแล้ว", tone: .ok, target: .day(d(6 - i)))
        }
        func papers(_ names: [(String, StationDocs.Status)]) -> [DocItem] {
            names.enumerated().map { i, p in
                DocItem(id: "p\(i)", title: p.0, detail: "ทีมเราทำ", chip: p.1.title, tone: Tone(StationDocs.level(p.1)), target: .docs)
            }
        }
        return [
            DocTile(id: "daily", title: "Daily Report", about: "รายงานประจำวัน: งานที่ทำ จำนวนคน สภาพอากาศ ปัญหา และรูปหน้างาน",
                    chip: "วันนี้ส่งแล้ว", tone: .ok, items: dailyItems),
            DocTile(id: "weekly", title: "Weekly Report", about: "สรุปงานประจำสัปดาห์ (R3) จากรายงานประจำวัน",
                    chip: "W40 ครบ \(ThaiFormat.dayMonth.string(from: d(10)))", tone: .warn,
                    items: [DocItem(id: "w40", code: "W40", title: "สรุปงานประจำสัปดาห์", detail: "4 รายงาน | 26 คน-วัน", chip: "ร่างพร้อมแล้ว", tone: .info, target: .weekly),
                            DocItem(id: "w39", code: "W39", title: "สรุปงานประจำสัปดาห์", detail: "3 รายงาน | 18 คน-วัน", chip: "ครบสัปดาห์", tone: .ok, target: .weekly)]),
            DocTile(id: "permits", title: "ใบอนุญาต", about: "งานขออนุญาตในแผน MP (1.x)", chip: "ได้ 3/4", tone: .idle, items: []),
            DocTile(id: "commissioning", title: "Test & Commissioning", about: "เอกสารชุดยื่นทดสอบระบบ", chip: "3/10 ฉบับ", tone: .idle,
                    items: papers([("ตารางตรวจสอบก่อน / หลังเชื่อมต่อ (IEC 62446)", .draft), ("รายงานภาพถ่ายตรวจสอบก่อน / หลังเชื่อมต่อ", .submitted),
                                   ("ภาพถ่ายความร้อน", .missing)])),
            DocTile(id: "punch", title: "Punch List", about: "Punch List Inspection Report", chip: "ยังไม่มี", tone: .idle,
                    items: papers([("Punch List Inspection Report", .missing)])),
            demoGrid, demoDevices,
            DocTile(id: "handover", title: "ส่งมอบงาน", about: "ชุดส่งมอบ กปภ. ของสถานีนี้ | กำหนดส่งมอบ \(ThaiFormat.numericDate.string(from: d(12)))",
                    chip: "1/4 ฉบับ", tone: .warn, items: [
                        DocItem(id: "asbuilt", code: "HO-01", title: "As-Built Drawing",
                                detail: "ทีมเราทำ | วิศวกรไฟฟ้า | ครบกำหนด \(ThaiFormat.dayMonth.string(from: d(12)))", chip: "ร่างแล้ว", tone: .info, target: .docs),
                        DocItem(id: "iec62446_report", code: "HO-02", title: "รายงาน IEC 62446",
                                detail: "ทีมเราทำ | จากแท็บทดสอบ IEC 62446 | ทดสอบ \(ThaiFormat.dayMonth.string(from: d(9)))", chip: "ยังไม่มี", tone: .warn, target: .iec),
                        DocItem(id: "om_manual", code: "HO-03", title: "คู่มือ O&M รายภาค", detail: "ดึงจากคลังกลาง", chip: "อนุมัติแล้ว", tone: .ok, target: .docs),
                        DocItem(id: "warranty", code: "HO-04", title: "ใบรับประกันอุปกรณ์",
                                detail: "ขอจากผู้ผลิต | ใช้ S/N จากอุปกรณ์ที่ติดตั้ง", chip: "ยังไม่มี", tone: .warn, target: .docs)])]
    }

    /// The board's `4.2 ขนานไฟ (กฟภ.)`: eleven papers handed in, waiting for the utility's inspection.
    private static var demoGrid: DocTile {
        let papers: [(String, String)] = [
            ("คำขออนุญาตขนานไฟ (กฟภ.)", "ทีมเราทำ | แอปสร้างได้"), ("Single Line Diagram | วิศวกรรับรอง", "ทีมเราทำ | วิศวกรไฟฟ้า"),
            ("Datasheet แผง + Inverter", "ดึงจากคลังกลาง"), ("ใบ กว. + ตพค. วิศวกรไฟฟ้า", "ดึงจากคลังกลาง"),
            ("พ.ร.บ.การประปาส่วนภูมิภาค", "ดึงจากคลังกลาง"), ("ใบแจ้งค่าไฟ 3 เดือน", "ขอจาก กปภ.สาขา"),
            ("แผนที่ตั้ง (Google Map)", "ทีมเราทำ"), ("ภาพถ่ายการติดตั้ง", "ทีมเราทำ | ผู้ควบคุมงาน"),
            ("ใบรับรอง Inverter (ผู้ผลิต)", "ขอจากผู้ผลิต"), ("สำเนาบัตรผู้มอบ / ผู้รับมอบ", "ขอจาก กปภ.สาขา | ปิดข้อมูลบนบัตรแล้ว"),
            ("หนังสือมอบอำนาจ (ติดอากร)", "เราร่าง → ผจก.สาขาลงนาม")]
        return DocTile(id: "grid", title: "4.2 ขนานไฟ (กฟภ.)", about: "ชุดยื่น กปภ. ของสถานีนี้ | ยื่นครบแล้ว รอ กฟภ. นัดตรวจ",
                       chip: "ครบ 11/11", tone: .ok, items: papers.enumerated().map { i, p in
                           DocItem(id: "g\(i)", code: String(format: "4.2-%02d", i + 1), title: p.0, detail: p.1,
                                   chip: "อนุมัติแล้ว", tone: .ok, target: .docs)
                       })
    }

    /// The board's `อุปกรณ์ที่ติดตั้ง`, with the installed counts the app doesn't keep yet.
    private static var demoDevices: DocTile {
        let rows: [(String, String, String, String, Tone)] = [
            ("EQ-PV", "แผงโซลาร์ (PV) | 570 W", "ติดตั้ง 164/164 แผง | S/N 158/164 | สำรอง 2 แผง", "ขาด S/N 6", .warn),
            ("EQ-INV", "อินเวอร์เตอร์ | 60 + 30 kW", "ติดตั้ง 0/2 (ขั้น 5 | 2/10) | S/N 2/2 บันทึกตอนรับของ", "รอติดตั้ง", .waiting),
            ("EQ-MTR", "มิเตอร์ | Smart meter กันย้อน + มิเตอร์ กฟภ.", "ติดตั้ง 0/2 | มิเตอร์ กฟภ. บันทึกหลังขนานไฟ", "ยังไม่ถึง", .idle),
            ("EQ-RSD", "Rapid shutdown | 1 ตัวต่อ 2 แผง", "ติดตั้ง 82/82 | S/N 76/82 | ตัวส่งสัญญาณ 2 ชุด", "ขาด S/N 6", .warn)]
        return DocTile(id: "devices", title: "อุปกรณ์ที่ติดตั้ง",
                       about: "ทะเบียนอุปกรณ์ที่ติดตั้งจริง พร้อม Serial No. | ใช้ทำใบรับประกันและ As-built",
                       chip: "S/N ขาด 14", tone: .warn, items: rows.map { r in
                           DocItem(id: r.0, code: r.0, title: r.1, detail: r.2, chip: r.3, tone: r.4, target: .devices, button: "เปิดบันทึก ›")
                       })
    }

    static func demoSite(day: Date) -> Site {
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        var s = Site(asOf: day)
        s.tasks = [("ส่งวัสดุเข้าหน้างาน", 100), ("ติดตั้งโครงสร้างราง", 100), ("ติดตั้งแผงโซลาร์", 100), ("เดินสาย DC | ตู้ DC", 50),
                   ("ติดตั้งอินเวอร์เตอร์ | ตู้ AC", 0), ("ทดสอบระบบ", 0)]
        s.hasReports = true; s.peopleToday = 6; s.manDays = 44; s.reportsSent = 7; s.workingDaysSoFar = 7; s.rainHours = 2
        s.issues = [.init(description: "รออนุมัติตู้ AC ก่อน \(ThaiFormat.dayMonth.string(from: d(8)))", since: d(4))]
        s.risks = [SiteRisk(id: "1", level: .high, title: "ตู้ AC ส่งไม่ทันขั้น 5 (\(ThaiFormat.dayMonth.string(from: d(8))))", prevention: "ติดตาม MA-05 ทุกวัน | สำรองตู้จากคลัง"),
                   SiteRisk(id: "2", level: .medium, title: "ฝนตก \(ThaiFormat.dayMonth.string(from: d(8)))–\(ThaiFormat.dayMonth.string(from: d(9))) (โอกาส 60–70%)", prevention: "ทำงานในร่มก่อน | เผื่อ 1 วันในแผน"),
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

import Foundation
import TCRoofCore

/// What the customer's `Weekly Report Template` shows (docs/ui/install-tracking-ipad-weekly-report §4.3): the 8 slides'
/// values worked out once from the week's daily reports, the MP plan and the station's settings. The .pptx
/// (`WeeklySlides.export`) and the app's slide views draw from the same `Content`, so the screen shows the file.
extension WeeklySlides {
    /// The template's kinds of slide, in order; `photos` repeats, two photos a slide, as the customer's deck does.
    public enum Kind: Int, CaseIterable, Sendable {
        case cover = 1, agenda, progress, daily, photos, weather, problems

        /// The rail's and the viewer's name of the slide.
        public var label: String {
            switch self {
            case .cover: "ปก"
            case .agenda: "AGENDA"
            case .progress: "ความก้าวหน้า"
            case .daily: "งานรายวัน"
            case .photos: "ภาพหน้างาน"
            case .weather: "Weather Report"
            case .problems: "ปัญหาและอุปสรรค"
            }
        }

        /// The title in the slide's blue band (the cover has none).
        public var bandTitle: String {
            switch self {
            case .cover: ""
            case .agenda: "AGENDA"
            case .progress, .daily: "1.Construction Progress"
            case .photos: "Construction Progress"
            case .weather: "2.Weather Report"
            case .problems: "3.ปัญหาและอุปสรรค"
            }
        }
    }

    /// One slide of the deck as the rail, the viewer's chip and the .pptx sheet list it.
    public struct Outline: Sendable, Equatable {
        public var kind: Kind
        /// Its place in the deck, from 1.
        public var number: Int
        /// The photo slide's page, from 0 (0 for the others).
        public var page: Int
        public var label: String
        /// Where its values come from.
        public var source: String
        /// Its data is there; false while it waits on something (an unsigned daily report for the day table, the
        /// weather and the problems).
        public var ready: Bool
    }

    /// A week's plan and actual on slide 3, cumulative percent of the station's plan.
    public struct Bar: Sendable, Equatable {
        /// `W40`.
        public var label: String
        public var planned: Double
        public var actual: Double
        /// The week being reported.
        public var current: Bool
        public init(label: String, planned: Double, actual: Double, current: Bool) {
            self.label = label; self.planned = planned; self.actual = actual; self.current = current
        }
    }

    /// One day of slide 4's table.
    public struct Row: Sendable, Equatable {
        public enum State: Sendable, Equatable {
            /// A signed report: its work.
            case done
            /// A working day whose report is missing or not signed yet.
            case waiting
            /// Not a working day, without a report.
            case off
            /// Still ahead of the report's date.
            case ahead
        }
        public var number: Int
        public var date: Date
        /// `28/09/2569`.
        public var dateText: String
        /// Done work starts with `-`, as the customer's table.
        public var lines: [String]
        public var state: State
    }

    /// A photo on a photo slide: the id `images` holds its bytes under, and its caption with the day.
    public struct Photo: Sendable, Equatable {
        public var id: UUID
        public var width: Int
        public var height: Int
        public var caption: String
    }

    /// One column of the weather slide.
    public struct WeatherDay: Sendable, Equatable {
        /// The template's three pictures; nil shows the text only.
        public enum Icon: String, Sendable { case sunny = "weather-sunny", partlyCloudy = "weather-partly-cloudy", thunderstorm = "weather-thunderstorm" }
        /// `MON`, as the customer's deck.
        public var name: String
        /// The day's name in the deck's colour, as hex: gold on SAT and SUN, else black.
        public var colour: String
        /// `28/09`.
        public var date: String
        public var icon: Icon?
        public var text: String
    }

    public struct Content: Sendable {
        public var weekStart: Date
        /// The ISO number of the week (Monday to Sunday), the template's `สัปดาห์ที่`.
        public var weekNumber: Int
        /// The cover's project lines and `สถานีผลิตน้ำ…`.
        public var project: [String]
        public var station: String
        /// `ประจำวันที่ 28 กันยายน 2569 ถึงวันที่ 4 ตุลาคม 2569`.
        public var range: String
        /// The progress slide's `ช่วงระหว่างวันที่ … ถึง วันที่ …`.
        public var period: String
        /// The day table's line under the band: the station and `ดำเนินงาน 25–31 ตุลาคม 2569`.
        public var tableLine: String
        /// The last six weeks to this one; empty without an MP plan.
        public var bars: [Bar]
        /// Plan and actual through the week, percent; nil without an MP plan.
        public var planned: Double?
        public var actual: Double?
        public var rows: [Row]
        /// The week's photos day by day, at most `maxPhotos`, two a slide.
        public var photos: [Photo]
        /// The photos the week has in all.
        public var photoCount: Int
        public var weather: [WeatherDay]
        public var problems: [String]
        public var fixes: [String]
        /// The working days that wait on a daily report, as `ศ 2/10`.
        public var waiting: [String]
        /// The number of daily reports in the week.
        public var reportCount: Int

        /// `+2`, `-2`, `0`: actual less plan, rounded.
        public var status: String? {
            guard let p = planned, let a = actual else { return nil }
            let d = Int(a.rounded()) - Int(p.rounded())
            return d > 0 ? "+\(d)" : String(d)
        }

        /// Photo slides: two photos each, one slide when the week has none.
        public var photoPages: Int { max(1, (photos.count + 1) / 2) }

        /// The photos of photo slide `page` (from 0).
        public func photos(page: Int) -> [Photo] { Array(photos.dropFirst(page * 2).prefix(2)) }

        public var outline: [Outline] {
            let wait = waiting.isEmpty, pages = photoPages
            var out: [Outline] = []
            func add(_ k: Kind, page: Int = 0, label: String? = nil, source: String, ready: Bool) {
                out.append(Outline(kind: k, number: out.count + 1, page: page, label: label ?? k.label, source: source, ready: ready))
            }
            add(.cover, source: "ข้อมูลโครงการ", ready: true)
            add(.agenda, source: "แม่แบบ", ready: true)
            add(.progress, source: "แผน MP · รายงานประจำวัน", ready: planned != nil)
            add(.daily, source: "รายงานประจำวัน \(reportCount) วัน", ready: wait)
            for p in 0..<pages {
                add(.photos, page: p, label: pages > 1 ? "ภาพหน้างาน \(p + 1)/\(pages)" : "ภาพหน้างาน", source: "รูปในรายงานประจำวัน", ready: photoCount > 0)
            }
            add(.weather, source: "รายงานประจำวัน", ready: wait)
            add(.problems, source: "รายงานประจำวัน", ready: wait)
            return out
        }
    }

    /// The template's cover lines above the station when the station's settings name no contract.
    static let coverProject = ["โครงการจัดการพลังงานไฟฟ้าจากระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์",
                               "ที่ติดตั้งบนหลังคา (Solar Rooftop) การประปาส่วนภูมิภาค"]
    /// The weather slide's day names by weekday (Sunday first), as the customer's deck writes them.
    static let dayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    /// The most photos the deck takes (ten slides of two, as the customer's deck).
    public static let maxPhotos = 20
    static let dayShort = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]

    /// The slides as the rail, the viewer's chips and the .pptx sheet list them.
    public static func outline(_ input: Input) -> [Outline] { content(input).outline }

    /// The deck's values. `images` (photo bytes by id) leaves out photos without readable bytes, as the .pptx does;
    /// nil takes every photo.
    public static func content(_ input: Input, images: [UUID: Data]? = nil) -> Content {
        let cal = RoutineReport.calendar
        let range = week(of: input.week), start = range.lowerBound
        let days = input.days.filter { range.contains(cal.startOfDay(for: $0.report.date)) }.sorted { $0.report.date < $1.report.date }
        let reports = days.map(\.report)
        let today = cal.startOfDay(for: input.asOf)
        let weekNumber = WeeklySlides.weekNumber(start)

        // slide 3: the plan's cumulative percent at the end of each of the last six weeks
        var bars: [Bar] = [], planned: Double?, actual: Double?
        if let s = input.schedule {
            let plan = MasterSchedule.plan(s.input)
            for k in (0..<6).reversed() {
                let w = cal.date(byAdding: .day, value: -7 * k, to: start)!
                let end = min(cal.date(byAdding: .day, value: 6, to: w)!, max(today, w))
                let st = MasterSchedule.status(plan: plan, actual: s.actual, through: end)
                bars.append(Bar(label: "W\(WeeklySlides.weekNumber(w))", planned: st.planned,
                                actual: st.actual, current: k == 0))
            }
            planned = bars.last?.planned; actual = bars.last?.actual
        }

        // slide 4: a row a day
        var rows: [Row] = [], waiting: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let day = days.first { RoutineReport.dayKey($0.report.date) == RoutineReport.dayKey(d) }
            let label = dayLabel(d)
            var row = Row(number: i + 1, date: d, dateText: slashDate(d), lines: [], state: .done)
            if let day {
                if day.signed {
                    let done = RoutineReport.workDone(day.report, in: input.all).map(\.line.title)
                    row.lines = (!done.isEmpty ? done
                        : day.report.stopReason.isEmpty ? ["ไม่มีความก้าวหน้า"] : ["หยุดงาน: " + day.report.stopReason]).map { "-" + $0 }
                } else {
                    row.state = .waiting; row.lines = ["รอเซ็นรายงานประจำวัน " + label]; waiting.append(label)
                }
            } else if !RoutineReport.isWorkingDay(d, settings: input.settings) {
                row.state = .off; row.lines = ["วันหยุด"]
            } else if d > today {
                row.state = .ahead
            } else {
                row.state = .waiting; row.lines = ["ยังไม่มีรายงานประจำวัน " + label]; waiting.append(label)
            }
            rows.append(row)
        }

        // the photo slides: the week's photos day by day, captioned with their work and date
        func usable(_ p: DayPhoto) -> Bool {
            guard let images else { return true }
            return images[p.id].flatMap { IECWord.pixelSize($0) } != nil
        }
        let perDay = days.map { d in d.photos.filter(usable).map { (d.report.date, $0) } }
        let photos: [Photo] = perDay.joined().prefix(maxPhotos).map { date, p in
            let when = slashDate(date)
            return Photo(id: p.id, width: p.width, height: p.height, caption: p.caption.isEmpty ? when : "\(p.caption) \(when)")
        }

        // slide 7: a column a day
        let weather = rows.map { r -> WeatherDay in
            let w = cal.component(.weekday, from: r.date) - 1
            let slots = days.first { RoutineReport.dayKey($0.report.date) == RoutineReport.dayKey(r.date) }?.report.weather.compactMap { $0 } ?? []
            let c = cal.dateComponents([.day, .month], from: r.date)
            let date = String(format: "%02d/%02d", c.day ?? 0, c.month ?? 0)
            let colour = w == 0 || w == 6 ? "FFC000" : "000000"
            guard !slots.isEmpty else { return WeatherDay(name: dayNames[w], colour: colour, date: date, icon: nil, text: "-") }
            let fine = slots.filter { $0 == .fine }.count, cloudy = slots.filter { $0 == .cloudy }.count
            let kind: RoutineReport.Weather = slots.contains(.rain) ? .rain : fine > cloudy ? .fine : .cloudy
            let icon: WeatherDay.Icon = switch kind { case .rain: .thunderstorm; case .fine: .sunny; case .cloudy: .partlyCloudy }
            // the customer's words: แจ่มใส, เมฆมาก, ฝนตก
            let text = switch kind { case .fine: "แจ่มใส"; case .cloudy: "เมฆมาก"; case .rain: "ฝนตก" }
            return WeatherDay(name: dayNames[w], colour: colour, date: date, icon: icon, text: text)
        }

        let p = RoutineReport.problems(reports), all = p.open + p.closed
        let s = input.stationName.trimmingCharacters(in: .whitespaces)
        let contract = input.settings.contractName.trimmingCharacters(in: .whitespaces)
        let station = s.hasPrefix("สถานี") ? s : "สถานีผลิตน้ำ" + s
        return Content(weekStart: start, weekNumber: weekNumber, project: contract.isEmpty ? coverProject : [contract],
                       station: station,
                       range: "ประจำวันที่ " + longDate(start) + " ถึงวันที่ " + longDate(range.upperBound),
                       period: "ช่วงระหว่างวันที่ " + longDate(start) + " ถึง วันที่ " + longDate(range.upperBound),
                       tableLine: station + " ดำเนินงาน " + spanDates(range),
                       bars: bars, planned: planned, actual: actual, rows: rows, photos: photos,
                       photoCount: perDay.reduce(0) { $0 + $1.count }, weather: weather,
                       problems: all.map(\.description), fixes: all.map(\.solution).filter { !$0.isEmpty },
                       waiting: waiting, reportCount: reports.count)
    }

    /// The Weekly Report's week, Monday to Sunday as the customer's deck (the R3 PDF and the MP plan count weeks from
    /// Sunday).
    public static func week(of date: Date) -> ClosedRange<Date> {
        let cal = RoutineReport.calendar, d = cal.startOfDay(for: date)
        let monday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: d) + 5) % 7), to: d)!
        return monday...cal.date(byAdding: .day, value: 6, to: monday)!
    }

    /// The ISO week number of a Monday-to-Sunday week (`สัปดาห์ที่`, `W40`).
    public static func weekNumber(_ d: Date) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = RoutineReport.calendar.timeZone
        return iso.component(.weekOfYear, from: d)
    }

    /// `28 กันยายน 2569`.
    public static func longDate(_ d: Date) -> String {
        let c = RoutineReport.calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.day ?? 0) \(RoutineReport.thaiMonths[(c.month ?? 1) - 1]) \((c.year ?? 0) + 543)"
    }

    /// `25–31 ตุลาคม 2569`, `28 กันยายน – 4 ตุลาคม 2569`.
    static func spanDates(_ r: ClosedRange<Date>) -> String {
    let cal = RoutineReport.calendar
    let a = cal.dateComponents([.day, .month, .year], from: r.lowerBound), b = cal.dateComponents([.day, .month, .year], from: r.upperBound)
    let m = RoutineReport.thaiMonths
    if a.month == b.month { return "\(a.day ?? 0)–\(b.day ?? 0) \(m[(b.month ?? 1) - 1]) \((b.year ?? 0) + 543)" }
    return "\(a.day ?? 0) \(m[(a.month ?? 1) - 1]) – \(b.day ?? 0) \(m[(b.month ?? 1) - 1]) \((b.year ?? 0) + 543)"
    }

    /// `28/09/2569`.
    static func slashDate(_ d: Date) -> String {
        let c = RoutineReport.calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%02d/%02d/%d", c.day ?? 0, c.month ?? 0, (c.year ?? 0) + 543)
    }

    /// `ศ 2/10`.
    public static func dayLabel(_ d: Date) -> String {
        let cal = RoutineReport.calendar, c = cal.dateComponents([.weekday, .day, .month], from: d)
        return "\(dayShort[(c.weekday ?? 1) - 1]) \(c.day ?? 0)/\(c.month ?? 0)"
    }

    /// A picture of the template (`logo-pea-seal`, `agenda-hex-1`…`3`, `weather-sunny`…), PNG bytes.
    public static func templatePicture(_ name: String) -> Data? {
        let url = Bundle.module.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "WeeklyTemplate")
        return url.flatMap { try? Data(contentsOf: $0) }
    }
}

import Foundation
import TCRoofCore

/// The team's station plans (`Project_Plan_TCRoof/2_แผนนำเข้า TCRoof (102 สถานี)`): one plan workbook per PWA station,
/// bundled as `PlanTemplates` (a link to the import files, so a regenerated set ships as it is). A station's plan starts
/// from one, normally its own: the plan moved to the station's kickoff, written into a copy of its file, which the
/// station keeps as its own plan workbook (`Job.scheduleWorkbook`).
///
/// The 20 install cases (`Project_Plan_TCRoof/3_แม่แบบ 20 กรณี`, bundled as `CaseTemplates`, P9-001…020) are the plan for a
/// station without a file of its own: 5 site types × กันย้อน HV / LV × Inverter < / ≥ 200 kVA, titled `แม่แบบ <site>,
/// กันย้อน HV, Inverter < 200 kVA` (an older set wrote `·` between the parts, which still reads). They differ in the
/// permits (≥ 200 kVA weighs พค.2, LV marks the 22 kV rows not for the station) and, through `applySite`, in 2.1's steps.
public enum MPTemplates {
    public struct Case: Identifiable, Hashable, Sendable {
        /// `P3-001`: the file name's code.
        public let id: String
        /// The station, `สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล`; an example file's case title.
        public let name: String
        /// The file's second line: สาขา, region, กฟภ., inverter, zero export, request, people.
        public let detail: String
        /// `หลังคาลอนคู่`, `ถังน้ำใส` … for an example file; empty for a station's (its file doesn't say).
        public let site: String
        /// `HV` or `LV`.
        public let backfeed: String
        public let over200kVA: Bool
        public let kWp: Double?
        public let url: URL

        public var title: String { site.isEmpty ? name : "\(site) | กันย้อน \(backfeed) | Inverter \(over200kVA ? "≥" : "<") 200 kVA" }
        /// `กปภ.สาขาชัยบาดาล`
        public var branch: String { detail.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "" }

        /// Search by code, station, สาขา or anything on its second line.
        public func matches(_ query: String) -> Bool {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            return q.isEmpty || [id, name, detail].contains { $0.lowercased().contains(q) }
        }
    }

    /// The bundled templates' folder.
    public static var bundled: URL? { Bundle.module.url(forResource: "PlanTemplates", withExtension: nil) }
    /// The bundled install cases' folder.
    public static var bundledCases: URL? { Bundle.module.url(forResource: "CaseTemplates", withExtension: nil) }

    /// The 20 install cases (`site` set on each), by code.
    public static func installCases(in folder: URL? = bundledCases) -> [Case] { cases(in: folder).filter { !$0.site.isEmpty } }

    /// The case for a station: the one of its size (พค.2 or not), where its zero export sits and its main site type;
    /// when no case has all three, the site type gives way first, then the zero export. Nil only without any case of
    /// the station's size.
    public static func suggest(site: String?, backfeed: String?, over200kVA: Bool, among cases: [Case]) -> Case? {
        let sized = cases.filter { !$0.site.isEmpty && $0.over200kVA == over200kVA }
        func fits(_ c: Case, site s: String?, backfeed b: String?) -> Bool {
            (s.map { c.site == $0 } ?? true) && (b.map { c.backfeed == $0 } ?? true)
        }
        return sized.first { fits($0, site: site, backfeed: backfeed) }
            ?? sized.first { fits($0, site: nil, backfeed: backfeed) }
            ?? sized.first
    }

    /// A station's main site type: the one with the most kWp in its installation points (`ProjectSetup.points`), else
    /// the one most of its daily-report locations name (`หลังคาลอนคู่ 2` → `หลังคาลอนคู่`). Only the case files' types count.
    public static func mainSite(points: [ProjectSetup.Point], locations: [String], among types: [String]) -> String? {
        let known = Set(types)
        if let p = points.filter({ known.contains($0.type) && $0.count > 0 })
            .max(by: { ($0.kWp, $0.count) < ($1.kWp, $1.count) }) { return p.type }
        var counts: [String: Int] = [:]
        for l in locations {
            // the longest type a location starts with: `หลังคาลอนคู่ 1` is a ลอนคู่ roof, not `หลังคา`
            if let t = known.filter({ l.hasPrefix($0) }).max(by: { $0.count < $1.count }) { counts[t, default: 0] += 1 }
        }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// Every file in `folder` whose title names its station or case, by code. Reads only each file's shared strings,
    /// not its sheets.
    public static func cases(in folder: URL? = bundled) -> [Case] {
        // resolved first: Linux Foundation lists nothing in a folder reached through a link (its test bundle keeps one)
        guard let folder = folder?.resolvingSymlinksInPath(),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return urls.filter { $0.pathExtension == "xlsx" }.compactMap { url -> Case? in
            guard let data = try? Data(contentsOf: url), let strings = (try? ZipArchive(data))?.string("xl/sharedStrings.xml")
            else { return nil }
            let name = url.lastPathComponent, code = String(name.prefix { $0 != " " })
            if let title = title(in: strings), let c = parse(title) {
                return Case(id: code, name: c.site, detail: "", site: c.site, backfeed: c.backfeed, over200kVA: c.over200kVA,
                            kWp: MPWorkbook.station(project: title, fileName: name).kWp, url: url)
            }
            guard let s = station(in: strings) else { return nil }
            return Case(id: code, name: s.name, detail: s.detail, site: "", backfeed: s.backfeed, over200kVA: s.over200kVA,
                        kWp: s.kWp, url: url)
        }
        .sorted { $0.id < $1.id }
    }

    /// A station file's first two shared strings: `แผนโครงการ P3-001 – <station> 163.02 kWp`, then `กปภ.สาขา…, Inverter 160 kW
    /// (ไม่ต้อง พค.2), Zero export HV, …`.
    static func station(in sharedStrings: String) -> (name: String, kWp: Double?, detail: String, backfeed: String, over200kVA: Bool)? {
        let items = sharedStrings.components(separatedBy: "<si>").dropFirst().prefix(4).map { item -> String in
            let text = item.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            return SharedStrings.unescape(text).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let title = items.first(where: { $0.hasPrefix("แผนโครงการ ") }), let dash = title.range(of: " – "),
              let detail = items.first(where: { $0.contains("Zero export") }) else { return nil }
        var name = String(title[dash.upperBound...])
        var kWp: Double?
        if let k = name.range(of: #"\s*[\d,]+(\.\d+)?\s*kWp$"#, options: .regularExpression) {
            kWp = Double(name[k].replacingOccurrences(of: "kWp", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
            name = String(name[..<k.lowerBound])
        }
        guard let ze = detail.range(of: #"Zero export (HV|LV)"#, options: .regularExpression) else { return nil }
        let backfeed = String(detail[ze].suffix(2))
        // พค.2 is the ≥ 200 kVA case's paper
        let over = detail.contains("ต้องยื่น พค.2")
        return (name.trimmingCharacters(in: .whitespaces), kWp, detail, backfeed, over)
    }

    /// The station's own file: its code (`P3-001`) in the job's code or name, else the same station name
    /// (`MPWorkbook.stationKey`).
    public static func best(for stationName: String, code: String, in cases: [Case]) -> Case? {
        let text = (code + " " + stationName).uppercased()
        if let c = cases.first(where: { text.contains($0.id.uppercased()) }) { return c }
        let key = MPWorkbook.stationKey(stationName)
        guard !key.isEmpty else { return nil }
        return cases.first { !$0.site.isEmpty ? false : MPWorkbook.stationKey($0.name) == key }
    }

    /// The first shared string naming a template's case (other texts of the file may say แม่แบบ too).
    static func title(in sharedStrings: String) -> String? {
        var at = sharedStrings.startIndex
        while let mark = sharedStrings.range(of: "แม่แบบ ", range: at..<sharedStrings.endIndex) {
            let start = sharedStrings[..<mark.lowerBound].range(of: ">", options: .backwards)?.upperBound ?? mark.lowerBound
            let end = sharedStrings[mark.upperBound...].range(of: "<")?.lowerBound ?? sharedStrings.endIndex
            let text = SharedStrings.unescape(String(sharedStrings[start..<end]))
            if parse(text) != nil { return text }
            at = mark.upperBound
        }
        return nil
    }

    /// `… แม่แบบ ถังน้ำใส, กันย้อน LV, Inverter ≥ 200 kVA …` (or `·` between the parts): the case a template's title names.
    static func parse(_ title: String) -> (site: String, backfeed: String, over200kVA: Bool)? {
        guard let a = title.range(of: "แม่แบบ "), let b = title.range(of: "กันย้อน ", range: a.upperBound..<title.endIndex)
        else { return nil }
        let site = String(title[a.upperBound..<b.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ·,"))
        let rest = title[b.upperBound...]
        let backfeed = String(rest.prefix { !$0.isWhitespace && $0 != "," && $0 != "·" })
        guard !site.isEmpty, ["HV", "LV"].contains(backfeed), let inv = rest.range(of: "Inverter ") else { return nil }
        let over = rest[inv.upperBound...].hasPrefix("≥")
        guard over || rest[inv.upperBound...].hasPrefix("<") else { return nil }
        return (site, backfeed, over)
    }

    /// The case's file with its plan moved so the kickoff falls on `kickoff`, and that file read back: what a station
    /// takes, as an import of the file would give it. No progress.
    /// `kickoff` nil keeps the file's own dates and progress: a station taking its own plan, as importing its file would.
    public static func plan(_ c: Case, kickoff: Date?, calendar cal: Calendar = MasterSchedule.calendar) throws
        -> (data: Data, imported: MPWorkbook.Imported) {
        let original = try Data(contentsOf: c.url)
        let template = try MPWorkbook.read(original, calendar: cal)
        guard let kickoff else { return (original, template) }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: template.input.kickoff), to: cal.startOfDay(for: kickoff)).day ?? 0
        guard days != 0 else { return (original, template) }
        let out = try MPWorkbook.export(original, input: template.input.shifted(days: days, calendar: cal),
                                        actual: MasterSchedule.Actual(), calendar: cal)
        // export writes the MP plan only: the WBS sheet keeps the template's dates, so its rows move here
        var moved = try MPWorkbook.read(out.data, calendar: cal)
        moved.wbs = moved.wbs.map { $0.shifted(days: days, calendar: cal) }
        // no progress: the rows that station marked done are its own, not ticks for the station taking the plan (an
        // empty base also keeps the import from taking back that station's earlier ticks); its export clears their Y
        moved.wbsDone = []
        moved.wbsDoneDates = [:]
        moved.wbsBase = []
        return (out.data, moved)
    }
}

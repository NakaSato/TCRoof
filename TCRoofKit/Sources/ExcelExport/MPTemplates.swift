import Foundation
import TCRoofCore

/// The team's install templates (`Project_Plan_TCRoof`, docs in its `อ่านก่อน.txt`): one plan workbook per case, site
/// type × กันย้อน HV / LV × inverter under / from 200 kVA, bundled as `PlanTemplates` (a link to the import files, so a
/// regenerated set ships as it is). A station's plan starts from one: the case's plan moved to the station's kickoff,
/// written into a copy of its file, which the station keeps as its own plan workbook (`Job.scheduleWorkbook`).
public enum MPTemplates {
    public struct Case: Identifiable, Hashable, Sendable {
        /// `P9-001`: the file name's code.
        public let id: String
        /// `หลังคาลอนคู่`, `ถังน้ำใส`, `Carport` …, as the file's title names it.
        public let site: String
        /// `HV` or `LV`.
        public let backfeed: String
        public let over200kVA: Bool
        public let kWp: Double?
        public let url: URL

        public var title: String { "\(site) | กันย้อน \(backfeed) | Inverter \(over200kVA ? "≥" : "<") 200 kVA" }
    }

    /// The bundled templates' folder.
    public static var bundled: URL? { Bundle.module.url(forResource: "PlanTemplates", withExtension: nil) }

    /// Every case in `folder`, by code; a file whose title doesn't name its case is left out. Reads only each file's
    /// shared strings for its title (`แผนโครงการ P9-001 – แม่แบบ … 150.48 kWp`), not its sheets.
    public static func cases(in folder: URL? = bundled) -> [Case] {
        guard let folder, let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return urls.filter { $0.pathExtension == "xlsx" }.compactMap { url -> Case? in
            guard let data = try? Data(contentsOf: url), let strings = (try? ZipArchive(data))?.string("xl/sharedStrings.xml"),
                  let title = title(in: strings), let c = parse(title) else { return nil }
            let name = url.lastPathComponent
            return Case(id: String(name.prefix { $0 != " " }), site: c.site, backfeed: c.backfeed, over200kVA: c.over200kVA,
                        kWp: MPWorkbook.station(project: title, fileName: name).kWp, url: url)
        }
        .sorted { $0.id < $1.id }
    }

    /// The first shared string naming a template's case.
    static func title(in sharedStrings: String) -> String? {
        guard let mark = sharedStrings.range(of: "แม่แบบ ") else { return nil }
        let start = sharedStrings[..<mark.lowerBound].range(of: ">", options: .backwards)?.upperBound ?? mark.lowerBound
        let end = sharedStrings[mark.upperBound...].range(of: "<")?.lowerBound ?? sharedStrings.endIndex
        return SharedStrings.unescape(String(sharedStrings[start..<end]))
    }

    /// `… แม่แบบ ถังน้ำใส · กันย้อน LV · Inverter ≥ 200 kVA …`: the case a template's title names.
    static func parse(_ title: String) -> (site: String, backfeed: String, over200kVA: Bool)? {
        guard let a = title.range(of: "แม่แบบ "), let b = title.range(of: " · กันย้อน ", range: a.upperBound..<title.endIndex)
        else { return nil }
        let site = String(title[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rest = title[b.upperBound...]
        let backfeed = String(rest.prefix { !$0.isWhitespace })
        guard !site.isEmpty, ["HV", "LV"].contains(backfeed), let inv = rest.range(of: "Inverter ") else { return nil }
        let over = rest[inv.upperBound...].hasPrefix("≥")
        guard over || rest[inv.upperBound...].hasPrefix("<") else { return nil }
        return (site, backfeed, over)
    }

    /// The case's file with its plan moved so the kickoff falls on `kickoff`, and that file read back: what a station
    /// takes, as an import of the file would give it. No progress.
    public static func plan(_ c: Case, kickoff: Date, calendar cal: Calendar = MasterSchedule.calendar) throws
        -> (data: Data, imported: MPWorkbook.Imported) {
        let original = try Data(contentsOf: c.url)
        let template = try MPWorkbook.read(original, calendar: cal)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: template.input.kickoff), to: cal.startOfDay(for: kickoff)).day ?? 0
        guard days != 0 else { return (original, template) }
        let out = try MPWorkbook.export(original, input: template.input.shifted(days: days, calendar: cal),
                                        actual: MasterSchedule.Actual(), calendar: cal)
        // export writes the MP plan only: the WBS sheet keeps the template's dates, so its rows move here
        var moved = try MPWorkbook.read(out.data, calendar: cal)
        moved.wbs = moved.wbs.map { $0.shifted(days: days, calendar: cal) }
        return (out.data, moved)
    }
}

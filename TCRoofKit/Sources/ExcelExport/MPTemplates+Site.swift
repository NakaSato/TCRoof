import Foundation
import TCRoofCore

/// Each site type's own 2.1 structure sub-tasks (docs/specs/project-plan-wbs.md, step 4): the full plan workbook's
/// `จุดติดตั้ง` sheet names 2.1.1–2.1.7 and splits 2.1's weight differently for a corrugated roof, a metal sheet roof, a
/// clear water tank, a buried tank or a carport; the import files carry only the generic list. `site-steps.json` is made
/// from that sheet by `tools/plan-template/site_steps.py`.
public extension MPTemplates {
    struct SiteStep: Codable, Equatable, Sendable {
        public let step: Int
        public let title: String
        /// Percent of 2.1's weight.
        public let percent: Double
    }

    private struct SiteSteps: Decodable { let sites: [String: [SiteStep]] }

    /// Every site type's steps, by the name the templates' titles use (`หลังคาลอนคู่`, `ถังน้ำใส`, `Carport` …).
    static let siteSteps: [String: [SiteStep]] = {
        guard let url = Bundle.module.url(forResource: "site-steps", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(SiteSteps.self, from: data) else { return [:] }
        return file.sites
    }()

    /// The WBS with 2.1's sub-tasks named and weighted for `site`: 2.1.n takes step n's title and its share of 2.1's
    /// weight, keeping its evidence, owner and dates. Unchanged for a site type the table doesn't have.
    static func applySite(_ site: String, to wbs: [MasterSchedule.WorkItem]) -> [MasterSchedule.WorkItem] {
        guard let steps = siteSteps[site], let line = wbs.first(where: { $0.code == "2.1" }) else { return wbs }
        let byStep = Dictionary(steps.map { ($0.step, $0) }) { a, _ in a }
        return wbs.map { item in
            let parts = item.code.split(separator: ".")
            guard parts.count == 3, parts[0] == "2", parts[1] == "1", let n = Int(parts[2]), let step = byStep[n] else { return item }
            var i = item
            i.title = step.title
            i.weight = line.weight * step.percent / 100
            return i
        }
    }
}

extension MPWorkbook {
    /// A template file's WBS with its site type's 2.1 sub-tasks, when the sheet's title names the case.
    static func siteSpecific(_ items: [MasterSchedule.WorkItem], sheet s: Sheet) -> [MasterSchedule.WorkItem] {
        guard !items.isEmpty, let title = s.texts.first(where: { $0.text.contains("แม่แบบ ") && $0.text.contains("กันย้อน") })?.text,
              let c = MPTemplates.parse(title) else { return items }
        return MPTemplates.applySite(c.site, to: items)
    }
}

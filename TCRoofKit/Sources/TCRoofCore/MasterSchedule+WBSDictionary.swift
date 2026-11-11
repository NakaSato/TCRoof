import Foundation

/// The Master Plan's WBS Dictionary (CHA-84): for each WBS code what "done" means (PMBOK 7th's Definition of Done), how it
/// earns credit (PMBOK 5th's rules of credit: `ร่าง 10% → ยื่น 50% → อนุมัติ 100%`, `50/50`), the documents that prove it
/// and the app record that stands for it. Bundled as `Resources/wbs-dictionary.json`, written from the template
/// workbook's `WBS Dictionary` sheet by `tools/plan-template/wbs_dictionary.py`. A row ticked in the app takes one of
/// its credit steps (`WBSTick.percent`), and 100 % of a row whose dictionary lists documents needs a document number or
/// an app record (`problem`).
public extension MasterSchedule {
    struct WBSDictionary: Codable, Equatable, Sendable {
        public struct Step: Codable, Equatable, Sendable {
            /// `ร่าง`, `ยื่น`, `อนุมัติ`, `เริ่ม`, `เสร็จ`.
            public var label: String
            public var percent: Double
            public init(label: String, percent: Double) { self.label = label; self.percent = percent }
        }

        public struct Entry: Codable, Equatable, Sendable {
            public var title: String?
            /// เกณฑ์เสร็จ / Deliverable.
            public var done: String?
            /// The rules of credit as the sheet words them.
            public var credit: String?
            /// The credit's steps, the last 100; nil when a tick is all or nothing.
            public var steps: [Step]?
            /// หลักฐาน (เอกสาร): the documents that prove it done.
            public var evidence: [String]?
            public var photos: String?
            /// บันทึก / ยืนยันในแอป TCRoof: the app record that stands for it.
            public var record: String?

            public init(title: String? = nil, done: String? = nil, credit: String? = nil, steps: [Step]? = nil,
                        evidence: [String]? = nil, photos: String? = nil, record: String? = nil) {
                self.title = title; self.done = done; self.credit = credit; self.steps = steps
                self.evidence = evidence; self.photos = photos; self.record = record
            }

            /// The percents a tick may take: its steps', else 100 only.
            public var percents: [Double] { steps?.map(\.percent) ?? [100] }
            public var needsEvidence: Bool { !(evidence ?? []).isEmpty }
            /// Signed ICL sheets of its task stand for it (`ใบตรวจรับงาน (ICL)`).
            public var byICL: Bool { record?.contains("ICL") == true }

            /// The step of `percent`, when the row has steps.
            public func step(_ percent: Double) -> Step? { steps?.first { abs($0.percent - percent) < 1e-9 } }
        }

        public var revision: String?
        public var entries: [String: Entry]

        public init(revision: String? = nil, entries: [String: Entry]) { self.revision = revision; self.entries = entries }

        /// The dictionary bundled with the app; empty if it can't be read.
        public static let bundled: WBSDictionary = {
            guard let url = Bundle.module.url(forResource: "wbs-dictionary", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let d = try? JSONDecoder().decode(WBSDictionary.self, from: data)
            else { return WBSDictionary(entries: [:]) }
            return d
        }()

        public func entry(_ code: String) -> Entry? { entries[code] }

        /// The percents a tick of `code` may take; 100 only for a row the dictionary doesn't have.
        public func percents(_ code: String) -> [Double] { entry(code)?.percents ?? [100] }

        // MARK: app records

        /// What the app's own records say of the rows: the ICL groups (`2.3`) whose sheets are all signed, and each
        /// station paper's status by kind (`StationDocs`).
        public struct Records: Equatable, Sendable {
            public var iclSigned: Set<String>
            public var papers: [String: StationDocs.Status]
            public init(iclSigned: Set<String> = [], papers: [String: StationDocs.Status] = [:]) {
                self.iclSigned = iclSigned; self.papers = papers
            }
        }

        /// The credit a record gives a row, and what it is.
        public struct Credit: Equatable, Sendable {
            public var percent: Double
            public var label: String
        }

        /// The credit the app's records give `item`: 100 once its task's ICL sheets are all signed (a row the dictionary
        /// confirms through the ICL), and for a row whose note names station papers (`หลักฐาน: site_map`) the step those
        /// papers reached (approved → 100, submitted → `ยื่น` / `ส่ง`, drafted or signed → `ร่าง`). Nil when no record
        /// says.
        public func credit(_ item: WorkItem, records: Records) -> Credit? {
            let entry = entry(item.code)
            if entry?.byICL == true, let task = item.task, records.iclSigned.contains(task.code) {
                return Credit(percent: 100, label: "ใบ ICL \(task.code) ลงนามครบแล้ว")
            }
            let kinds = item.evidenceKinds
            let statuses = kinds.compactMap { records.papers[$0] }
            guard !kinds.isEmpty, statuses.count == kinds.count else { return nil }
            if statuses.allSatisfy({ $0 == .approved || $0 == .notNeeded }) {
                return Credit(percent: 100, label: "เอกสารสถานีอนุมัติแล้ว")
            }
            let rank: [StationDocs.Status: Int] = [.missing: 0, .requested: 0, .draft: 1, .signed: 1, .submitted: 2, .approved: 3, .notNeeded: 3]
            let least = statuses.min { (rank[$0] ?? 0) < (rank[$1] ?? 0) } ?? .missing
            let words: [String]
            switch least {
            case .submitted: words = ["ยื่น", "ส่ง"]
            case .draft, .signed: words = ["ร่าง"]
            default: return nil
            }
            guard let step = entry?.steps?.first(where: { s in words.contains { s.label.hasPrefix($0) } }) else { return nil }
            return Credit(percent: step.percent, label: "เอกสารสถานี: \(least.title)")
        }

        // MARK: checks

        /// Why `percent` of `code` can't be booked, nil when it can: a row with credit steps takes only those, any other
        /// only 100, and 100 of a row whose dictionary lists documents needs a document number or a record that gives it.
        public func problem(_ item: WorkItem, percent: Double, document: String?, records: Records = .init()) -> String? {
            let allowed = percents(item.code)
            guard allowed.contains(where: { abs($0 - percent) < 1e-9 }) else {
                return "งานนี้นับได้ " + allowed.map { WBSDictionary.percentText($0) }.joined(separator: " / ")
            }
            guard percent >= 100 - 1e-9, let e = entry(item.code), e.needsEvidence else { return nil }
            if !(document ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            if credit(item, records: records)?.percent ?? 0 >= 100 - 1e-9 { return nil }
            return "ใส่เลขที่เอกสารก่อนนับ 100%: " + (e.evidence ?? []).joined(separator: ", ")
        }

        /// `50%`, `100%`.
        public static func percentText(_ p: Double) -> String {
            p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p)
        }
    }
}

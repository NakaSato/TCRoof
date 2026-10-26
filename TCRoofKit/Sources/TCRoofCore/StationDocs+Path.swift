import Foundation

/// The iPad install page's `เอกสาร` tab (docs/ui/install-tracking-ipad-docs): the station's permit papers as a
/// three-step path, a four-state legend and each paper's draft → submit → approve level.
public extension StationDocs {
    /// The summary's legend.
    enum Legend: Equatable, Sendable, CaseIterable {
        /// `ต้องทำ`: missing, drafted or signed, still the team's to do.
        case todo
        /// `รอผู้อื่น`: requested or submitted, waiting on someone outside the team.
        case waiting
        /// `ครบ / อนุมัติ`: approved.
        case done
        /// `ยังไม่ถึง`: not needed at this station (yet).
        case notYet

        public var title: String {
            switch self {
            case .todo: "ต้องทำ"
            case .waiting: "รอผู้อื่น"
            case .done: "ครบ / อนุมัติ"
            case .notYet: "ยังไม่ถึง"
            }
        }
    }

    static func legend(_ s: Status) -> Legend {
        switch s {
        case .approved: .done
        case .requested, .submitted: .waiting
        case .missing, .draft, .signed: .todo
        case .notNeeded: .notYet
        }
    }

    /// How far a paper is along `ร่าง → ยื่น → อนุมัติ`: 0 nothing yet, 1 drafted or signed, 2 handed in or asked for,
    /// 3 approved.
    static func flowLevel(_ s: Status) -> Int {
        switch s {
        case .approved: 3
        case .submitted, .requested: 2
        case .draft, .signed: 1
        case .missing, .notNeeded: 0
        }
    }

    /// The permit path, in filing order: the municipality, the utility's grid connection, the ERC's พค.2. The test and
    /// the hand-over stay on the overview's tiles.
    static let permitPath: [(package: Package, agency: String)] = [(.building, "เทศบาล"), (.gridConnection, "กฟภ."), (.pk2, "กกพ.")]

    /// The step's title: the building step follows the municipality's decision (both while it is unknown).
    static func pathTitle(_ p: Package, route: BuildingRoute) -> String {
        switch p {
        case .building: switch route {
            case .unknown: "อ.1 / แจ้งเทศบาล"
            case .permit: "อ.1 (ขออนุญาต)"
            case .notify: "แจ้งเทศบาล"
            }
        case .gridConnection: "ขนานไฟ (กฟภ.)"
        case .pk2: "พค.2 (กกพ.)"
        case .commissioning, .handover: p.title
        }
    }

    struct PathStep: Equatable, Sendable, Identifiable {
        public let number: Int
        public let package: Package
        public let agency: String
        public let title: String
        /// The station files this package (no พค.2 under 200 kVA).
        public let applies: Bool
        public let progress: Progress
        public var id: String { package.rawValue }
        /// Done, or nothing to file: the arrow after it turns green.
        public var cleared: Bool { !applies || progress.isComplete }

        /// `ครบ r/t`, `กำลังยื่น` or `ไม่ต้องยื่น`.
        public var chip: String { !applies ? "ไม่ต้องยื่น" : progress.isComplete ? "ครบ \(progress.ready)/\(progress.total)" : "กำลังยื่น" }
        /// `ยื่นครบแล้ว`, `n ฉบับยังไม่เสร็จ` or `ต่ำกว่า 200 kVA`.
        public var note: String {
            !applies ? "ต่ำกว่า 200 kVA" : progress.isComplete ? "ยื่นครบแล้ว" : "\(progress.total - progress.ready) ฉบับยังไม่เสร็จ"
        }
    }

    static func path(station: Station, library: Library, _ ctx: Context) -> [PathStep] {
        let applies = Set(packages(ctx))
        return permitPath.enumerated().map { i, s in
            let on = applies.contains(s.package)
            return PathStep(number: i + 1, package: s.package, agency: s.agency, title: pathTitle(s.package, route: ctx.buildingRoute),
                            applies: on, progress: on ? progress(s.package, station: station, library: library, ctx) : Progress(ready: 0, total: 0))
        }
    }

    /// The step opened first: the first one with work left, else step 1.
    static func defaultStep(_ steps: [PathStep]) -> Package {
        steps.first { $0.applies && !$0.progress.isComplete }?.package ?? steps.first?.package ?? .building
    }

    /// The tab's summary over every paper on the path, each counted once (a paper filed in two packages is one file).
    struct PathSummary: Equatable, Sendable {
        public var counts: [Legend: Int] = [:]
        public var packages = 0
        public func count(_ l: Legend) -> Int { counts[l] ?? 0 }
        /// Papers that count: all but those not needed.
        public var total: Int { count(.todo) + count(.waiting) + count(.done) }
        public var done: Int { count(.done) }
    }

    static func pathSummary(station: Station, library: Library, _ ctx: Context) -> PathSummary {
        var out = PathSummary(), seen = Set<String>()
        for step in path(station: station, library: library, ctx) where step.applies {
            out.packages += 1
            for k in papers(in: step.package, ctx) where seen.insert(k.id).inserted {
                out.counts[legend(state(k, station: station, library: library).status), default: 0] += 1
            }
        }
        return out
    }

    /// Where a paper comes from, as the row's second line: `ทีมเราทำ`, `ดึงจากคลังกลาง`, `ขอจาก กปภ.สาขา`,
    /// `เราร่าง → ผจก. กปภ.สาขาลงนาม`, with the signer of a paper the team makes.
    static func source(_ k: Kind) -> String {
        switch k.origin {
        case .internalDoc:
            if k.scope.isShared { return "ดึงจากคลังกลาง" }
            return k.signBy.map { "ทีมเราทำ | " + $0 } ?? "ทีมเราทำ"
        case .signoff: return k.signBy.map { "เราร่าง → " + $0 + "ลงนาม" } ?? Origin.signoff.title
        case .external:
            if k.scope.isShared { return "ดึงจากคลังกลาง" }
            return k.obtainFrom.map { "ขอจาก " + $0 } ?? Origin.external.title
        }
    }

    /// A paper's code in its package: the section and its place, `4.2-07`.
    static func code(section: String, index: Int) -> String { String(format: "%@-%02d", section, index + 1) }
}

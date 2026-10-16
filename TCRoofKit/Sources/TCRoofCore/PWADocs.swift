import Foundation

/// The iPhone `เอกสาร PWA` page (docs/ui/pwa-docs-iphone-v2): every PWA station's papers at once, by station, as a
/// to-do list and as the shared library. Worked out from `StationDocs` over the stations the plan page uses
/// (`PWAPlan.Station`) and the device library; nothing here is stored.
public enum PWADocs {

    // MARK: Summary

    /// The summary bar's five parts, in the bar's order.
    public enum Band: CaseIterable, Sendable {
        /// `อนุมัติแล้ว`
        case approved
        /// `ยื่นแล้ว`: submitted, or signed and waiting to go in.
        case submitted
        /// `รอลงนาม`: sent to PWA to sign, or asked of an outside office.
        case waiting
        /// `ร่าง`
        case draft
        /// `ยังไม่มี`
        case missing

        public init?(_ status: StationDocs.Status) {
            switch status {
            case .approved: self = .approved
            case .submitted, .signed: self = .submitted
            case .requested: self = .waiting
            case .draft: self = .draft
            case .missing: self = .missing
            case .notNeeded: return nil
            }
        }
    }

    public struct Summary: Equatable, Sendable {
        /// Papers of each band; `notNeeded` papers are in none.
        public var bands: [Band: Int]
        /// Open papers by who has them: ours to make, drafted for PWA to sign, asked of an outside office.
        public var open: [StationDocs.Origin: Int]

        public var total: Int { bands.values.reduce(0, +) }
        public var approved: Int { bands[.approved] ?? 0 }
        /// Approved share, 0–100.
        public var percent: Int { total == 0 ? 0 : Int((Double(approved) / Double(total) * 100).rounded()) }
    }

    /// Every station's papers it needs (site papers of the packages it takes part in, `notNeeded` left out), plus
    /// each shared library paper once.
    public static func summary(_ stations: [PWAPlan.Station], library: StationDocs.Library) -> Summary {
        var s = Summary(bands: [:], open: [:])
        func add(_ kind: StationDocs.Kind, _ status: StationDocs.Status) {
            guard let band = Band(status) else { return }
            s.bands[band, default: 0] += 1
            if !status.isReady { s.open[kind.origin, default: 0] += 1 }
        }
        for st in stations {
            for kind in sitePapers(st.docsContext) { add(kind, StationDocs.state(kind, station: st.docs, library: library).status) }
        }
        for kind in libraryKinds { add(kind, StationDocs.state(kind, station: .init(), library: library).status) }
        return s
    }

    /// A station's own papers (not the shared ones) over its packages, once each, in catalog order.
    public static func sitePapers(_ ctx: StationDocs.Context) -> [StationDocs.Kind] {
        let packages = StationDocs.packages(ctx)
        return StationDocs.kinds.filter { k in
            !k.scope.isShared && StationDocs.applies(k, ctx) && k.packages.contains(where: packages.contains)
        }
    }

    /// The papers kept once for every station, in catalog order.
    public static var libraryKinds: [StationDocs.Kind] { StationDocs.kinds.filter(\.scope.isShared) }

    // MARK: Stepper

    /// The station card's four steps. `ทดสอบระบบ` isn't one: its papers are all in `ส่งมอบงาน` too.
    public static let steps: [(package: StationDocs.Package, title: String)] =
        [(.building, "อ.1"), (.gridConnection, "ขนานไฟ"), (.pk2, "พค.2"), (.handover, "ส่งมอบ")]

    public enum StepState: Equatable, Sendable {
        case done, current, later
        /// `ไม่ต้องยื่น`: พค.2 under 200 kVA.
        case skip
    }

    public struct Step: Equatable, Sendable {
        public var package: StationDocs.Package
        public var title: String
        public var state: StepState
        public var progress: StationDocs.Progress
    }

    /// A package is done once every paper it needs is submitted or approved (as the plan page's deadlines have it); the
    /// first one that isn't is current. A package with no papers needed counts as done.
    public static func stepper(_ st: PWAPlan.Station, library: StationDocs.Library) -> [Step] {
        let needed = StationDocs.packages(st.docsContext)
        var reachedCurrent = false
        return steps.map { step in
            let pr = StationDocs.progress(step.package, station: st.docs, library: library, st.docsContext)
            guard needed.contains(step.package) else { return Step(package: step.package, title: step.title, state: .skip, progress: pr) }
            let complete = isIn(step.package, st, library: library)
            let state: StepState
            if reachedCurrent { state = complete ? .done : .later }
            else if complete { state = .done }
            else { state = .current; reachedCurrent = true }
            return Step(package: step.package, title: step.title, state: state, progress: pr)
        }
    }

    /// Every paper the package needs is submitted or approved.
    static func isIn(_ package: StationDocs.Package, _ st: PWAPlan.Station, library: StationDocs.Library) -> Bool {
        let gone: Set<StationDocs.Status> = [.submitted, .approved, .notNeeded]
        return StationDocs.papers(in: package, st.docsContext).allSatisfy { kind in
            gone.contains(StationDocs.state(kind, station: st.docs, library: library).status)
        }
    }

    // MARK: Stations

    /// Where a station stands, in the list's order.
    public enum StationState: Int, Comparable, Sendable {
        /// The current package's day has come and it isn't in yet: `ครบกำหนด`.
        case late
        /// The next paper is ours to make or draft: `ทีมเรา`.
        case ours
        /// Waiting for PWA to sign or hand a paper over: `รอ กปภ.`.
        case waitingPWA
        /// Waiting for an outside office: `รอเทศบาล`, `รอ กฟภ.`.
        case waitingOutside
        /// Every paper of the current package is ready to go in: `พร้อมยื่น`; or every package is in: `ครบ`.
        case ready

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        public var isOurs: Bool { self == .late || self == .ours }
        public var isWaiting: Bool { self == .waitingPWA || self == .waitingOutside }
    }

    public struct StationRow: Identifiable, Sendable {
        public var station: PWAPlan.Station
        public var steps: [Step]
        public var state: StationState
        /// The tag's words: `ครบกำหนด`, `ทีมเรา`, `รอ กปภ.`, `รอเทศบาล`, `พร้อมยื่น`, `ครบ`.
        public var tag: String
        /// The first open paper of the current package.
        public var next: StationDocs.Kind?
        /// The current package's due day.
        public var due: Date?
        /// The plan's install end.
        public var handover: Date?
        public var id: String { station.id }
    }

    /// The day a package's papers are due: the day the team set, else the MP plan's (its task's planned start, the
    /// install end for the handover). Nil without either.
    public static func due(_ package: StationDocs.Package, _ st: PWAPlan.Station) -> Date? {
        if let d = st.docs.due(package) { return d }
        guard let input = st.input else { return nil }
        if package == .handover || package == .commissioning { return input.installEnd }
        guard let task = PWAPlan.submissionTask(package) else { return nil }
        return MasterSchedule.plan(input).first { $0.task == task }?.start
    }

    /// Who an outside paper waits on, short: `เทศบาล / อบต.` → `เทศบาล`.
    static func office(_ kind: StationDocs.Kind) -> String {
        (kind.obtainFrom ?? "หน่วยงานนอก").components(separatedBy: " / ").first ?? ""
    }

    static func waitsOnPWA(_ kind: StationDocs.Kind) -> Bool {
        kind.origin == .signoff || (kind.obtainFrom ?? "").contains("กปภ.")
    }

    public static func row(_ st: PWAPlan.Station, library: StationDocs.Library, today: Date) -> StationRow {
        let cal = MasterSchedule.calendar
        let steps = stepper(st, library: library)
        let handover = st.input?.installEnd
        guard let current = steps.first(where: { $0.state == .current }) else {
            return StationRow(station: st, steps: steps, state: .ready, tag: "ครบ", next: nil, due: nil, handover: handover)
        }
        let open = StationDocs.papers(in: current.package, st.docsContext).filter {
            let s = StationDocs.state($0, station: st.docs, library: library).status
            return !s.isReady && s != .notNeeded
        }
        // our own papers first: what the team can move today
        let next = open.first { isOurs($0, StationDocs.state($0, station: st.docs, library: library).status) } ?? open.first
        let due = due(current.package, st)
        var state: StationState, tag: String
        if let next {
            if isOurs(next, StationDocs.state(next, station: st.docs, library: library).status) { state = .ours; tag = "ทีมเรา" }
            else if waitsOnPWA(next) { state = .waitingPWA; tag = "รอ กปภ." }
            else { state = .waitingOutside; tag = "รอ" + office(next) }
        } else {
            state = .ready; tag = "พร้อมยื่น"
        }
        if let due, cal.startOfDay(for: due) <= cal.startOfDay(for: today) { state = .late; tag = "ครบกำหนด" }
        return StationRow(station: st, steps: steps, state: state, tag: tag, next: next, due: due, handover: handover)
    }

    /// The station list's filter.
    public enum StationFilter: String, CaseIterable, Sendable {
        /// `ต้องทำ`: late, or the next paper is ours.
        case todo
        /// `รอผู้อื่น`: waiting for PWA or an outside office.
        case waiting
        case all

        public func holds(_ s: StationState) -> Bool {
            switch self {
            case .todo: s.isOurs
            case .waiting: s.isWaiting
            case .all: true
            }
        }
    }

    /// Rows sorted late → ours → waiting PWA → waiting outside → ready, then by due day, then in the given order.
    public static func rows(_ stations: [PWAPlan.Station], library: StationDocs.Library, today: Date) -> [StationRow] {
        stations.map { row($0, library: library, today: today) }.enumerated().sorted { a, b in
            if a.element.state != b.element.state { return a.element.state < b.element.state }
            switch (a.element.due, b.element.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    public static func matches(_ row: StationRow, search: String) -> Bool {
        PWAPlan.matches([row.station.ref, row.station.name] + sitePapers(row.station.docsContext).map(\.name), search)
    }

    // MARK: To do

    /// One open paper on the to-do list: a station's, or a library paper (no station).
    public struct Item: Identifiable, Sendable {
        public var kind: StationDocs.Kind
        public var status: StationDocs.Status
        public var station: PWAPlan.Station?
        /// The package the due day comes from.
        public var package: StationDocs.Package?
        public var due: Date?
        public var id: String { (station?.id ?? "library") + "/" + kind.id }

        /// Ours to move: an internal paper, or a sign-off paper not yet sent to PWA.
        public var isOurs: Bool { PWADocs.isOurs(kind, status) }

        /// `MP 77 โชคชัย`, or `คลังกลาง`.
        public var place: String { station.map { $0.ref + " " + $0.shortName } ?? "คลังกลาง" }

        /// Who has it next: the signer, the office asked, or the package.
        public var who: String {
            switch kind.origin {
            case .signoff: kind.signBy ?? package?.title ?? ""
            case .external: kind.obtainFrom ?? ""
            case .internalDoc: kind.signBy.map { "รอ" + $0 } ?? package.map(stepTitle) ?? ""
            }
        }

        /// `ยังไม่มี`, `ร่าง`, `รอลงนาม`, `รอรับ`.
        public var statusWord: String {
            switch status {
            case .missing: "ยังไม่มี"
            case .draft: "ร่าง"
            case .requested: kind.origin == .signoff ? "รอลงนาม" : "รอรับ"
            default: status.title
            }
        }

        public func isLate(today: Date) -> Bool { days(today: today).map { $0 < 0 } ?? false }

        /// Days from today to the due day; negative when late.
        public func days(today: Date) -> Int? {
            let cal = MasterSchedule.calendar
            return due.flatMap { cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: $0)).day }
        }
    }

    static func isOurs(_ kind: StationDocs.Kind, _ status: StationDocs.Status) -> Bool {
        kind.origin == .internalDoc || (kind.origin == .signoff && status != .requested)
    }

    public static func stepTitle(_ p: StationDocs.Package) -> String { steps.first { $0.package == p }?.title ?? p.title }

    public struct Group: Identifiable, Sendable {
        public var origin: StationDocs.Origin
        public var items: [Item]
        public var id: StationDocs.Origin { origin }
        /// Papers of the group the app can draft (`แอปสร้างได้ m`).
        public var draftable: Int { items.filter { StationDocs.draft(for: $0.kind) != nil }.count }
    }

    /// Every paper not ready yet, in three groups by origin (internal, sign-off, external), each by due day with the
    /// undated ones last. A paper in several packages is due on the earliest of them.
    public static func todo(_ stations: [PWAPlan.Station], library: StationDocs.Library) -> [Group] {
        var items: [Item] = []
        for st in stations {
            let packages = StationDocs.packages(st.docsContext)
            for kind in sitePapers(st.docsContext) {
                let status = StationDocs.state(kind, station: st.docs, library: library).status
                guard !status.isReady, status != .notNeeded else { continue }
                let dated = kind.packages.filter(packages.contains).compactMap { p in due(p, st).map { (p, $0) } }.min { $0.1 < $1.1 }
                items.append(Item(kind: kind, status: status, station: st,
                                  package: dated?.0 ?? kind.packages.first(where: packages.contains), due: dated?.1))
            }
        }
        for kind in libraryKinds {
            let status = StationDocs.state(kind, station: .init(), library: library).status
            guard !status.isReady, status != .notNeeded else { continue }
            items.append(Item(kind: kind, status: status, station: nil, package: kind.packages.first, due: nil))
        }
        let sorted = items.enumerated().sorted { a, b in
            switch (a.element.due, b.element.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
        return StationDocs.Origin.allCases.map { o in Group(origin: o, items: sorted.filter { $0.kind.origin == o }) }
    }

    public static func matches(_ item: Item, search: String) -> Bool {
        PWAPlan.matches([item.kind.name, item.station?.ref ?? "", item.station?.name ?? ""], search)
    }

    // MARK: Library

    public enum Pill: Equatable, Sendable {
        /// `ล่าสุด`: a ready paper that isn't expiring.
        case latest
        /// `ยังไม่มี`: no ready paper yet.
        case missing
        /// `n วัน`
        case soon(days: Int)
        /// `หมดอายุ`
        case expired
        /// `ไม่ใช้`
        case notNeeded
    }

    public struct LibraryRow: Identifiable, Sendable {
        public var kind: StationDocs.Kind
        public var state: StationDocs.DocState
        public var pill: Pill
        public var id: String { kind.id }
    }

    public static func pill(_ kind: StationDocs.Kind, _ state: StationDocs.DocState, today: Date, warnDays: Int = 30) -> Pill {
        if state.status == .notNeeded { return .notNeeded }
        switch StationDocs.expiry(kind, state, on: today, warnDays: warnDays, calendar: MasterSchedule.calendar) {
        case .expired: return .expired
        case .soon(let days): return .soon(days: days)
        case nil: return state.status.isReady ? .latest : .missing
        }
    }

    public static func library(_ library: StationDocs.Library, today: Date, warnDays: Int = 30) -> [LibraryRow] {
        libraryKinds.map { k in
            let s = StationDocs.state(k, station: .init(), library: library)
            return LibraryRow(kind: k, state: s, pill: pill(k, s, today: today, warnDays: warnDays))
        }
    }

    public static func matches(_ row: LibraryRow, search: String) -> Bool { PWAPlan.matches([row.kind.name], search) }

    /// The library paper nearest to running out (an expired one first), for the page's banner; nil when none is
    /// within `warnDays`.
    public static func nearestExpiry(_ rows: [LibraryRow]) -> LibraryRow? {
        rows.compactMap { r -> (LibraryRow, Int)? in
            switch r.pill {
            case .expired: (r, -1)
            case .soon(let d): (r, d)
            default: nil
            }
        }.min { $0.1 < $1.1 }?.0
    }
}

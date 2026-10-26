import Foundation

/// What the iPad `เอกสาร` page (docs/ui/pwa-docs-ipad) adds over the iPhone page: the late count, a station's open
/// papers, the contractor filter and sort, the status steps of a paper, the library's use and expiry marks, and the
/// search across stations, papers and the library. Worked out; nothing here is stored.
extension PWADocs {

    // MARK: Counts

    /// Open papers late or due today: the switch's red `ต้องทำ n` on iPad.
    public static func dueNow(_ groups: [Group], today: Date) -> Int {
        groups.flatMap(\.items).filter { ($0.days(today: today) ?? 1) <= 0 }.count
    }

    /// Late or due today, for one column of `ต้องทำ`.
    public static func dueNow(_ group: Group, today: Date) -> Int { dueNow([group], today: today) }

    /// Every paper a station needs over the packages it takes part in, its own and the shared ones, once each, in
    /// catalog order.
    public static func stationPapers(_ ctx: StationDocs.Context) -> [StationDocs.Kind] {
        let packages = StationDocs.packages(ctx)
        return StationDocs.kinds.filter { StationDocs.applies($0, ctx) && $0.packages.contains(where: packages.contains) }
    }

    /// The station's papers not ready yet (`ขาด n`); papers marked not needed are left out.
    public static func open(_ st: PWAPlan.Station, library: StationDocs.Library) -> [StationDocs.Kind] {
        stationPapers(st.docsContext).filter {
            let s = StationDocs.state($0, station: st.docs, library: library).status
            return !s.isReady && s != .notNeeded
        }
    }

    /// Stations whose needed papers include this one: a library paper's `ใช้ใน n สถานี`.
    public static func usedIn(_ kind: StationDocs.Kind, _ stations: [PWAPlan.Station]) -> [PWAPlan.Station] {
        stations.filter { st in stationPapers(st.docsContext).contains { $0.id == kind.id } }
    }

    // MARK: Station list

    /// The contractors named on the stations, in order: the filter's chips.
    public static func contractors(_ stations: [PWAPlan.Station]) -> [String] {
        Array(Set(stations.map(\.contractor).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public enum StationSort: String, CaseIterable, Sendable {
        /// `เรียง: วันส่งมอบ`: the plan's hand-over day, earliest first, undated last.
        case handover
        /// `เรียง: ขาดมากสุด`: most open papers first.
        case missing
    }

    /// The rows in that order; ties keep the rows' own order (late first, then by due day).
    public static func sorted(_ rows: [StationRow], by sort: StationSort, library: StationDocs.Library) -> [StationRow] {
        let missing = Dictionary(rows.map { ($0.id, open($0.station, library: library).count) }) { a, _ in a }
        return rows.enumerated().sorted { a, b in
            switch sort {
            case .handover:
                switch (a.element.handover, b.element.handover) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            case .missing:
                let x = missing[a.element.id] ?? 0, y = missing[b.element.id] ?? 0
                if x != y { return x > y }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Papers

    /// The พค.2 check list item a paper answers, for `พค.2 ข้อ n | …`.
    public static func checkNumber(_ kind: StationDocs.Kind) -> Int? {
        StationDocs.pk2Checklist.first { $0.docs.contains(kind.id) }?.number
    }

    /// A to-do card's title: a พค.2 paper by its check list number.
    public static func title(_ item: Item) -> String {
        guard item.package == .pk2, let n = checkNumber(item.kind) else { return item.kind.name }
        return "พค.2 ข้อ \(n) | " + item.kind.name
    }

    /// A paper's status steps as the document sheet shows them: done steps, and the one it is at (nil once through).
    public struct Flow: Equatable, Sendable {
        public var labels: [String]
        /// Steps before this index are done.
        public var done: Int
        public var current: Int?
    }

    /// Our papers: `ยังไม่มี | ร่าง | รอลงนาม | ยื่นแล้ว | อนุมัติ`, a signed paper past `รอลงนาม`. Outside ones:
    /// `ยังไม่มี | ขอแล้ว | ได้รับแล้ว`, done once received.
    public static func flow(_ origin: StationDocs.Origin, _ status: StationDocs.Status) -> Flow {
        if origin == .external {
            let labels = ["ยังไม่มี", "ขอแล้ว", "ได้รับแล้ว"]
            switch status {
            case .missing: return Flow(labels: labels, done: 0, current: 0)
            case .requested, .draft: return Flow(labels: labels, done: 1, current: 1)
            case .signed, .submitted, .approved: return Flow(labels: labels, done: 3, current: nil)
            case .notNeeded: return Flow(labels: labels, done: 0, current: nil)
            }
        }
        let labels = ["ยังไม่มี", "ร่าง", "รอลงนาม", "ยื่นแล้ว", "อนุมัติ"]
        switch status {
        case .missing: return Flow(labels: labels, done: 0, current: 0)
        case .draft: return Flow(labels: labels, done: 1, current: 1)
        case .requested: return Flow(labels: labels, done: 2, current: 2)
        case .signed, .submitted: return Flow(labels: labels, done: 3, current: 3)
        case .approved: return Flow(labels: labels, done: 5, current: nil)
        case .notNeeded: return Flow(labels: labels, done: 0, current: nil)
        }
    }

    /// Where a paper goes when a file is uploaded into its slot: a sign-off paper back from PWA is submitted (the
    /// signed copy), before that it is a draft; our own paper is submitted; an outside paper has been received. An
    /// approved paper stays approved when its file is replaced, and nothing goes back.
    public static func statusAfterUpload(_ kind: StationDocs.Kind, _ status: StationDocs.Status) -> StationDocs.Status {
        if status == .approved { return .approved }
        switch kind.origin {
        case .signoff:
            switch status {
            case .requested, .signed, .submitted: return .submitted
            default: return .draft
            }
        case .internalDoc: return .submitted
        case .external: return .approved
        }
    }

    /// Papers whose card asks to mask the ID card before it is attached (`ต้องปิดข้อมูลบนบัตร`).
    public static func isIDCard(_ kind: StationDocs.Kind) -> Bool { kind.id == "grantor_docs" || kind.id == "grantee_docs" }

    /// The station's papers updated most recently (`ความเคลื่อนไหว`).
    public static func recent(_ st: PWAPlan.Station, library: StationDocs.Library, limit: Int = 2)
        -> [(kind: StationDocs.Kind, state: StationDocs.DocState)] {
        stationPapers(st.docsContext).compactMap { k -> (kind: StationDocs.Kind, state: StationDocs.DocState)? in
            let s = StationDocs.state(k, station: st.docs, library: library)
            return s.updatedAt == nil ? nil : (k, s)
        }
        .sorted { ($0.state.updatedAt ?? .distantPast) > ($1.state.updatedAt ?? .distantPast) }
        .prefix(limit).map { $0 }
    }

    /// A letter number the team wrote into the note (`ที่ กปภ.ข.1 123/2569`, `เลขที่ TC-PML-001/2569`); there is no
    /// field of its own.
    public static func letterNumber(_ note: String) -> String? {
        let pattern = #"(?:เลขที่|ที่)\s*([^\s,·]*\d+/\d{2,4})"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: note, range: NSRange(note.startIndex..., in: note)),
              let r = Range(m.range(at: 1), in: note) else { return nil }
        return String(note[r])
    }

    // MARK: Library

    /// The library's groups on iPad, in order: `ระดับ กปภ.`, `ผู้รับจ้าง`, `โครงการ`, `สาขา กปภ.`.
    public static let libraryScopes: [StationDocs.Scope] = [.org, .contractor, .project, .branch]

    /// One library paper on the expiry track (`หมดอายุใน 12 เดือน`).
    public struct ExpiryMark: Identifiable, Sendable {
        public var kind: StationDocs.Kind
        /// Days left; 0 for one already out of date.
        public var days: Int
        public var expired: Bool
        public var id: String { kind.id }
    }

    /// Library papers that expire within a year (or have), soonest first.
    public static func expiryMarks(_ rows: [LibraryRow], today: Date) -> [ExpiryMark] {
        let cal = MasterSchedule.calendar
        return rows.compactMap { r -> ExpiryMark? in
            guard r.kind.expires, r.state.status != .notNeeded, let end = r.state.expiresAt,
                  let days = cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: end)).day,
                  days <= 365 else { return nil }
            return ExpiryMark(kind: r.kind, days: max(days, 0), expired: days < 0)
        }
        .sorted { $0.days < $1.days }
    }

    // MARK: Search

    /// One search result: a station, one of its papers, or a library paper.
    public struct Hit: Identifiable, Sendable {
        public enum Kind: Sendable { case station, paper, library }
        public var type: Kind
        public var station: PWAPlan.Station?
        public var kind: StationDocs.Kind?
        public var state: StationDocs.DocState?
        /// The package the paper is shown under.
        public var package: StationDocs.Package?
        public var id: String { "\(type)/\(station?.id ?? "")/\(kind?.id ?? "")" }
    }

    /// Stations by MP number or name; their own papers by name or note (a letter number); library papers by name or
    /// note. Stations first, then papers, then the library.
    public static func search(_ query: String, stations: [PWAPlan.Station], library: StationDocs.Library) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out = stations.filter { PWAPlan.matches([$0.ref, $0.code, $0.name], q) }.map { Hit(type: .station, station: $0) }
        for st in stations {
            let packages = StationDocs.packages(st.docsContext)
            for k in sitePapers(st.docsContext) {
                let s = StationDocs.state(k, station: st.docs, library: library)
                guard PWAPlan.matches([k.name, s.note], q) else { continue }
                out.append(Hit(type: .paper, station: st, kind: k, state: s, package: k.packages.first(where: packages.contains)))
            }
        }
        for k in libraryKinds {
            let s = StationDocs.state(k, station: .init(), library: library)
            if PWAPlan.matches([k.name, s.note], q) { out.append(Hit(type: .library, kind: k, state: s)) }
        }
        return out
    }
}

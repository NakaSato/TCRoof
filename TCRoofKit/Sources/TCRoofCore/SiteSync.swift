import Foundation

/// A2 ↔ A3 / B4 (docs/ui/a2-a3-autofill): the symbols on the site picture fill the transformer / MDB page and the B4
/// zero-export level, and edits there come back onto the symbols.
/// - transformer mark: `value` (kVA) ↔ `trafos[i].kva`
/// - MDB mark: `label` ↔ the board's name (`tr{i}_feed` for a main board), `value` (AT) ↔ its `at` through `setBoards`
/// - กันย้อน mark: `value` "MV" / "LV" ↔ the linked B4's `level` (`ZeroExport.hv` / `.lv`)
/// - PEA meter mark: position only, counted as linked
/// Empty targets are filled; a different non-empty value is a conflict the surveyor settles (`useA2` / `keepA3`).
public enum SiteSync {
    public static let marksKey = ModuleMarks.key
    public static let trafosKey = "trafos"
    /// The panel's footnote: symbols that don't reach A3.
    public static let notSent = "ไม่ส่งมาหน้านี้: INV | Weather | Site Office | อาคาร"

    public enum Status: Equatable, Sendable {
        case filled, same
        case conflict(a3: String, a2: String)
        case skipped(String)
        /// Filled or already the same: counted in `ดึงจากภาพ A2 | N รายการ`.
        public var isLinked: Bool { self == .filled || self == .same }
        public var isConflict: Bool { if case .conflict = self { return true } else { return false } }
    }

    /// One linked mark, one row of A3's panel.
    public struct Item: Identifiable, Equatable, Sendable {
        /// The mark's id.
        public var id: UUID
        public var kind: MarkKind
        /// Text in the row's symbol pill: "PEA METER", "TX 1", "MDB", "กันย้อน".
        public var symbol: String
        /// "หม้อแปลง TX 1 | 630 kVA"
        public var title: String
        /// "หม้อแปลง TX 1 | ชื่อ + ขนาด"
        public var target: String
        public var status: Status
        /// Unit after the A2 value in a conflict line ("kVA", "AT"); nil for none.
        public var unit: String?
    }

    /// A3 / B4 fields whose value came from, or matches, a linked mark: they carry the `A2` badge.
    public enum Field: Hashable, Sendable {
        case meter
        case kva(Int)
        case boardName(Int, Int)
        case boardAT(Int, Int)
        case level(UUID)
    }

    // MARK: public API

    /// A2 → A3 / B4: fills empty targets, creates transformer cards for new marks, stores links and reports conflicts.
    /// `previous` is the marks before an A2 edit: a target still holding a mark's previous value follows the mark, so
    /// typing "6", "63", "630" doesn't end in a conflict. Never overwrites any other non-empty value. Idempotent.
    @discardableResult
    public static func push(_ job: inout Job, previous: [MapMark]? = nil) -> [Item] {
        run(&job, previous: previous, force: [:]).items
    }

    /// The panel's rows (what `push` reports) and the fields to badge, from one run without writing.
    public struct Summary: Equatable, Sendable {
        public var items: [Item] = []
        public var badges: Set<Field> = []
        public init() {}
    }
    public static func summary(_ job: Job) -> Summary {
        var copy = job
        return run(&copy, previous: nil, force: [:])
    }
    /// The panel's rows: what `push` reports, without writing.
    public static func items(_ job: Job) -> [Item] { summary(job).items }
    /// Fields to badge on A3 / B4.
    public static func badges(_ job: Job) -> Set<Field> { summary(job).badges }

    /// Everything `summary` reads: equal inputs give an equal summary, so a page can keep one until they change.
    public struct Inputs: Equatable, Sendable {
        let marks: [MapMark]
        let trafos: [Transformer]
        let feeds: [String]
        /// "<B4 id>:<level>" in module order (an unlinked กันย้อน mark takes the n-th B4).
        let levels: [String]
        public init(_ job: Job) {
            marks = job.values.marks(marksKey)
            trafos = job.values.transformers(trafosKey)
            feeds = (0..<Transformer.maxTransformers).map { job.values.text("tr\($0)_feed") }
            levels = job.modules.filter { $0.type == .backfeed }.map { "\($0.id):\($0.values.choice(ZeroExport.levelKey) ?? "")" }
        }
    }

    /// What a linked mark points at, for A2's chip `↔ A3 TX 1` / `↔ A3 MDP-1` / `↔ B4`: "A3 TX 1", "A3 MDP-1", "B4"; nil when unlinked.
    public static func linkTitle(_ job: Job, mark m: MapMark) -> String? {
        switch m.kind {
        case .trafo:
            guard let id = linkID(m.link, "tr"), let i = job.values.transformers(trafosKey).firstIndex(where: { $0.id == id }) else { return nil }
            return "A3 TX \(i + 1)"
        case .mdb:
            guard let id = linkID(m.link, "bd"), let b = board(id, in: job) else { return nil }
            let name = b.name.trimmingCharacters(in: .whitespaces)
            return "A3 " + (name.isEmpty ? "MDB" : name)
        case .zeroExport:
            guard let id = m.module, job.modules.contains(where: { $0.id == id && $0.type == .backfeed }) else { return nil }
            return "B4"
        default: return nil
        }
    }

    /// Conflict resolution: A3 / B4 take the mark's values.
    public static func useA2(_ job: inout Job, mark: UUID) { run(&job, previous: nil, force: [mark: .a2]) }
    /// Conflict resolution: the mark takes A3's / B4's values.
    public static func keepA3(_ job: inout Job, mark: UUID) { run(&job, previous: nil, force: [mark: .a3]) }

    /// A3 / B4 → A2: after an edit there, a linked mark whose target changed since `before` takes the new value.
    /// Only linked marks change; clearing a value on A3 leaves the mark as it was.
    public static func pull(_ job: inout Job, since before: Job) {
        var marks = job.values.marks(marksKey)
        guard !marks.isEmpty else { return }
        for i in marks.indices {
            switch marks[i].kind {
            case .trafo:
                guard let id = linkID(marks[i].link, "tr"),
                      let new = trafo(id, in: job)?.kva, new != trafo(id, in: before)?.kva, !clean(new).isEmpty else { continue }
                marks[i].value = clean(new)
            case .mdb:
                guard let id = linkID(marks[i].link, "bd"), let now = board(id, in: job) else { continue }
                let was = board(id, in: before)
                if now.name != was?.name, !now.name.trimmingCharacters(in: .whitespaces).isEmpty { marks[i].label = now.name }
                if now.at != was?.at, !clean(now.at).isEmpty { marks[i].value = clean(now.at) }
            case .zeroExport:
                guard let id = marks[i].module, let new = level(job, id), new != level(before, id), !new.isEmpty else { continue }
                marks[i].value = new
            default: continue
            }
        }
        if marks != job.values.marks(marksKey) { job.values[marksKey] = .marks(marks) }
    }

    // MARK: matching

    enum Side { case a2, a3 }

    /// "630 kVA" → "630": trimmed, without a trailing unit.
    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        for unit in ["kva", "at", "a"] where t.lowercased().hasSuffix(unit) {
            t = String(t.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return t
    }
    /// Comparison key: `clean`, case-insensitive, no spaces.
    static func same(_ a: String, _ b: String) -> Bool { key(a) == key(b) }
    static func key(_ s: String) -> String { clean(s).lowercased().replacingOccurrences(of: " ", with: "") }

    static func linkID(_ link: String?, _ prefix: String) -> UUID? {
        guard let link, link.hasPrefix(prefix + ":") else { return nil }
        return UUID(uuidString: String(link.dropFirst(prefix.count + 1)))
    }

    static func trafo(_ id: UUID, in job: Job) -> Transformer? { job.values.transformers(trafosKey).first { $0.id == id } }

    /// A board by id with its name as A3 shows it (`tr{i}_feed` for a main board).
    static func board(_ id: UUID, in job: Job) -> (name: String, at: String)? {
        for (i, t) in job.values.transformers(trafosKey).enumerated() {
            guard let k = t.boards.firstIndex(where: { $0.id == id }) else { continue }
            return (k == 0 ? job.values.text("tr\(i)_feed") : t.boards[k].name, t.boards[k].at)
        }
        return nil
    }

    /// The B4's level as a mark writes it: "MV", "LV" or "".
    static func level(_ job: Job, _ module: UUID) -> String? {
        guard let m = job.modules.first(where: { $0.id == module && $0.type == .backfeed }) else { return nil }
        switch m.values.choice(ZeroExport.levelKey) {
        case ZeroExport.hv?: return "MV"
        case ZeroExport.lv?: return "LV"
        default: return ""
        }
    }

    /// An MDB name the surveyor didn't type: empty, or the placed default ("MDB", "MDB-2").
    static func isDefaultBoardName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == "MDB" || (t.hasPrefix("MDB-") && Int(t.dropFirst(4)) != nil)
    }

    /// Settles one A2 / A3 pair. Fills the empty side, follows a mark the target was copying (`previous`), or applies
    /// `force` to a conflict.
    static func settle(a3: inout String, a2: inout String, previous: String?, force: Side?) -> Status {
        let x = clean(a3), y = clean(a2)
        if y.isEmpty {
            if !x.isEmpty { a2 = x }
            return .same
        }
        if x.isEmpty { a3 = y; return .filled }
        if same(x, y) { return .same }
        if let p = previous, same(p, x) { a3 = y; return .filled }
        switch force {
        case .a2?: a3 = y; return .filled
        case .a3?: a2 = x; return .same
        case nil: return .conflict(a3: x, a2: y)
        }
    }

    static func combine(_ a: Status, _ b: Status) -> Status {
        if a.isConflict { return a }
        if b.isConflict { return b }
        return a == .filled || b == .filled ? .filled : .same
    }

    // MARK: engine

    @discardableResult
    static func run(_ job: inout Job, previous: [MapMark]?, force: [UUID: Side]) -> Summary {
        var marks = job.values.marks(marksKey)
        guard !marks.isEmpty else { return Summary() }
        var trafos = job.values.transformers(trafosKey)
        var out = Summary()
        let before = Dictionary((previous ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [UUID: Item] = [:]

        // transformers: linked marks first, then the unlinked ones by position among the unclaimed transformers
        let trafoMarks = marks.indices.filter { marks[$0].kind == .trafo }
        var trafoOf: [Int: Int] = [:]
        for mi in trafoMarks {
            if let id = linkID(marks[mi].link, "tr"), let t = trafos.firstIndex(where: { $0.id == id }) { trafoOf[mi] = t }
        }
        var free = trafos.indices.filter { !trafoOf.values.contains($0) }
        var created: Set<Int> = []
        for mi in trafoMarks where trafoOf[mi] == nil {
            let m = marks[mi]
            if linkID(m.link, "tr") != nil {   // its transformer was removed on A3: never re-create it
                items[m.id] = trafoItem(m, marks: marks, index: nil, status: .skipped("ลบที่ A3 แล้ว"))
                continue
            }
            if !free.isEmpty { trafoOf[mi] = free.removeFirst(); continue }
            guard trafos.count < Transformer.maxTransformers else {
                items[m.id] = trafoItem(m, marks: marks, index: nil, status: .skipped("เกิน 5 ลูก"))
                continue
            }
            trafos.append(Transformer(kva: clean(m.value)))
            trafoOf[mi] = trafos.count - 1
            created.insert(trafos.count - 1)
        }
        for (mi, t) in trafoOf {
            var m = marks[mi]
            m.link = "tr:\(trafos[t].id)"
            var status = settle(a3: &trafos[t].kva, a2: &m.value, previous: before[m.id]?.value, force: force[m.id])
            if created.contains(t) { status = .filled }
            marks[mi] = m
            items[m.id] = trafoItem(m, marks: marks, index: t, status: status)
            if status.isLinked, !clean(trafos[t].kva).isEmpty { out.badges.insert(.kva(t)) }
        }

        // MDB marks: linked boards first, then main boards of the transformers not yet claimed
        let mdbMarks = marks.indices.filter { marks[$0].kind == .mdb }
        var boardOf: [Int: (Int, Int)] = [:]
        for mi in mdbMarks {
            guard let id = linkID(marks[mi].link, "bd") else { continue }
            for (t, tr) in trafos.enumerated() {
                if let k = tr.boards.firstIndex(where: { $0.id == id }) { boardOf[mi] = (t, k) }
            }
        }
        var freeMains = trafos.indices.filter { t in !boardOf.values.contains { $0.0 == t && $0.1 == 0 } }
        for mi in mdbMarks where boardOf[mi] == nil {
            let m = marks[mi]
            if linkID(m.link, "bd") != nil {
                items[m.id] = boardItem(m, marks: marks, at: nil, status: .skipped("ลบที่ A3 แล้ว"))
                continue
            }
            guard !freeMains.isEmpty else {
                items[m.id] = boardItem(m, marks: marks, at: nil, status: .skipped("ยังไม่มีหม้อแปลงใน A3"))
                continue
            }
            let t = freeMains.removeFirst()
            // older jobs keep boards in mdb[]: store them so the main board has an id to link
            var b = trafos[t].resolvedBoards
            if b.isEmpty { b = [Board(name: "", isMain: true)] }
            trafos[t].setBoards(b)
            boardOf[mi] = (t, 0)
        }
        for (mi, (t, k)) in boardOf {
            var m = marks[mi]
            m.link = "bd:\(trafos[t].boards[k].id)"
            let prev = before[m.id]
            // name: main boards keep theirs in tr{t}_feed
            var a3Name = k == 0 ? job.values.text("tr\(t)_feed") : trafos[t].boards[k].name
            var a2Name = isDefaultBoardName(m.label) ? "" : m.label
            let nameStatus = settle(a3: &a3Name, a2: &a2Name, previous: prev.map(\.label), force: force[m.id])
            if !a2Name.isEmpty { m.label = a2Name }
            if k == 0 {
                job.values["tr\(t)_feed"] = a3Name.isEmpty ? nil : .text(a3Name)
            } else {
                trafos[t].boards[k].name = a3Name
            }
            var boards = trafos[t].boards
            let atStatus = settle(a3: &boards[k].at, a2: &m.value, previous: prev?.value, force: force[m.id])
            trafos[t].setBoards(boards)
            marks[mi] = m
            let status = combine(nameStatus, atStatus)
            items[m.id] = boardItem(m, marks: marks, at: (t, k), status: status)
            if !a3Name.isEmpty, same(a3Name, a2Name) || nameStatus == .filled { out.badges.insert(.boardName(t, k)) }
            if atStatus.isLinked, !clean(boards[k].at).isEmpty { out.badges.insert(.boardAT(t, k)) }
        }

        // กันย้อน marks → their B4
        for mi in marks.indices where marks[mi].kind == .zeroExport {
            var m = marks[mi]
            if m.module.map({ id in !job.modules.contains { $0.id == id && $0.type == .backfeed } }) ?? true {
                m.module = job.modules.first { $0.type == .backfeed && ZeroExport.mark(job, module: $0.id)?.id == m.id }?.id
            }
            guard let id = m.module, let k = job.modules.firstIndex(where: { $0.id == id }) else {
                marks[mi] = m
                items[m.id] = levelItem(m, level: "", status: .skipped("ยังไม่มีหน้า B4"))
                continue
            }
            var a3 = level(job, id) ?? ""
            var a2 = m.value.trimmingCharacters(in: .whitespaces).uppercased()
            let status = settle(a3: &a3, a2: &a2, previous: before[m.id]?.value.uppercased(), force: force[m.id])
            m.value = a2
            switch a3 {
            case "MV": job.modules[k].values[ZeroExport.levelKey] = .choice(ZeroExport.hv, other: "")
            case "LV": job.modules[k].values[ZeroExport.levelKey] = .choice(ZeroExport.lv, other: "")
            default: break
            }
            marks[mi] = m
            items[m.id] = levelItem(m, level: a3, status: status)
            if status.isLinked, !a3.isEmpty { out.badges.insert(.level(id)) }
        }

        for m in marks where m.kind == .meter {
            items[m.id] = Item(id: m.id, kind: .meter, symbol: "PEA METER", title: "มิเตอร์ กฟภ. | มีบนภาพ", target: "การ์ดมิเตอร์ กฟภ.",
                               status: .same, unit: nil)
            out.badges.insert(.meter)
        }

        if marks != job.values.marks(marksKey) { job.values[marksKey] = .marks(marks) }
        if trafos != job.values.transformers(trafosKey) { job.values[trafosKey] = trafos.isEmpty ? nil : .transformers(trafos) }
        // rows in the panel's order: meter, transformers, MDBs, กันย้อน; each in picture order
        let order: [MarkKind] = [.meter, .trafo, .mdb, .zeroExport]
        out.items = order.flatMap { k in marks.filter { $0.kind == k }.compactMap { items[$0.id] } }
        return out
    }

    // MARK: rows

    static func trafoItem(_ m: MapMark, marks: [MapMark], index: Int?, status: Status) -> Item {
        let name = m.label.trimmingCharacters(in: .whitespaces).isEmpty ? SiteMarks.defaultLabel(m, in: marks) : m.label
        let target: String
        if case .skipped(let why) = status { target = why } else { target = "หม้อแปลง TX \((index ?? 0) + 1) | ชื่อ + ขนาด" }
        return Item(id: m.id, kind: .trafo, symbol: name, title: "หม้อแปลง \(name)" + (m.rating.isEmpty ? "" : " | \(m.rating)"),
                    target: target, status: status, unit: "kVA")
    }

    static func boardItem(_ m: MapMark, marks: [MapMark], at place: (Int, Int)?, status: Status) -> Item {
        let name = isDefaultBoardName(m.label) ? SiteMarks.defaultLabel(m, in: marks) : m.label
        let target: String
        if case .skipped(let why) = status { target = why }
        else if let (t, k) = place { target = (k == 0 ? "ตู้หลัก TX \(t + 1)" : "ตู้ย่อย TX \(t + 1)") + " | ชื่อตู้ + AT เมนเบรกเกอร์" }
        else { target = "" }
        return Item(id: m.id, kind: .mdb, symbol: "MDB", title: name + (m.rating.isEmpty ? "" : " | \(m.rating)"),
                    target: target, status: status, unit: "AT")
    }

    static func levelItem(_ m: MapMark, level: String, status: Status) -> Item {
        let target: String
        if case .skipped(let why) = status { target = why }
        else { target = "B4 กันย้อน | ระดับ" + (level == "MV" ? ": " + ZeroExport.hv : level == "LV" ? ": " + ZeroExport.lv : "") }
        let line = m.value.isEmpty ? "ZERO EXPORT" : "ZERO EXPORT \(SiteMarks.zeroExportLine(m))"
        return Item(id: m.id, kind: .zeroExport, symbol: "กันย้อน", title: line, target: target, status: status, unit: nil)
    }
}

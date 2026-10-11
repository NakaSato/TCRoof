import Foundation

/// B1 building panels (`.panel` sections) shown together on one page (docs/ui/survey-b1): each card's status, the link to
/// the A3 breaker that feeds the panel, the daytime load against the PV size, and what is still missing. Pure values.
public enum BuildingPanels {
    public enum Key {
        /// "{trafoIndex}/{boardId}/{breakerId}" of the A3 breaker feeding the panel.
        public static let a3Breaker = "a3Breaker"
        /// The PV connection point marked on `photoWide` (a `.pvPoint` shape).
        public static let pvPoint = "pvPoint"
        /// Spare breaker slots in the panel.
        public static let spareSlots = "spareSlots"
        public static let photoWide = "photoWide", photoBreaker = "photoBreaker"
        public static let breakerAT = "breakerAT", loadKW = "loadKW", loadTime = "loadTime"
    }

    /// Time chips under the load; `ตอนนี้` stores the current time.
    public static let timeChips = ["10:00", "12:00", "14:00"]

    /// "09:42" — what the `ตอนนี้` chip stores.
    public static func nowTime(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// A stored load time as "HH:mm": "10:00", "10 น.", "10.30", "9:05 น." → "10:00", "10:00", "10:30", "09:05"; nil when not a time.
    public static func clockTime(_ s: String) -> String? {
        let digits = s.replacingOccurrences(of: "น.", with: "").trimmingCharacters(in: .whitespaces)
        let parts = digits.split { $0 == ":" || $0 == "." }.map(String.init)
        guard (1...2).contains(parts.count), let h = Int(parts[0]), (0..<24).contains(h) else { return nil }
        let m = parts.count == 2 ? Int(parts[1]) : 0
        guard let m, (0..<60).contains(m) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: A3 breakers

    /// One outgoing breaker of an A3 board.
    public struct BreakerRef: Hashable, Sendable {
        public var trafo: Int
        public var board: UUID
        public var breaker: UUID
        public init(trafo: Int, board: UUID, breaker: UUID) { self.trafo = trafo; self.board = board; self.breaker = breaker }
        /// "0/{boardId}/{breakerId}"
        public var key: String { "\(trafo)/\(board.uuidString)/\(breaker.uuidString)" }
        public init?(_ key: String) {
            let p = key.split(separator: "/").map(String.init)
            guard p.count == 3, let t = Int(p[0]), let b = UUID(uuidString: p[1]), let r = UUID(uuidString: p[2]) else { return nil }
            self.init(trafo: t, board: b, breaker: r)
        }
    }

    /// A breaker the panel can be linked to: `MDP-1 · CB1 400 AT`.
    public struct Option: Hashable, Identifiable, Sendable {
        public var ref: BreakerRef
        public var boardName: String
        /// 1-based position on its board (the SLD's CB number).
        public var number: Int
        public var at: String
        /// The B1 section already linked to it, if any.
        public var linkedTo: UUID?
        public var id: String { ref.key }
        /// "CB1 · 400 AT" / "CB1"
        public var cbText: String { "CB\(number)" + (at.isEmpty ? "" : " · \(at) AT") }
        /// "MDP-1 · CB1 400 AT"
        public var label: String { "\(boardName) · CB\(number)" + (at.isEmpty ? "" : " \(at) AT") }
    }

    static func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

    /// Every outgoing breaker of every A3 board, in diagram order.
    public static func options(_ job: Job) -> [Option] {
        var out: [Option] = []
        let panels = job.modules.filter { $0.type == .panel }
        for (i, tr) in job.values.transformers("trafos").enumerated() {
            for (k, bd) in tr.boards.enumerated() {
                let name = t(bd.name).isEmpty ? (k == 0 && !t(job.values.text("tr\(i)_feed")).isEmpty ? t(job.values.text("tr\(i)_feed")) : "MDB\(k + 1)") : t(bd.name)
                for (j, br) in bd.breakers.enumerated() {
                    let ref = BreakerRef(trafo: i, board: bd.id, breaker: br.id)
                    out.append(Option(ref: ref, boardName: name, number: j + 1, at: t(br.at),
                                      linkedTo: panels.first { $0.values.text(Key.a3Breaker) == ref.key }?.id))
                }
            }
        }
        return out
    }

    /// The A3 breaker a section is linked to (nil when unlinked or the breaker was removed from A3).
    public static func linked(_ m: SurveyModule, in job: Job) -> Option? {
        let key = m.values.text(Key.a3Breaker)
        guard !key.isEmpty else { return nil }
        return options(job).first { $0.ref.key == key }
    }

    /// The B1 section an A3 breaker is linked to.
    public static func panel(linkedTo breaker: UUID, in job: Job) -> SurveyModule? {
        job.modules.first { $0.type == .panel && BreakerRef($0.values.text(Key.a3Breaker))?.breaker == breaker }
    }

    /// "B1" / "B1.2"
    public static func number(_ m: SurveyModule, in job: Job) -> String {
        job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? m.type.code
    }
    /// The building's name, or its section number when unnamed.
    public static func name(_ m: SurveyModule, in job: Job) -> String { t(m.name).isEmpty ? number(m, in: job) : t(m.name) }

    /// What the A3 breaker's target says: "ตู้ไฟฟ้า โรงสูบน้ำ (B1.1)".
    public static func targetText(_ m: SurveyModule, in job: Job) -> String {
        let n = t(m.name)
        return "ตู้ไฟฟ้า " + (n.isEmpty ? "" : n + " ") + "(\(number(m, in: job)))"
    }

    /// Changes a breaker on the A3 diagram.
    static func editBreaker(_ job: inout Job, _ ref: BreakerRef, _ change: (inout Breaker) -> Void) {
        var trafos = job.values.transformers("trafos")
        guard trafos.indices.contains(ref.trafo), let k = trafos[ref.trafo].boards.firstIndex(where: { $0.id == ref.board }),
              let j = trafos[ref.trafo].boards[k].breakers.firstIndex(where: { $0.id == ref.breaker }) else { return }
        change(&trafos[ref.trafo].boards[k].breakers[j])
        job.values["trafos"] = .transformers(trafos)
    }

    /// Links section `id` to an A3 breaker (nil unlinks). Writes `breakerAT` from the breaker and its `target`; the old breaker's
    /// target is cleared, and a building that was linked to the new breaker loses that link.
    public static func link(_ job: inout Job, panel id: UUID, to ref: BreakerRef?) {
        guard let i = job.modules.firstIndex(where: { $0.id == id }) else { return }
        if let old = BreakerRef(job.modules[i].values.text(Key.a3Breaker)), old != ref {
            editBreaker(&job, old) { $0.target = "" }
        }
        guard let ref else { job.modules[i].values[Key.a3Breaker] = nil; return }
        for k in job.modules.indices where k != i && job.modules[k].type == .panel && job.modules[k].values.text(Key.a3Breaker) == ref.key {
            job.modules[k].values[Key.a3Breaker] = nil
        }
        job.modules[i].values[Key.a3Breaker] = .text(ref.key)
        let target = targetText(job.modules[i], in: job)
        var at = ""
        editBreaker(&job, ref) { $0.target = target; at = t($0.at) }
        if !at.isEmpty { job.modules[i].values[Key.breakerAT] = .text(at) }
    }

    /// Keeps the linked breaker's AT and target in step after A3 or the name changed.
    public static func refresh(_ job: inout Job, panel id: UUID) {
        guard let m = job.modules.first(where: { $0.id == id }), let ref = BreakerRef(m.values.text(Key.a3Breaker)) else { return }
        link(&job, panel: id, to: ref)
    }

    /// Renames a building and the target of its A3 breaker.
    public static func rename(_ job: inout Job, panel id: UUID, to name: String) {
        guard let i = job.modules.firstIndex(where: { $0.id == id }) else { return }
        job.modules[i].name = name
        refresh(&job, panel: id)
    }

    /// Removes a building and clears the A3 target that pointed to it.
    public static func delete(_ job: inout Job, panel id: UUID) {
        link(&job, panel: id, to: nil)
        job.modules.removeAll { $0.id == id }
    }

    // MARK: card

    public enum Pill: Hashable, Sendable {
        case complete
        case photos(Int)
        case noLoad
        public var text: String {
            switch self {
            case .complete: return "ครบ"
            case .photos(let n): return "\(n)/2 ภาพ"
            case .noLoad: return "ยังไม่กรอกโหลด"
            }
        }
        public var ok: Bool { self == .complete }
    }

    static func photoCount(_ v: Values) -> Int { [Key.photoWide, Key.photoBreaker].filter { v.photo($0) != nil }.count }
    static func hasLoad(_ v: Values) -> Bool { v.number(Key.loadKW) != nil }

    /// `ครบ` with both photos and the load; else the photo count while one is missing; else `ยังไม่กรอกโหลด`.
    public static func pill(_ v: Values) -> Pill {
        let n = photoCount(v)
        if n < 2 { return .photos(n) }
        return hasLoad(v) ? .complete : .noLoad
    }

    /// "CB1 · 400 AT · โหลด 85 kW" / "CB2 · 250 AT · ยังไม่กรอกโหลด"; AT from the A3 link, else `breakerAT`.
    public static func subLine(_ m: SurveyModule, in job: Job) -> String {
        let link = linked(m, in: job), at = link.map(\.at) ?? t(m.values.text(Key.breakerAT))
        var parts: [String] = []
        if let link { parts.append("CB\(link.number)") }
        if !at.isEmpty { parts.append("\(at) AT") }
        if parts.isEmpty { parts.append("ยังไม่ผูก A3") }
        parts.append(m.values.number(Key.loadKW).map { "โหลด \(fmt($0)) kW" } ?? "ยังไม่กรอกโหลด")
        return parts.joined(separator: " · ")
    }

    // MARK: daytime load

    /// PV size (kW): Σ B2 `invSizes` when picked, else A1 `capacity`.
    public static func pvKW(_ job: Job) -> Double? {
        let picked = job.modules.filter { $0.type == .inverter && !$0.values.text(InverterStation.Key.sizes).isEmpty }
        if !picked.isEmpty { return Double(picked.reduce(0) { $0 + InverterStation($1.values).totalKW }) }
        return job.values.number("capacity").flatMap { $0 > 0 ? $0 : nil }
    }

    public struct DaytimeNote: Hashable, Sendable {
        public var load: Double
        /// Buildings without a load yet.
        public var missing: [String]
        public var pv: Double?
        /// Σ load < PV: zero export (B4) is needed.
        public var needsZeroExport: Bool
        /// "โหลดกลางวันรวม 107 kW (ยังขาดโรงกรอง) · PV 120 kW"
        public var lead: String {
            "โหลดกลางวันรวม \(fmt(load)) kW" + (missing.isEmpty ? "" : " (ยังขาด\(missing.joined(separator: ", ")))") + (pv.map { " · PV \(fmt($0)) kW" } ?? " · PV ? kW")
        }
        public var conclusion: String { needsZeroExport ? "ต้องมีระบบกันย้อน (B4)" : "โหลดมากกว่า PV · กันย้อนยังแนะนำตามเงื่อนไข กฟภ." }
        public var text: String { lead + " → " + conclusion }
    }

    /// The note under the load; nil until one building has a load.
    public static func daytimeNote(_ job: Job) -> DaytimeNote? {
        let panels = job.modules.filter { $0.type == .panel }
        let loads = panels.compactMap { $0.values.number(Key.loadKW) }
        guard !loads.isEmpty else { return nil }
        let total = loads.reduce(0, +), pv = pvKW(job)
        return DaytimeNote(load: total, missing: panels.filter { !hasLoad($0.values) }.map { name($0, in: job) }, pv: pv,
                           needsZeroExport: pv.map { total < $0 } ?? false)
    }

    // MARK: bottom status

    /// "ภาพเบรกเกอร์ โรงสูบน้ำ", "โรงกรอง ทั้ง 2 ภาพ", "โหลด โรงกรอง" across every B1 section; empty when all are filled.
    public static func missing(_ job: Job) -> [String] {
        var breaker: [String] = [], wide: [String] = [], both: [String] = [], load: [String] = []
        for m in job.modules where m.type == .panel {
            let v = m.values, n = name(m, in: job), w = v.photo(Key.photoWide) != nil, b = v.photo(Key.photoBreaker) != nil
            if !w && !b { both.append(n) } else if !b { breaker.append(n) } else if !w { wide.append(n) }
            if !hasLoad(v) { load.append(n) }
        }
        var out: [String] = []
        if !breaker.isEmpty { out.append("ภาพเบรกเกอร์ " + breaker.joined(separator: ", ")) }
        if !wide.isEmpty { out.append("ภาพมุมกว้าง " + wide.joined(separator: ", ")) }
        out += both.map { "\($0) ทั้ง 2 ภาพ" }
        if !load.isEmpty { out.append("โหลด " + load.joined(separator: ", ")) }
        return out
    }
    /// One building's gaps, the same checks as `missing`: "ภาพมุมกว้าง", "ภาพเบรกเกอร์", "โหลด" (the iPad bar's chip).
    public static func missingItems(_ v: Values) -> [String] {
        var out: [String] = []
        if v.photo(Key.photoWide) == nil { out.append("ภาพมุมกว้าง") }
        if v.photo(Key.photoBreaker) == nil { out.append("ภาพเบรกเกอร์") }
        if !hasLoad(v) { out.append("โหลด") }
        return out
    }
    /// "ยังขาด: ภาพเบรกเกอร์ โรงสูบน้ำ · โรงกรอง ทั้ง 2 ภาพ" / "ครบทุกอาคาร"
    public static func statusLine(_ job: Job) -> String {
        let m = missing(job)
        return m.isEmpty ? "ครบทุกอาคาร" : "ยังขาด: " + m.joined(separator: " · ")
    }

    /// "จุดเชื่อมต่อ PV · ช่องว่าง 2 ช่อง"
    public static func pointLabel(_ v: Values) -> String {
        "จุดเชื่อมต่อ PV" + (v.number(Key.spareSlots).map { " · ช่องว่าง \(fmt($0)) ช่อง" } ?? "")
    }
}

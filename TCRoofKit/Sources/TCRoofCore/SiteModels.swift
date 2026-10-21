import Foundation

/// A building model dropped on the A2 site picture (docs/ui/survey-a2 v2 §5). Only the position is stored; the size is read
/// live from the survey section it stands for, so editing that section resizes the model.
public struct SiteModel: Codable, Hashable, Identifiable, Sendable {
    /// The source section's module id.
    public var id: String
    /// Centre as fractions (0…1) of the picture's width and height, like `MapMark`.
    public var x: Double
    public var y: Double
    /// Degrees clockwise.
    public var rotation: Double
    /// Kept where it was placed (the toolbar's global lock also holds it).
    public var locked: Bool
    public init(id: String, x: Double, y: Double, rotation: Double = 0, locked: Bool = false) {
        self.id = id; self.x = min(max(x, 0), 1); self.y = min(max(y, 0), 1); self.rotation = rotation; self.locked = locked
    }
    enum CodingKeys: String, CodingKey { case id, x, y, rotation, locked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

public enum SiteModels {
    /// Values key of the placed models (JSON text, so older app versions still read the job); hidden from the form.
    public static let key = "siteModels"
    /// Values key of the toolbar's "ล็อก": "1" holds every model in place.
    public static let lockKey = "siteModelsLocked"

    /// A survey section that can be dropped on the picture.
    public struct Source: Identifiable, Hashable, Sendable {
        public enum Skin: Sendable { case tank, roof, building }
        /// The section's module id (`SiteModel.id`).
        public let id: String
        /// "D1", "C1.2"
        public let code: String
        /// "ถังน้ำใส | 1 (ใหม่)"
        public let name: String
        public let skin: Skin
        /// PV area (tank, roof) or electrical building.
        public let isPV: Bool
        /// Metres across (ก) and along (ย); nil until the section has them.
        public let width: Double?
        public let length: Double?
        /// Position in the survey's steps (1-based) and their count: "ขั้น 12/13".
        public let step: Int
        public let steps: Int
        /// "400 แผง" for PV areas.
        public let extra: String

        public var title: String { code + " " + name }
        public var hasSize: Bool { (width ?? 0) > 0 && (length ?? 0) > 0 }
        /// "40 × 40 ม."
        public var sizeText: String { hasSize ? fmt(width!) + " × " + fmt(length!) + " ม." : "ยังไม่มีขนาด" }
        /// "ขั้น 12/13 | 40 × 40 ม. | 400 แผง"
        public var subtitle: String { (["ขั้น \(step)/\(steps)", sizeText] + (extra.isEmpty ? [] : [extra])).joined(separator: " | ") }
        public var color: RGBA { isPV ? RGBA(hex: 0x1F6FB5) : RGBA(hex: 0x178A7D) }
    }

    /// B1 building size (metres), entered on the A2 building-model panel; hidden from the B1 form.
    public static let buildingWidthKey = "bldW", buildingLengthKey = "bldL"

    /// One card per tank, roof, B1 building and B2 inverter area, in that order (PV areas first), numbered as in the survey.
    public static func sources(_ job: Job) -> [Source] {
        let steps = job.steps
        let numbered = job.sectionsByCategory.flatMap(\.sections)
        let order: [ModuleType] = [.tank, .roof, .panel, .inverter]
        return order.flatMap { t in
            numbered.filter { $0.module.type == t }.map { s -> Source in
                let v = s.module.values
                let step = (steps.firstIndex { $0.page == .module(s.module.id) } ?? 0) + 1
                switch t {
                case .tank, .roof:
                    let w = parseSpans(v.text("spansX")).reduce(0, +), l = parseSpans(v.text("spansY")).reduce(0, +)
                    let n = max(0, (v.number("panelsBefore") ?? 0) - (v.number("panelsCut") ?? 0))
                    return Source(id: s.module.id.uuidString, code: s.number, name: s.module.title, skin: t == .tank ? .tank : .roof, isPV: true,
                                  width: w > 0 ? w : nil, length: l > 0 ? l : nil, step: step, steps: steps.count, extra: n > 0 ? "\(Int(n)) แผง" : "")
                case .inverter:
                    let st = InverterStation(v)
                    return Source(id: s.module.id.uuidString, code: s.number, name: s.module.title, skin: .building, isPV: false,
                                  width: st.width, length: st.length, step: step, steps: steps.count, extra: "")
                default:
                    return Source(id: s.module.id.uuidString, code: s.number, name: s.module.title, skin: .building, isPV: false,
                                  width: v.number(buildingWidthKey), length: v.number(buildingLengthKey), step: step, steps: steps.count, extra: "")
                }
            }
        }
    }

    // MARK: stored answers

    public static func models(_ v: Values) -> [SiteModel] {
        guard let d = v.text(key).data(using: .utf8), !d.isEmpty else { return [] }
        return (try? JSONDecoder().decode([SiteModel].self, from: d)) ?? []
    }
    public static func setModels(_ a: [SiteModel], in v: inout Values) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        v[key] = a.isEmpty ? nil : (try? enc.encode(a)).flatMap { String(data: $0, encoding: .utf8) }.map(FieldValue.text)
    }
    public static func allLocked(_ v: Values) -> Bool { v.text(lockKey) == "1" }
    public static func setAllLocked(_ on: Bool, in v: inout Values) { v[lockKey] = on ? .text("1") : nil }

    /// Placed models whose section still exists, with it.
    public static func placed(_ job: Job) -> [(model: SiteModel, source: Source)] {
        let src = sources(job)
        return models(job.values).compactMap { m in src.first { $0.id == m.id }.map { (m, $0) } }
    }

    // MARK: drawing

    /// Corners (clockwise from top-left) of a model `w` × `l` metres over a picture in `box` that spans `metersAcross`.
    public static func corners(_ m: SiteModel, width w: Double, length l: Double, in box: Box, metersAcross: Double) -> [Pt] {
        frame(m, w, l, box, metersAcross).corners
    }

    /// Maps a point in metres from the model's top-left corner onto the picture.
    struct Frame {
        let c: Pt, k: Double, w: Double, l: Double, cos: Double, sin: Double
        func p(_ u: Double, _ v: Double) -> Pt {
            let dx = (u - w / 2) * k, dy = (v - l / 2) * k
            return Pt(c.x + dx * cos - dy * sin, c.y + dx * sin + dy * cos)
        }
        var corners: [Pt] { [p(0, 0), p(w, 0), p(w, l), p(0, l)] }
    }
    static func frame(_ m: SiteModel, _ w: Double, _ l: Double, _ box: Box, _ metersAcross: Double) -> Frame {
        let a = m.rotation * .pi / 180
        return Frame(c: Pt(box.x + m.x * box.w, box.y + m.y * box.h), k: box.w / metersAcross, w: w, l: l, cos: cos(a), sin: sin(a))
    }

    /// One model at real scale. `detailed` draws the skin (screen: panel rows, roof ridge, hatched building); otherwise an
    /// outline with a light fill (PDF). `unit` scales line widths and the name tag (1 on screen, in points).
    public static func ops(_ m: SiteModel, _ s: Source, in box: Box, metersAcross: Double, detailed: Bool, selected: Bool = false,
                           locked: Bool = false, unit: Double = 1) -> [DrawOp] {
        guard let w = s.width, let l = s.length, w > 0, l > 0, metersAcross > 0 else { return [] }
        let f = frame(m, w, l, box, metersAcross), pts = f.corners
        let op = selected ? 0.95 : 0.85
        func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> RGBA { RGBA(r / 255, g / 255, b / 255, a * op) }
        let col = s.color
        var o: [DrawOp] = []
        if detailed {
            func band(_ u0: Double, _ v0: Double, _ u1: Double, _ v1: Double, _ fill: RGBA) {
                o.append(.polygon([f.p(u0, v0), f.p(u1, v0), f.p(u1, v1), f.p(u0, v1)], stroke: nil, fill: fill))
            }
            /// Panel joints: thin white lines every 1.154 m across the area between v0 and v1.
            func joints(_ pad: Double, _ v0: Double, _ v1: Double, _ alpha: Double) {
                var u = pad + 1.154
                while u < w - pad { o.append(.line(f.p(u, v0), f.p(u, v1), width: max(0.5, unit * 0.8), color: RGBA(1, 1, 1, alpha * op))); u += 1.154 }
            }
            switch s.skin {
            case .tank:
                o.append(.polygon(pts, stroke: nil, fill: c(214, 219, 226, 0.92)))
                let pad = min(1.0, w / 4, l / 4)
                var v = pad
                while v < l - pad { band(pad, v, w - pad, min(v + 4.40, l - pad), c(40, 78, 160, 0.82)); v += 5.50 }
                joints(pad, pad, l - pad, 0.7)
            case .roof:
                o.append(.polygon(pts, stroke: nil, fill: c(185, 178, 166, 0.92)))
                let pad = min(0.7, w / 4, l / 4)
                band(pad, pad, w - pad, l / 2 - 0.4, c(40, 78, 160, 0.8))
                band(pad, l / 2 + 0.4, w - pad, l - pad, c(40, 78, 160, 0.8))
                joints(pad, pad, l - pad, 0.65)
                o.append(.line(f.p(pad, l / 2), f.p(w - pad, l / 2), width: 2 * unit, color: c(0x6B, 0x62, 0x55, 1)))
            case .building:
                o.append(.polygon(pts, stroke: nil, fill: c(23, 138, 125, 0.85)))
                o += SiteShapes.hatch(pts, color: RGBA(1, 1, 1, 0.25 * op), spacing: 5 * unit, width: 2 * unit)
            }
        } else {
            o.append(.polygon(pts, stroke: nil, fill: RGBA(col.r, col.g, col.b, 0.15)))
        }
        let orange = RGBA(hex: 0xF08C00)
        o.append(.polygon(pts, stroke: selected ? orange : col, fill: nil, width: (selected ? 3 : 2) * unit))
        // name tag above the top-left corner
        let fs = 11.5 * unit, t = (locked ? "🔒 " : "") + s.title
        let tw = ApproxText.width(t, size: fs, bold: true) + 12 * unit, th = 18 * unit
        let top = pts.min { $0.y < $1.y }!, left = pts.filter { abs($0.y - top.y) < 0.5 }.min { $0.x < $1.x } ?? top
        let tag = Box(left.x - 2 * unit, left.y - th - 4 * unit, tw, th)
        o.append(.rect(tag, stroke: nil, fill: selected ? orange : col))
        o.append(.text(t, at: Pt(tag.x + 6 * unit, tag.y + th / 2), size: fs, bold: true, color: .white))
        return o
    }

    /// Every placed model, for the report's A2 picture (always drawn, whatever the screen's layers).
    public static func reportOps(_ job: Job, in box: Box) -> [DrawOp] {
        guard let m = job.values.number(SiteShapes.scaleKey), m > 0 else { return [] }
        let all = allLocked(job.values)
        return placed(job).flatMap { p in
            ops(p.model, p.source, in: box, metersAcross: m, detailed: false, locked: all || p.model.locked, unit: max(0.5, box.w / 860))
        }
    }
}

/// Undo and redo of whole-state snapshots (A2 drawings). A new edit clears what could be redone.
public struct UndoStack<State: Equatable>: Sendable where State: Sendable {
    public private(set) var undos: [State] = []
    public private(set) var redos: [State] = []
    public let limit: Int
    public init(limit: Int = 50) { self.limit = limit }
    public var canUndo: Bool { !undos.isEmpty }
    public var canRedo: Bool { !redos.isEmpty }
    /// Call before an edit with the state it starts from.
    public mutating func record(_ before: State) {
        undos.append(before)
        if undos.count > limit { undos.removeFirst() }
        redos = []
    }
    /// The state to go back to, given the current one; nil when there is none.
    public mutating func undo(_ current: State) -> State? {
        guard let s = undos.popLast() else { return nil }
        redos.append(current)
        return s
    }
    public mutating func redo(_ current: State) -> State? {
        guard let s = redos.popLast() else { return nil }
        undos.append(current)
        return s
    }
}

import Foundation

/// D1 "ถังน้ำใส" sub-step 2 "สิ่งกีดขวาง" (docs/ui/survey-d1-obstacles-iphone): the vents and access hatches of the
/// tank's standard layout, checked on site. They live in `Roof.Key.obstacles` as `Obstacle`s (kind `vent` / `hatch`,
/// `x` / `y` the top-left corner in metres from the tank's top-left as before), so the plan drawings, the PDF and Excel
/// keep reading them; points marked `absent` are left out of the drawings.
public enum TankPoints {
    public static let vent = "vent", hatch = "hatch", ladder = "ladder", pipe = "pipe"
    public static let ok = "ok", absent = "absent"
    public static let standard = "standard", added = "added"
    /// Side of the opening drawn on the plans (m).
    public static let ventSize = 0.6, hatchSize = 0.8
    /// Positions snap to 5 cm.
    public static let grid = 0.05
    /// A dragged point within this of another point's row or column takes it (m).
    public static let magnet = 0.3

    /// A standard point: its centre as a fraction of the tank's width / height.
    public struct Slot: Hashable, Sendable {
        public let kind: String
        public let fx, fy: Double
    }
    /// The standard layout, V1…V10 then H1…H5 (the 40 × 40 m tank of the design: vents 2 m in from the corners and
    /// the side walls' middles, two pairs 4 m apart in the middle and along the bottom wall; hatches 1.2 m in from the
    /// top and bottom walls at the quarter lines, and one on the left wall).
    public static let layout: [Slot] = [
        Slot(kind: vent, fx: 0.05, fy: 0.05), Slot(kind: vent, fx: 0.95, fy: 0.05),
        Slot(kind: vent, fx: 0.05, fy: 0.5), Slot(kind: vent, fx: 0.95, fy: 0.5),
        Slot(kind: vent, fx: 0.05, fy: 0.95), Slot(kind: vent, fx: 0.45, fy: 0.95),
        Slot(kind: vent, fx: 0.55, fy: 0.95), Slot(kind: vent, fx: 0.95, fy: 0.95),
        Slot(kind: vent, fx: 0.45, fy: 0.5), Slot(kind: vent, fx: 0.55, fy: 0.5),
        Slot(kind: hatch, fx: 0.25, fy: 0.03), Slot(kind: hatch, fx: 0.75, fy: 0.03),
        Slot(kind: hatch, fx: 0.25, fy: 0.97), Slot(kind: hatch, fx: 0.75, fy: 0.97),
        Slot(kind: hatch, fx: 0.03, fy: 0.6),
    ]

    public static func size(_ kind: String) -> Double { kind == hatch ? hatchSize : ventSize }
    /// "ช่องระบายอากาศ" / "ช่องลงถัง" / "บันไดขึ้นถัง" / "ท่อ" / "สิ่งกีดขวาง"
    public static func kindName(_ kind: String) -> String {
        switch kind {
        case vent: return "ช่องระบายอากาศ"
        case hatch: return "ช่องลงถัง"
        case ladder: return "บันไดขึ้นถัง"
        case pipe: return "ท่อ"
        default: return "สิ่งกีดขวาง"
        }
    }
    /// Ladders and pipes stand on a wall, outside the roof: they slide along it, overlap nothing and take no room from
    /// the panels. They are kept just inside the wall (top-left corner on it) so the plan's clamping still applies.
    /// The label's letter: V, H, L or P.
    public static func prefix(_ kind: String) -> String {
        switch kind {
        case hatch: return "H"
        case ladder: return "L"
        case pipe: return "P"
        default: return "V"
        }
    }
    public static func onWall(_ kind: String) -> Bool { kind == ladder || kind == pipe }

    public enum Wall: String, Sendable { case top, bottom, left, right }
    /// The wall nearest a rectangle in a tank of this size.
    public static func wall(_ r: Rect, w W: Double, h H: Double) -> Wall {
        let d: [(Wall, Double)] = [(.top, r.y), (.bottom, H - r.y - r.h), (.left, r.x), (.right, W - r.x - r.w)]
        return d.min { $0.1 < $1.1 }!.0
    }
    public static func snap(_ d: Double) -> Double { ((d / grid).rounded() * grid * 100).rounded() / 100 }
    static func text(_ d: Double) -> String { fmt(snap(d)) }

    /// The tank's width and height (m), nil without spans.
    public static func tankSize(_ v: Values) -> (w: Double, h: Double)? {
        let s = Tank.spans(v)
        guard !s.x.isEmpty, !s.y.isEmpty else { return nil }
        return (s.x.reduce(0, +), s.y.reduce(0, +))
    }

    // MARK: points

    /// A point's rectangle in metres; nil without a usable position. Points without a size (older entries) are
    /// drawn as a vent.
    public struct Rect: Hashable, Sendable {
        public var x, y, w, h: Double
        public var cx: Double { x + w / 2 }
        public var cy: Double { y + h / 2 }
        public func overlaps(_ o: Rect) -> Bool { x < o.x + o.w - 1e-6 && o.x < x + w - 1e-6 && y < o.y + o.h - 1e-6 && o.y < y + h - 1e-6 }
    }
    public static func rect(_ o: Obstacle) -> Rect? {
        guard let x = NumberInput.value(o.x), let y = NumberInput.value(o.y) else { return nil }
        let s = size(o.kind), w = NumberInput.value(o.w).flatMap { $0 > 0 ? $0 : nil } ?? s, h = NumberInput.value(o.h).flatMap { $0 > 0 ? $0 : nil } ?? s
        return Rect(x: x, y: y, w: w, h: h)
    }

    public static func points(_ v: Values) -> [Obstacle] { v.obstacles(Roof.Key.obstacles) }
    static func write(_ v: inout Values, _ list: [Obstacle]) { v[Roof.Key.obstacles] = list.isEmpty ? nil : .obstacles(list) }
    static func edit(_ v: inout Values, _ id: UUID, _ f: (inout Obstacle) -> Void) {
        var list = points(v)
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        f(&list[i])
        write(&v, list)
    }

    /// The standard points for a tank of this size, unchecked, at their standard positions.
    public static func standardPoints(width W: Double, height H: Double) -> [Obstacle] {
        var n = [vent: 0, hatch: 0]
        return layout.map { s in
            n[s.kind, default: 0] += 1
            let d = size(s.kind), x = text(s.fx * W - d / 2), y = text(s.fy * H - d / 2)
            return Obstacle(label: (s.kind == vent ? "V" : "H") + "\(n[s.kind]!)", x: x, y: y, w: fmt(d), h: fmt(d), kind: s.kind,
                            origin: standard, stdX: x, stdY: y)
        }
    }
    /// Writes the standard points when the tank has a size and no obstacle yet (the sub-step's first open).
    @discardableResult public static func seed(_ v: inout Values) -> Bool {
        guard points(v).isEmpty, let t = tankSize(v) else { return false }
        write(&v, standardPoints(width: t.w, height: t.h))
        v[Tank.Key.design] = nil
        return true
    }

    public static func isStandard(_ o: Obstacle) -> Bool { o.origin == standard }
    /// "ย้ายแล้ว": a standard point away from its standard position.
    public static func moved(_ o: Obstacle) -> Bool {
        guard isStandard(o), let x = NumberInput.value(o.x), let y = NumberInput.value(o.y),
              let sx = NumberInput.value(o.stdX), let sy = NumberInput.value(o.stdY) else { return false }
        return abs(x - sx) > 0.001 || abs(y - sy) > 0.001
    }

    // MARK: status and completion

    /// "ตรวจแล้ว n/N": every point with a status, of all points.
    public static func checked(_ v: Values) -> (n: Int, total: Int) {
        let list = points(v)
        return (list.filter { !$0.status.isEmpty }.count, list.count)
    }
    /// The sub-step is done when the tank has standard points and every one of them has a status.
    public static func done(_ v: Values) -> Bool {
        let std = points(v).filter(isStandard)
        return !std.isEmpty && std.allSatisfy { !$0.status.isEmpty }
    }
    /// The points still to check, in list order (the chips and ‹ ›).
    public static func pending(_ v: Values) -> [Obstacle] { points(v).filter { $0.status.isEmpty } }

    public static func setStatus(_ v: inout Values, _ id: UUID, _ status: String) { edit(&v, id) { $0.status = status; $0.bulk = false } }
    /// `ยืนยันที่เหลือ n จุดว่าตรงแบบ`: every point not checked yet is marked `ok` together, kept apart as `bulk` so the
    /// report shows which ones weren't checked one by one. Returns how many.
    @discardableResult public static func confirmRest(_ v: inout Values) -> Int {
        var list = points(v), n = 0
        for i in list.indices where list[i].status.isEmpty { list[i].status = ok; list[i].bulk = true; n += 1 }
        if n > 0 { write(&v, list) }
        return n
    }

    // MARK: moving

    /// Moves a point's top-left corner to (x, y), snapped to 5 cm and kept inside the tank.
    public static func move(_ v: inout Values, _ id: UUID, x: Double?, y: Double?) {
        guard let t = tankSize(v) else { return }
        edit(&v, id) { o in
            guard let r = rect(o) else { return }
            o.bulk = false
            if let x { o.x = text(min(max(0, x), max(0, t.w - r.w))) }
            if let y { o.y = text(min(max(0, y), max(0, t.h - r.h))) }
            if o.w.isEmpty { o.w = fmt(r.w) }
            if o.h.isEmpty { o.h = fmt(r.h) }
        }
    }

    /// Where a dragged point lands: (x, y) is its wanted top-left corner. It snaps to 5 cm, stays inside the tank and
    /// takes another point's column / row (centre line) within `magnet`; `guideX` / `guideY` are those centre lines.
    public struct Drop: Hashable, Sendable {
        public var x, y: Double
        public var guideX, guideY: Double?
    }
    public static func drop(_ v: Values, _ id: UUID, x: Double, y: Double) -> Drop? {
        let list = points(v)
        guard let t = tankSize(v), let me = list.first(where: { $0.id == id }), let r = rect(me) else { return nil }
        var nx = min(max(0, x), max(0, t.w - r.w)), ny = min(max(0, y), max(0, t.h - r.h))
        var gx: Double?, gy: Double?
        // a ladder or a pipe slides along its wall
        let side = onWall(me.kind) ? wall(r, w: t.w, h: t.h) : nil
        switch side {
        case .left: nx = 0
        case .right: nx = max(0, t.w - r.w)
        case .top: ny = 0
        case .bottom: ny = max(0, t.h - r.h)
        case nil: break
        }
        let others = list.filter { $0.id != id && $0.status != absent }.compactMap(rect)
        if side != .left && side != .right,
           let o = others.min(by: { abs($0.cx - (nx + r.w / 2)) < abs($1.cx - (nx + r.w / 2)) }), abs(o.cx - (nx + r.w / 2)) <= magnet {
            nx = o.cx - r.w / 2; gx = o.cx
        }
        if side != .top && side != .bottom,
           let o = others.min(by: { abs($0.cy - (ny + r.h / 2)) < abs($1.cy - (ny + r.h / 2)) }), abs(o.cy - (ny + r.h / 2)) <= magnet {
            ny = o.cy - r.h / 2; gy = o.cy
        }
        nx = snap(nx); ny = snap(ny)
        return Drop(x: nx, y: ny, guideX: gx.map { _ in nx + r.w / 2 }, guideY: gy.map { _ in ny + r.h / 2 })
    }

    // MARK: live check

    /// The info line under the distances: alignment with other points, overlaps, outside the tank.
    public struct Check: Hashable, Sendable {
        public var aligned: [String] = []
        public var overlaps: [String] = []
        public var outside = false
        public var warning: Bool { outside || !overlaps.isEmpty }
        /// "แนวเดียวกับ V10 · ไม่ทับจุดอื่น" / "ทับ H3" / "อยู่นอกถัง"
        public var text: String {
            var parts: [String] = []
            if outside { parts.append("อยู่นอกถัง") }
            if !aligned.isEmpty { parts.append("แนวเดียวกับ " + aligned.prefix(2).joined(separator: ", ")) }
            parts.append(overlaps.isEmpty ? "ไม่ทับจุดอื่น" : "ทับ " + overlaps.joined(separator: ", "))
            return parts.joined(separator: " · ")
        }
    }
    public static func check(_ v: Values, _ id: UUID) -> Check? {
        let list = points(v)
        guard let me = list.first(where: { $0.id == id }), let r = rect(me) else { return nil }
        var c = Check()
        if let t = tankSize(v) { c.outside = r.x < -1e-6 || r.y < -1e-6 || r.x + r.w > t.w + 1e-6 || r.y + r.h > t.h + 1e-6 }
        for o in list where o.id != id && o.status != absent {
            guard let q = rect(o) else { continue }
            if abs(q.cx - r.cx) < 0.01 || abs(q.cy - r.cy) < 0.01 { c.aligned.append(o.label) }
            if q.overlaps(r), !onWall(me.kind), !onWall(o.kind) { c.overlaps.append(o.label) }
        }
        // nearest first
        c.aligned.sort { a, b in
            let p = list.first { $0.label == a }.flatMap(rect), q = list.first { $0.label == b }.flatMap(rect)
            return hypot((p?.cx ?? 0) - r.cx, (p?.cy ?? 0) - r.cy) < hypot((q?.cx ?? 0) - r.cx, (q?.cy ?? 0) - r.cy)
        }
        return c
    }

    // MARK: adding and deleting

    /// "V11", "H6", "L4", "P7": one more than the highest number of that kind.
    public static func nextLabel(_ list: [Obstacle], kind: String) -> String {
        let p = prefix(kind)
        let n = list.compactMap { $0.label.hasPrefix(p) ? Int($0.label.dropFirst()) : nil }.max() ?? 0
        return p + "\(n + 1)"
    }
    /// Adds a point found on site at the plan's centre, moved down 1 m at a time while another point or its label is
    /// close (within 11 % of the width and 6 % of the height, about a label on the plan); it is there, so its status is
    /// `ok`. Returns its id.
    @discardableResult public static func add(_ v: inout Values, kind: String) -> UUID? {
        guard let t = tankSize(v) else { return nil }
        var list = points(v)
        let d = size(kind)
        var r = Rect(x: snap(t.w / 2 - d / 2), y: snap(t.h / 2 - d / 2), w: d, h: d)
        let taken = list.compactMap(rect)
        func crowded(_ r: Rect) -> Bool { taken.contains { abs($0.cx - r.cx) < t.w * 0.11 && abs($0.cy - r.cy) < t.h * 0.06 } }
        var k = 0
        while crowded(r) && k < 40 && r.y + 1 + d <= t.h { r.y += 1; k += 1 }
        if crowded(r) { r.y = snap(t.h / 2 - d / 2) }
        let o = Obstacle(label: nextLabel(list, kind: kind), x: text(r.x), y: text(r.y), w: fmt(d), h: fmt(d), kind: kind, status: ok, origin: added)
        list.append(o)
        write(&v, list)
        return o.id
    }
    /// "ทำซ้ำเป็นแถว": `count` copies of the point along its row, `spacing` apart to the right; copies that would leave
    /// the tank are skipped. Returns the new ids.
    @discardableResult public static func repeatRow(_ v: inout Values, _ id: UUID, count: Int, spacing: Double) -> [UUID] {
        var list = points(v)
        guard let t = tankSize(v), count > 0, spacing > 0, let me = list.first(where: { $0.id == id }), let r = rect(me) else { return [] }
        var ids: [UUID] = []
        for i in 1...count {
            let x = snap(r.x + Double(i) * spacing)
            guard x + r.w <= t.w + 1e-6 else { break }
            let o = Obstacle(label: nextLabel(list, kind: me.kind), x: text(x), y: text(r.y), w: fmt(r.w), h: fmt(r.h), kind: me.kind, status: ok, origin: added)
            list.append(o); ids.append(o.id)
        }
        write(&v, list)
        return ids
    }
    /// The standard spacing offered for a row: the tank's first column span, else 4 m.
    public static func rowSpacing(_ v: Values) -> Double { Tank.spans(v).x.first ?? 4 }
    /// Only points added on site can be deleted; standard ones are marked `absent` instead.
    public static func canDelete(_ o: Obstacle) -> Bool { !isStandard(o) }
    @discardableResult public static func delete(_ v: inout Values, _ id: UUID) -> Bool {
        var list = points(v)
        guard let i = list.firstIndex(where: { $0.id == id }), canDelete(list[i]) else { return false }
        list.remove(at: i)
        write(&v, list)
        return true
    }
}

extension Obstacle {
    /// Marked `ไม่มีจริง` on site: kept in the data, left out of the drawings.
    public var isAbsent: Bool { status == TankPoints.absent }
}

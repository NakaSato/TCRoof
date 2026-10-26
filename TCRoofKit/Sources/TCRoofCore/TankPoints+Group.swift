import Foundation

/// D1 sub-step 2 on iPad (docs/ui/survey-d1-obstacles-ipad A4–A5): moving a row or a column of points together, even
/// spacing along it, and repeating a point down as well as to the right.
extension TankPoints {
    /// `ย้ายพร้อมกัน`: the selected point alone, its row or its column.
    public enum GroupMode: String, CaseIterable, Sendable { case single, row, column }

    /// Two centres closer than this share a row / column (m), as the plan's alignment line reads them.
    public static let lineTolerance = 0.01
    /// A distance stepper's step (m): two of the 2.5 cm grid's steps.
    public static let nudge = 0.05

    /// The point and, for a row / column, every live point of its kind whose centre is on the same line, in order
    /// along it (left to right, top to bottom).
    public static func group(_ v: Values, of id: UUID, mode: GroupMode) -> [Obstacle] {
        let list = points(v)
        guard let me = list.first(where: { $0.id == id }), let r = rect(me) else { return [] }
        guard mode != .single, !onWall(me.kind) else { return [me] }
        let members = list.filter { o in
            guard o.id == id || (o.kind == me.kind && !o.isAbsent), let q = rect(o) else { return false }
            return mode == .row ? abs(q.cy - r.cy) < lineTolerance : abs(q.cx - r.cx) < lineTolerance
        }
        return members.sorted { a, b in
            let p = rect(a)!, q = rect(b)!
            return mode == .row ? p.cx < q.cx : p.cy < q.cy
        }
    }

    /// Whether the rectangle sits inside the tank (the circle of a round one).
    static func inside(_ r: Rect, _ v: Values) -> Bool {
        if let c = circle(v) { return c.contains(r) }
        guard let t = tankSize(v) else { return false }
        return r.x >= -1e-6 && r.y >= -1e-6 && r.x + r.w <= t.w + 1e-6 && r.y + r.h <= t.h + 1e-6
    }

    /// Moves every point of the group by (dx, dy), keeping their relative positions. The step is cut down so none
    /// leaves the tank; returns the step taken and whether it was cut.
    @discardableResult
    public static func move(_ v: inout Values, group ids: [UUID], dx: Double, dy: Double) -> (dx: Double, dy: Double, clamped: Bool) {
        let list = points(v), rects = ids.compactMap { id in list.first { $0.id == id }.flatMap(rect) }
        guard !rects.isEmpty, tankSize(v) != nil else { return (0, 0, dx != 0 || dy != 0) }
        var sx = dx, sy = dy
        if circle(v) == nil, let t = tankSize(v) {
            // the farthest each way the whole group can go
            let lo = rects.map { -$0.x }.max()!, hi = rects.map { t.w - $0.x - $0.w }.min()!
            let top = rects.map { -$0.y }.max()!, bottom = rects.map { t.h - $0.y - $0.h }.min()!
            sx = min(max(dx, min(lo, 0)), max(hi, 0)); sy = min(max(dy, min(top, 0)), max(bottom, 0))
        } else {
            // a round tank: back off by grid steps until every member is inside the circle
            func fits(_ a: Double, _ b: Double) -> Bool { rects.allSatisfy { inside(Rect(x: $0.x + a, y: $0.y + b, w: $0.w, h: $0.h), v) } }
            var k = 0
            while !fits(sx, sy) && k < 4000 && (abs(sx) > 1e-9 || abs(sy) > 1e-9) {
                sx = abs(sx) <= grid ? 0 : sx - (sx > 0 ? grid : -grid)
                sy = abs(sy) <= grid ? 0 : sy - (sy > 0 ? grid : -grid)
                k += 1
            }
        }
        sx = snap(sx); sy = snap(sy)
        var out = list
        for i in out.indices where ids.contains(out[i].id) {
            guard let r = rect(out[i]) else { continue }
            out[i].x = text(r.x + sx); out[i].y = text(r.y + sy); out[i].bulk = false
            if out[i].w.isEmpty { out[i].w = fmt(r.w) }
            if out[i].h.isEmpty { out[i].h = fmt(r.h) }
        }
        write(&v, out)
        return (sx, sy, abs(sx - dx) > 1e-6 || abs(sy - dy) > 1e-6)
    }

    /// The group's spacing between neighbouring centres when it is even, else the most common one (rounded to the
    /// grid); nil for fewer than two points.
    public static func spacing(_ v: Values, group: [Obstacle], mode: GroupMode) -> Double? {
        let c = group.compactMap(rect).map { mode == .row ? $0.cx : $0.cy }.sorted()
        guard c.count > 1 else { return nil }
        let gaps = zip(c.dropFirst(), c).map { snap($0 - $1) }
        var count: [Double: Int] = [:]
        for g in gaps { count[g, default: 0] += 1 }
        return count.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    /// Spaces the group evenly, `spacing` apart along its line, measured from the selected point (which stays put).
    /// A point that would leave the tank is pulled back inside; returns how many were.
    @discardableResult
    public static func respace(_ v: inout Values, group: [Obstacle], from id: UUID, spacing: Double, mode: GroupMode) -> Int {
        guard mode != .single, spacing > 0, let at = group.firstIndex(where: { $0.id == id }), let anchor = rect(group[at]),
              let t = tankSize(v) else { return 0 }
        var list = points(v), clamped = 0
        let c = circle(v)
        for (k, o) in group.enumerated() where o.id != id {
            guard let i = list.firstIndex(where: { $0.id == o.id }), let r = rect(o) else { continue }
            let centre = (mode == .row ? anchor.cx : anchor.cy) + Double(k - at) * spacing
            var x = mode == .row ? centre - r.w / 2 : r.x, y = mode == .column ? centre - r.h / 2 : r.y
            let want = (x, y)
            if let c {
                let p = c.clamp(Rect(x: x, y: y, w: r.w, h: r.h)); x = p.x; y = p.y
            } else {
                x = min(max(0, x), max(0, t.w - r.w)); y = min(max(0, y), max(0, t.h - r.h))
            }
            if abs(want.0 - x) > 1e-6 || abs(want.1 - y) > 1e-6 { clamped += 1 }
            list[i].x = text(x); list[i].y = text(y); list[i].bulk = false
            if list[i].w.isEmpty { list[i].w = fmt(r.w) }
            if list[i].h.isEmpty { list[i].h = fmt(r.h) }
        }
        write(&v, list)
        return clamped
    }

    /// "ทำซ้ำเป็นแถว" to the right or downwards: `count` copies `spacing` apart; the copies that would leave the tank
    /// are not made. Returns the new ids (`count - ids.count` were skipped).
    @discardableResult
    public static func repeatPoint(_ v: inout Values, _ id: UUID, count: Int, spacing: Double, down: Bool) -> [UUID] {
        guard !down else { return repeatDown(&v, id, count: count, spacing: spacing) }
        return repeatRow(&v, id, count: count, spacing: spacing)
    }

    static func repeatDown(_ v: inout Values, _ id: UUID, count: Int, spacing: Double) -> [UUID] {
        var list = points(v)
        guard count > 0, spacing > 0, let me = list.first(where: { $0.id == id }), let r = rect(me) else { return [] }
        var ids: [UUID] = []
        for i in 1...count {
            let y = snap(r.y + Double(i) * spacing), copy = Rect(x: r.x, y: y, w: r.w, h: r.h)
            guard inside(copy, v) else { break }
            let o = Obstacle(label: nextLabel(list, kind: me.kind), x: text(r.x), y: text(y), w: fmt(r.w), h: fmt(r.h), kind: me.kind,
                             status: ok, origin: added)
            list.append(o); ids.append(o.id)
        }
        write(&v, list)
        return ids
    }

    /// `ตรงแบบ` on a point moved away from its standard position puts it back there.
    public static func restore(_ v: inout Values, _ id: UUID) {
        edit(&v, id) { o in
            guard isStandard(o), !o.stdX.isEmpty, !o.stdY.isEmpty else { return }
            o.x = o.stdX; o.y = o.stdY
        }
    }
}

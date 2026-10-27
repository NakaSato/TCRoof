import Foundation

/// The mounting plan's grid (docs/specs/cad-export-dxf, Tank mounting grid): a letter on every post line across the
/// slope (A, B for the first row's front and back posts in the layout frame's order, then C, D, …) and, per row, a
/// number on every post pair along it (1, 2, 3 … from the frame's west end; pairs of a row's tables share a number where
/// they line up). A post's reference is its line's letter and its pair's number (`B-3`).
public struct TankMountGrid: Sendable {
    public struct Line: Sendable { public var w: Double; public var name: String }
    public struct Row: Sendable {
        public var row: Int
        /// The pairs along the row (layout frame u), and its front and back post lines and low edge (frame w).
        public var us: [Double]
        public var front, back, lowEdge: Double
        /// +1 when the front posts are on the larger w (the low side towards the frame's south).
        public var down: Double { front >= back ? 1 : -1 }
    }
    public let letters: [Line]
    public let rows: [Row]
    let frame: TankLayout.Frame

    public init(_ l: TankLayout) {
        let fr = TankLayout.Frame(q: l.turn, W: l.size.w, H: l.size.h)
        frame = fr
        func merged(_ xs: [Double]) -> [Double] {
            xs.sorted().reduce(into: [Double]()) { out, x in if let last = out.last, abs(x - last) < 0.05 { return }; out.append(x) }
        }
        let built = l.builtTables
        var rs: [Row] = []
        for r in Set(built.map(\.row)).sorted() {
            let ts = built.filter { $0.row == r && $0.posts.count >= 2 }
            guard let t0 = ts.first else { continue }
            let front = fr.to(t0.posts[0].x, t0.posts[0].y).1, back = fr.to(t0.posts[1].x, t0.posts[1].y).1
            let us = merged(ts.flatMap { t in stride(from: 0, to: t.posts.count, by: 2).map { fr.to(t.posts[$0].x, t.posts[$0].y).0 } })
            let rects = ts.map { fr.rect(TankPoints.Rect(x: $0.x, y: $0.y, w: $0.w, h: $0.h)) }
            let low = front >= back ? rects.map { $0.y + $0.h }.max() ?? front : rects.map(\.y).min() ?? front
            rs.append(Row(row: r, us: us, front: front, back: back, lowEdge: low))
        }
        rows = rs
        let ws = merged(rs.flatMap { [$0.front, $0.back] })
        letters = ws.enumerated().map { Line(w: $1, name: Self.letter($0)) }
    }

    /// A, B, … Z, AA, AB, …
    static func letter(_ i: Int) -> String {
        let a = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return i < 26 ? String(a[i]) : String(a[i / 26 - 1]) + String(a[i % 26])
    }

    /// The letter of the post line at frame `w`.
    public func letter(atW w: Double) -> String? { letters.min { abs($0.w - w) < abs($1.w - w) }.flatMap { abs($0.w - w) < 0.05 ? $0.name : nil } }

    /// The row whose post lines pass through frame `w`.
    func row(atW w: Double) -> Row? { rows.first { abs($0.front - w) < 0.05 || abs($0.back - w) < 0.05 } }

    /// A post's reference (`B-3`), from its centre in tank metres.
    public func ref(_ p: Pt) -> String? {
        let (u, w) = frame.to(p.x, p.y)
        guard let l = letter(atW: w), let r = row(atW: w), let i = r.us.indices.min(by: { abs(r.us[$0] - u) < abs(r.us[$1] - u) }),
              abs(r.us[i] - u) < 0.05 else { return nil }
        return "\(l)-\(i + 1)"
    }

    /// The number of the pair at frame `u` in row `r`.
    public func number(row r: Int, u: Double) -> Int? {
        guard let row = rows.first(where: { $0.row == r }), let i = row.us.indices.min(by: { abs(row.us[$0] - u) < abs(row.us[$1] - u) }),
              abs(row.us[i] - u) < 0.05 else { return nil }
        return i + 1
    }
}

extension TankDXF {
    /// A grid bubble: a circle of radius `r` and its name in the middle (metres).
    static func bubble(_ dxf: inout SketchDXF, _ c: (Double, Double), r: Double, _ name: String) {
        dxf.circle(CADLayers.grid, c, r: r)
        dxf.text(CADLayers.grid, c, height: r * 0.9, name, align: .center, middle: true)
    }

    /// The mounting plan's grid, `at` mapping tank metres to the drawing: a CENTER line along every letter line across
    /// the tank with a bubble past each end, and per row a line through every pair from behind its back posts to past
    /// its low edge with its number's bubble there; each footing is tagged with its reference.
    static func mountGrid(_ dxf: inout SketchDXF, _ l: TankLayout, _ g: TankMountGrid, at: (Pt) -> (Double, Double)) {
        let fr = TankLayout.Frame(q: l.turn, W: l.size.w, H: l.size.h)
        func plan(_ u: Double, _ w: Double) -> (Double, Double) { let q = fr.from(u, w); return at(Pt(q.0, q.1)) }
        for line in g.letters {
            dxf.line(CADLayers.grid, plan(-0.55, line.w), plan(fr.fw + 0.55, line.w))
            bubble(&dxf, plan(-0.95, line.w), r: 0.35, line.name)
            bubble(&dxf, plan(fr.fw + 0.95, line.w), r: 0.35, line.name)
        }
        for row in g.rows {
            let top = row.back - row.down * 0.4, end = row.lowEdge + row.down * 0.71
            for (i, u) in row.us.enumerated() {
                dxf.line(CADLayers.grid, plan(u, top), plan(u, end))
                bubble(&dxf, plan(u, row.lowEdge + row.down * 0.95), r: 0.22, "\(i + 1)")
            }
        }
        for t in l.builtTables {
            for q in t.posts {
                guard let ref = g.ref(q) else { continue }
                let p = at(q)
                dxf.text(CADLayers.text, (p.0 + 0.2, p.1 + 0.2), height: 0.12, ref)
            }
        }
    }
}

extension TankDXF {
    /// The footing schedule beside the mounting plan, its top-left corner at `o` (metres): a line per letter line with
    /// the footings' references, the footing, what stands on it (the back line's post and its height, or the front
    /// line's V of struts) and the count, and the total.
    static func footingSchedule(_ dxf: inout SketchDXF, _ l: TankLayout, _ g: TankMountGrid, at o: (Double, Double)) {
        let p = l.params
        // footings per letter line: their pair numbers and what stands on them (footings alternate front, back)
        var lines: [String: (numbers: [Int], on: String)] = [:]
        for t in l.builtTables {
            for (i, q) in t.posts.enumerated() {
                guard let ref = g.ref(q), let dash = ref.lastIndex(of: "-"), let n = Int(ref[ref.index(after: dash)...]) else { continue }
                let name = String(ref[..<dash])
                lines[name, default: ([], i % 2 == 0 ? "ขาค้ำ V" : String(format: "เสา %.2f ม.", p.hBack))].numbers.append(n)
            }
        }
        let size = String(format: "%.0f × %.0f มม.", p.footing * 1000, p.footing * 1000)
        let cols: [Double] = [0, 1.6, 5.4, 8.6, 10.8, 12.4], rh = 0.5, th = 0.22
        let head = ["แนว", "ตำแหน่งฐานราก", "ฐานราก", "บนฐาน", "จำนวน"]
        var rows: [[String]] = []
        var total = 0
        for line in g.letters {
            guard let e = lines[line.name] else { continue }
            let ns = Array(Set(e.numbers)).sorted()
            total += e.numbers.count
            rows.append([line.name, ranges(ns) { "\(line.name)-\($0)" }.joined(separator: ", "), size,
                         e.on, "\(e.numbers.count)"])
        }
        rows.append(["", "รวม / Total", "", "", "\(total)"])
        let L = CADLayers.roofTable, w = cols.last!
        dxf.text(CADLayers.text, (o.0, o.1 + 0.35), height: 0.32, "ตารางฐานราก / Footing schedule")
        let all = [head] + rows
        for (r, cells) in all.enumerated() {
            let y = o.1 - Double(r) * rh
            dxf.line(L, (o.0, y), (o.0 + w, y))
            for (c, s) in cells.enumerated() where !s.isEmpty {
                dxf.text(L, (o.0 + cols[c] + 0.1, y - rh / 2), height: th, s, align: .left, middle: true)
            }
        }
        let bottom = o.1 - Double(all.count) * rh
        dxf.line(L, (o.0, bottom), (o.0 + w, bottom))
        for x in cols { dxf.line(L, (o.0 + x, o.1), (o.0 + x, bottom)) }
    }

    /// Consecutive numbers as ranges, each end named by `name`: [1, 2, 3, 5] → "A-1…A-3", "A-5".
    static func ranges(_ ns: [Int], _ name: (Int) -> String) -> [String] {
        var out: [String] = [], i = 0
        while i < ns.count {
            var j = i
            while j + 1 < ns.count, ns[j + 1] == ns[j] + 1 { j += 1 }
            out.append(j == i ? name(ns[i]) : name(ns[i]) + "…" + name(ns[j]))
            i = j + 1
        }
        return out
    }
}

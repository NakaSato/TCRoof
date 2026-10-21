import Foundation

/// The true-south comparison of docs/specs/tank-mounting-layout.md §3a (`หันทิศใต้จริง`, comparison only): the same
/// structure standard with the rows turned to run exactly east–west, so the tables sit at an angle to the walls. The
/// tank, its setback and its openings are turned into that frame; a module is placed when its four corners are inside
/// the setback and it misses every grown hatch and every vent too high to stand under it, and its posts follow §3 step 6
/// (`TankLayout.post`). It is searched like `bestEnergy` (the row gaps, the offsets, the year's energy after both
/// shades) and never stored: the team rule keeps the rows on the walls, and this only shows what turning them would give.
extension TankLayout {
    public struct TrueSouth: Sendable {
        /// One module on the tank plan: its corners (tank metres), its row and whether it is the lower one.
        public struct Module: Hashable, Sendable {
            public var corners: [Pt]
            public var row: Int
            public var lower: Bool
        }
        public var gap: Double, offX: Double, offY: Double
        /// The facing wall's angle from south (°, + west): how far the rows are turned from the walls.
        public var wallOffset: Double
        public var modules: [Module]
        /// Footing centres on the plan.
        public var posts: [Pt]
        public var tables: Int, rows: Int, cutColumns: Int
        public var kWp: Double
        /// kWh per kWp a year unshaded, facing south.
        public var yield: Double
        public var rowLoss = 0.0, objectLoss = 0.0
        public var count: Int { modules.count }
        /// MWh a year after both shades.
        public var mwh: Double { kWp * yield / 1000 * (1 - rowLoss - objectLoss) }
    }

    /// The wall-parallel winner of `bestEnergy` beside the true-south layout.
    public struct SouthComparison: Sendable {
        public var wall: GapTrial
        public var south: TrueSouth
        /// The true-south layout's energy against the wall's (−0.087 is 8.7 % less).
        public var change: Double { wall.mwh > 0 ? south.mwh / wall.mwh - 1 : 0 }
        /// `หันทิศใต้จริง (หมุนแถว 12°): 368 แผง | 321.3 MWh/ปี | น้อยกว่า 8.7% (เทียบเท่านั้น)`
        public var line: String {
            let d = abs(change) * 100
            let word = abs(change) < 0.0005 ? "เท่ากัน" : String(format: "%@กว่า %.1f%%", change < 0 ? "น้อย" : "มาก", d)
            return String(format: "หันทิศใต้จริง (หมุนแถว %.0f°): %d แผง | %.1f MWh/ปี | %@ (เทียบเท่านั้น)",
                          abs(south.wallOffset), south.count, south.mwh, word)
        }
    }

    /// The facing wall's angle from south (°, + west); nil without a measured azimuth.
    public static func wallOffset(_ v: Values) -> Double? {
        facing(v).map { ($0 - 180 + 540).truncatingRemainder(dividingBy: 360) - 180 }
    }

    /// Turning the rows is worth comparing only when the facing wall is at least a degree off south.
    public static func comparesSouth(_ v: Values) -> Bool { (wallOffset(v).map(abs) ?? 0) >= 1 }

    // MARK: the frame

    /// Tank plan ↔ the true-south frame: u runs east, w runs south (the plan's top faces the tank's azimuth).
    struct SouthFrame {
        let ex, ey, sx, sy: Double
        init(azimuth az: Double) { let r = az * .pi / 180; ex = cos(r); ey = -sin(r); sx = sin(r); sy = cos(r) }
        func to(_ x: Double, _ y: Double) -> (u: Double, w: Double) { (x * ex + y * ey, x * sx + y * sy) }
        func from(_ u: Double, _ w: Double) -> Pt { Pt(u * ex + w * sx, u * ey + w * sy) }
    }

    /// A plan rectangle turned into the frame: its corners, the bounds and its two edge directions.
    struct Quad {
        var pts: [(u: Double, w: Double)]
        var lo: (u: Double, w: Double), hi: (u: Double, w: Double)
        init(_ r: TankPoints.Rect, _ fr: SouthFrame) {
            pts = [(r.x, r.y), (r.x + r.w, r.y), (r.x + r.w, r.y + r.h), (r.x, r.y + r.h)].map { fr.to($0.0, $0.1) }
            lo = (pts.map(\.u).min()!, pts.map(\.w).min()!); hi = (pts.map(\.u).max()!, pts.map(\.w).max()!)
        }
        /// Separating axes: the slot's own (the bounds), then the quad's two edges.
        func overlaps(u0: Double, w0: Double, u1: Double, w1: Double) -> Bool {
            guard lo.u < u1 - 1e-6, u0 < hi.u - 1e-6, lo.w < w1 - 1e-6, w0 < hi.w - 1e-6 else { return false }
            let box = [(u0, w0), (u1, w0), (u1, w1), (u0, w1)]
            for i in 0..<2 {
                let a = pts[i], b = pts[i + 1], nu = -(b.w - a.w), nw = b.u - a.u
                let q = pts.map { $0.u * nu + $0.w * nw }, s = box.map { $0.0 * nu + $0.1 * nw }
                if s.max()! <= q.min()! + 1e-6 || q.max()! <= s.min()! + 1e-6 { return false }
            }
            return true
        }
    }

    struct SouthGeometry {
        let fr: SouthFrame, size: (w: Double, h: Double), p: Params
        let lo: (u: Double, w: Double), hi: (u: Double, w: Double)
        let grown: [(quad: Quad, vent: Bool)], real: [Quad]
        let keep: [TankPoints.Rect]

        init(size t: (w: Double, h: Double), azimuth az: Double, openings open: [Opening], params p: Params) {
            let fr = SouthFrame(azimuth: az)
            self.fr = fr; size = t; self.p = p
            let c = [(0.0, 0.0), (t.w, 0), (t.w, t.h), (0, t.h)].map { fr.to($0.0, $0.1) }
            lo = (c.map(\.u).min()!, c.map(\.w).min()!); hi = (c.map(\.u).max()!, c.map(\.w).max()!)
            grown = open.map { o in
                let r = o.rect, g = TankPoints.Rect(x: r.x - p.openClear, y: r.y - p.openClear, w: r.w + 2 * p.openClear, h: r.h + 2 * p.openClear)
                return (Quad(g, fr), o.vent)
            }
            real = open.map { Quad($0.rect, fr) }
            keep = open.map(\.rect).map { r in
                TankPoints.Rect(x: r.x - p.legClear - p.footing / 2, y: r.y - p.legClear - p.footing / 2,
                                w: r.w + 2 * p.legClear + p.footing, h: r.h + 2 * p.legClear + p.footing)
            }
        }

        func insideSetback(_ u: Double, _ w: Double) -> Bool {
            let q = fr.from(u, w), e = p.clearance
            return q.x >= e - 1e-9 && q.x <= size.w - e + 1e-9 && q.y >= e - 1e-9 && q.y <= size.h - e + 1e-9
        }

        /// A footing at (u, each w) inside the tank and clear of every opening.
        func footingFree(_ u: Double, _ ws: [Double]) -> Bool {
            let f = p.footing / 2
            return ws.allSatisfy { w in
                let q = fr.from(u, w)
                return q.x >= f && q.x <= size.w - f && q.y >= f && q.y <= size.h - f
                    && !keep.contains { q.x > $0.x + 1e-9 && q.x < $0.x + $0.w - 1e-9 && q.y > $0.y + 1e-9 && q.y < $0.y + $0.h - 1e-9 }
            }
        }

        func colX(_ c: Int, _ offX: Double) -> Double { lo.u + offX + Double(c) * (p.cellW + p.moduleGap) }

        /// Each row's lower panel edge and free columns (§3 steps 2–4 in the turned frame).
        func rows(offX: Double, offY: Double) -> [(lower: Double, free: [Int])] {
            var out: [(Double, [Int])] = []
            var lower = hi.w - offY
            let n = max(0, Int(((hi.u - lo.u - offX + p.moduleGap) / (p.cellW + p.moduleGap) + 1e-9).rounded(.down)))
            while lower - p.depth >= lo.w - 1e-9 {
                let upper = lower - p.depth, front = lower - p.frontIn
                var free: [Int] = []
                for c in 0..<n {
                    let u0 = colX(c, offX), u1 = u0 + p.cellW
                    guard insideSetback(u0, upper), insideSetback(u1, upper), insideSetback(u0, lower), insideSetback(u1, lower) else { continue }
                    var ok = true
                    for (i, g) in grown.enumerated() where g.quad.overlaps(u0: u0, w0: upper, u1: u1, w1: lower) {
                        if !g.vent { ok = false; break }
                        // a vent stays under the panels when the underside above its southmost point is high enough
                        guard real[i].overlaps(u0: u0, w0: upper, u1: u1, w1: lower) else { continue }
                        let ws = min(real[i].hi.w, lower), h = p.hFront + (front - ws) * p.tanT
                        if h < p.ventH + p.underClear - 1e-9 { ok = false; break }
                    }
                    if ok { free.append(c) }
                }
                out.append((lower, free))
                lower -= p.rowPitch
            }
            return out
        }

        func count(offX: Double, offY: Double) -> Int {
            rows(offX: offX, offY: offY).reduce(0) { $0 + runs($1.free).filter { $0.count >= 2 }.reduce(0) { $0 + 2 * $1.count } }
        }

        /// The layout with posts; the spots for the shade simulation alongside.
        func layout(gap: Double, offX: Double, offY: Double, wallOffset: Double) -> (TrueSouth, [TankShade.Spot]) {
            var modules: [TrueSouth.Module] = [], posts: [Pt] = [], spots: [TankShade.Spot] = []
            var tables = 0, cut = 0, builtRows = 0
            var spans: [Int: [(Double, Double)]] = [:]
            for (r, row) in rows(offX: offX, offY: offY).enumerated() {
                let upper = row.lower - p.depth, yF = row.lower - p.frontIn, ys = [yF, yF - p.postDY]
                let posted = TankLayout.post(row.free, colX: { colX($0, offX) }, ys: ys, p, free: footingFree)
                cut += posted.cut.count
                guard !posted.tables.isEmpty else { continue }
                builtRows += 1; tables += posted.tables.count
                spans[r] = posted.tables.map { (colX($0.0.first!, offX), colX($0.0.last!, offX) + p.cellW) }
                for (run, xs) in posted.tables {
                    posts += xs.flatMap { x in ys.map { fr.from(x, $0) } }
                    let a = colX(run.first!, offX), b = colX(run.last!, offX) + p.cellW
                    let behind = spans[r - 1]?.contains { $0.0 < b - 1e-6 && a < $0.1 - 1e-6 } ?? false
                    for c in run {
                        for k in 0..<2 {
                            let u0 = colX(c, offX), w0 = upper + Double(k) * (p.cellH + p.moduleGap * p.cosT)
                            let corners = [fr.from(u0, w0), fr.from(u0 + p.cellW, w0), fr.from(u0 + p.cellW, w0 + p.cellH), fr.from(u0, w0 + p.cellH)]
                            modules.append(.init(corners: corners, row: r, lower: k == 1))
                            let mid = fr.from(u0 + p.cellW / 2, w0 + p.cellH / 2)
                            spots.append(TankShade.Spot(key: "\(r).\(c).\(k)", x: mid.x, y: mid.y, z: TankShade.height(p, lower: k == 1),
                                                        lower: k == 1, behindRow: behind))
                        }
                    }
                }
            }
            let s = TrueSouth(gap: gap, offX: offX, offY: offY, wallOffset: wallOffset, modules: modules, posts: posts,
                              tables: tables, rows: builtRows, cutColumns: cut, kWp: Double(modules.count) * p.moduleKW, yield: 0)
            return (s, spots)
        }
    }

    // MARK: the search

    /// The true-south layout with the most energy a year; nil without a size or an azimuth. Each row gap from the
    /// standard's (`gapSteps`) gets the coarse offset pass (columns 0.10 m over a module width, rows 0.20 m over a
    /// pitch), the ten best counts are posted, and the gap with the most MWh wins; the winner is searched again on the
    /// 5 cm grid. The year is sampled as in `bestEnergy`.
    public static func trueSouth(_ v: Values, latitude: Double, base: Params? = nil) -> TrueSouth? {
        let base = base ?? defaults(v)
        guard let t = TankPoints.tankSize(v), let az = Tank.azimuth(v).map(Double.init), let off = wallOffset(v) else { return nil }
        let open = openings(v), objects = TankShade.objects(v), exposed = Tank.exposed(v) ?? 0
        let yield = SolarModel.yield(lat: latitude, tilt: base.tilt, azimuthFromSouth: 0)

        func trial(_ gap: Double, step: (x: Double, y: Double)) -> TrueSouth {
            var p = base; p.rowGap = gap
            let g = SouthGeometry(size: t, azimuth: az, openings: open, params: p)
            let nx = Int(((p.cellW + p.moduleGap) / step.x - 1e-9).rounded(.down)), ny = Int((p.rowPitch / step.y - 1e-9).rounded(.down))
            var found: [(n: Int, x: Double, y: Double)] = []
            for j in 0...ny { for i in 0...nx {
                let x = snap(Double(i) * step.x), y = snap(Double(j) * step.y)
                found.append((g.count(offX: x, offY: y), x, y))
            } }
            let top = found.enumerated().sorted { $0.element.n != $1.element.n ? $0.element.n > $1.element.n : $0.offset < $1.offset }.prefix(10)
            var pick: (TrueSouth, [TankShade.Spot])?
            for f in top.map(\.element) {
                let l = g.layout(gap: gap, offX: f.x, offY: f.y, wallOffset: off)
                if pick == nil || l.0.count > pick!.0.count { pick = l }
            }
            var (s, spots) = pick!
            s.yield = yield
            if !spots.isEmpty {
                let sim = TankShade.Sim(spots: spots, facing: 180, params: p, size: t, objects: objects, azimuth: az, exposed: exposed)
                let r = sim.run(latitude: latitude, dayStep: 6, minutes: 30)
                s.rowLoss = r.rowLoss; s.objectLoss = r.objectLoss
            }
            return s
        }
        let coarse = gapSteps(base.standardGap).map { trial($0, step: (0.1, 0.2)) }
        guard var best = coarse.first else { return nil }
        for s in coarse.dropFirst() where s.mwh > best.mwh + 1e-9 { best = s }
        let fine = trial(best.gap, step: (TankPoints.grid, TankPoints.grid))
        return fine.mwh > best.mwh ? fine : best
    }

    /// `bestEnergy`'s winner beside the true-south layout; nil when the walls already face within a degree of south.
    public static func compareSouth(_ v: Values, latitude: Double, wall: EnergySearch) -> SouthComparison? {
        guard comparesSouth(v), let s = trueSouth(v, latitude: latitude) else { return nil }
        return SouthComparison(wall: wall.chosen, south: s)
    }
}

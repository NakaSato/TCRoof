import Foundation

/// D1 "ถังน้ำใส" sub-step 3 "จัดแผง" (docs/ui/survey-d1-layout-iphone): the PV mounting structure on the tank roof,
/// after the team's tank-roof standard (docs/specs/tank-mounting-layout.md §1, §3). Rows follow the tank walls and
/// face the wall nearest to south; each row is 2 portrait modules down the slope on front / back posts 1.00 / 2.00 m
/// high, 2.80 m apart, with 2.70 m to the next row (pitch 5.50 m). Module columns are centred in the 1.00 m setback;
/// hatches (grown by 0.50 m) remove the columns over them, vents stay under the panels when the panel underside is high
/// enough and otherwise remove them. Each run of ≥ 2 free columns is one table; its post pairs keep every footing
/// 0.30 m clear of every opening, and a column is cut where no pair fits. Pure and deterministic; the page's answers
/// are optional and hidden (`Key`), and `panelsBefore` follows the panel count.
public struct TankLayout: Sendable {
    public enum Key {
        public static let orient = "tankPvOrient", offX = "tankPvOffX", offY = "tankPvOffY", off = "tankPvOff",
            /// The arrangement the switched-off keys were made on (`arrangement`): a key names a panel by its place in
            /// the list, so the keys hold only while every panel still sits where it did.
            offBase = "tankPvOffBase"
        /// The row gap the energy search picked (m), when wider than the standard's; absent means the standard.
        public static let gap = "tankPvGap"
        /// The team standard the layout was made with (`TankStandard` JSON); absent on layouts made before it was
        /// editable, which used the built-in one.
        public static let standard = "tankPvStd"
    }

    // MARK: the structure standard (§1)

    public struct Params: Hashable, Sendable {
        /// Module size (m) and power (kW), portrait along the slope.
        public var moduleL = 2.278, moduleW = 1.134, moduleKW = 0.55
        public var moduleGap = 0.02
        /// Top of the front / back post above the roof, front → back post on plan.
        public var hFront = 1.0, hBack = 2.0, postDY = 2.8
        /// Back post of a row → front post of the next.
        public var rowGap = 2.7
        /// Post pair spacing along a table, rail overhang past the end posts, front post → lower panel edge (slope).
        public var postDX = 2.7, endOver = 0.4, frontOver = 0.46
        /// Tank edge → panel, openings grown by `openClear` for the panels, footings kept `legClear` from openings.
        public var clearance = 1.0, openClear = 0.5, legClear = 0.3, footing = 0.3
        /// Vent height above the roof and the clearance kept under the panels.
        public var ventH = 1.0, underClear = 0.1
        /// Post pair placement when the equal spacing hits an opening (§3 step 6).
        public var maxCantilever = 1.0, minPairGap = 0.6
        /// Module columns and rows moved from the west / south setback (m).
        public var offX = 0.0, offY = 0.0
        /// The standard's row gap (`rowGap` may be wider, from the energy search) and the standard's revision.
        public var standardGap = 2.7
        public var standardRevision = 0
        public init() {}

        public var tilt: Double { atan((hBack - hFront) / postDY) * 180 / .pi }
        var cosT: Double { cos(tilt * .pi / 180) }
        var tanT: Double { tan(tilt * .pi / 180) }
        /// A module on plan, and the table's depth on plan (4.31 m for the standard).
        public var cellW: Double { moduleW }
        public var cellH: Double { moduleL * cosT }
        public var depth: Double { (2 * moduleL + moduleGap) * cosT }
        /// Lower panel edge → front post on plan.
        public var frontIn: Double { frontOver * cosT }
        public var rowPitch: Double { postDY + rowGap }
        public func width(_ columns: Int) -> Double { Double(columns) * cellW + Double(max(0, columns - 1)) * moduleGap }
        /// Module columns across a frame width.
        func columns(_ fw: Double) -> Int { max(0, Int(((fw - 2 * clearance + moduleGap) / (cellW + moduleGap) + 1e-9).rounded(.down))) }
    }

    // MARK: result

    public struct Panel: Hashable, Sendable {
        /// "row.table.column.panel" (panel 0 is the upper one, away from the slope's low side).
        public var key: String
        public var x, y, w, h: Double
        public var on: Bool
    }
    public struct Table: Hashable, Sendable {
        public var row, index, columns: Int
        public var x, y, w, h: Double
        public var panels: [Panel]
        /// Post pairs, front and back footing centres in turn (tank metres).
        public var posts: [Pt]
        /// The row's centre line through the table (tank metres), for the plan's guide.
        public var guide: (Pt, Pt) { w >= h ? (Pt(x, y + h / 2), Pt(x + w, y + h / 2)) : (Pt(x + w / 2, y), Pt(x + w / 2, y + h)) }
        public var count: Int { panels.filter(\.on).count }
        public var pairs: Int { posts.count / 2 }
    }
    /// A module column cut so no leg touches an opening (drawn as a red outline).
    public struct Cut: Hashable, Sendable { public var x, y, w, h: Double }

    // MARK: quantities (§3 step 7)

    public struct TableBOM: Hashable, Sendable {
        public var modules, posts, footings, rafters, railClamps, midClamps, endClamps, braces, groundLugs: Int
        /// The team's section 1 and detail 1: an aluminium base at every post on its concrete topping (`footings`), two
        /// M12 expansion bolts per base (its two slots), the front and back braces of every post pair's frame and its
        /// outer strut.
        public var bases = 0, anchors = 0, sideBraces = 0, struts = 0
        public var railLength: Double
        /// One table of `columns` × 2 modules, `length` m long, on `pairs` post pairs.
        public init(columns c: Int, length: Double, pairs: Int) {
            modules = 2 * c
            posts = 2 * pairs; footings = posts; rafters = pairs
            railLength = c > 0 ? 4 * length : 0
            // rails × rafters
            railClamps = 4 * pairs
            // 2 per module joint per module row; 2 per end per module row
            midClamps = 2 * max(0, c - 1) * 2
            endClamps = c > 0 ? 2 * 2 * 2 : 0
            // X in every post bay, front and back lines
            braces = 2 * max(0, pairs - 1)
            groundLugs = c > 0 ? 1 : 0
            bases = posts; anchors = 2 * posts; sideBraces = 2 * pairs; struts = pairs
        }
    }
    public struct BOM: Hashable, Sendable {
        public var posts = 0, footings = 0, rafters = 0, railClamps = 0, midClamps = 0, endClamps = 0, braces = 0, groundLugs = 0
        public var bases = 0, anchors = 0, sideBraces = 0, struts = 0
        public var railLength = 0.0
    }

    // MARK: checks

    public struct Checks: Hashable, Sendable {
        /// Vents under the panels and the least height left above them (panel underside − vent height).
        public var ventsUnder = 0
        public var ventHeadroom: Double?
        public var ventsOK = true
        /// Tank edge to the nearest panel edge.
        public var edge: Double?
        public var edgeOK = true
        /// Posts placed, columns cut for them; no footing within `legClear` of an opening.
        public var posts = 0, cutColumns = 0
        public var legsOK = true
        public var passed: Int { [ventsOK, edgeOK, legsOK].filter { $0 }.count }
        public var allOK: Bool { passed == 3 }
    }

    public let params: Params
    public let size: (w: Double, h: Double)
    /// A round tank's roof (its bounding square is `size`): module columns are clipped to it less the edge setback and
    /// footings stay inside it; nil for a rectangle, whose results are unchanged.
    public let circle: TankPoints.Circle?
    /// Quarter turns from the tank plan to the layout's frame: 0 the bottom wall faces south, 1 the right, 2 the top, 3 the left.
    public let turn: Int
    public let tables: [Table]
    public let cuts: [Cut]
    public let rows: Int
    public let bom: BOM
    public let checks: Checks
    public var count: Int { tables.reduce(0) { $0 + $1.count } }
    public var kWp: Double { Double(count) * params.moduleKW }
    /// Tables with at least one panel on.
    public var builtTables: [Table] { tables.filter { $0.count > 0 } }

    // MARK: frame

    /// The wall nearest to south from the D1 azimuth (the top wall's facing); the bottom wall without one.
    public static func turn(_ v: Values) -> Int {
        guard let az = Tank.azimuth(v) else { return 0 }
        // facings: bottom az + 180, right az + 90, top az, left az + 270
        let walls = [(0, az + 180), (1, az + 90), (2, az), (3, az + 270)]
        return walls.min { HeadingLock.diff(Double($0.1), 180) < HeadingLock.diff(Double($1.1), 180) }!.0
    }
    /// Tank plan → layout frame (south is +y) and back, by quarter turns.
    struct Frame {
        let q: Int, W: Double, H: Double
        var fw: Double { q % 2 == 0 ? W : H }
        var fh: Double { q % 2 == 0 ? H : W }
        func to(_ x: Double, _ y: Double) -> (Double, Double) {
            switch q {
            case 1: return (H - y, x)
            case 2: return (W - x, H - y)
            case 3: return (y, W - x)
            default: return (x, y)
            }
        }
        func from(_ x: Double, _ y: Double) -> (Double, Double) {
            switch q {
            case 1: return (y, H - x)
            case 2: return (W - x, H - y)
            case 3: return (W - y, x)
            default: return (x, y)
            }
        }
        func rect(_ r: TankPoints.Rect, back: Bool = false) -> TankPoints.Rect {
            let a = back ? from(r.x, r.y) : to(r.x, r.y), b = back ? from(r.x + r.w, r.y + r.h) : to(r.x + r.w, r.y + r.h)
            return TankPoints.Rect(x: min(a.0, b.0), y: min(a.1, b.1), w: abs(b.0 - a.0), h: abs(b.1 - a.1))
        }
    }

    struct Opening { var rect: TankPoints.Rect; var vent: Bool }
    /// Vents, hatches and other obstacles from sub-step 2, not marked absent. Ladders and pipes stand on the walls.
    static func openings(_ v: Values) -> [Opening] {
        TankPoints.points(v).filter { !$0.isAbsent && !TankPoints.onWall($0.kind) }.compactMap { o in TankPoints.rect(o).map { Opening(rect: $0, vent: o.kind == TankPoints.vent) } }
    }

    // MARK: layout

    /// The layout for the tank in `v`; `off` are the panels switched off by hand. nil without a size.
    public init?(_ v: Values, params p: Params, off: Set<String> = []) {
        guard let t = TankPoints.tankSize(v) else { return nil }
        self.init(size: t, turn: Self.turn(v), openings: Self.openings(v), params: p, off: off, circle: TankPoints.circle(v))
    }

    struct Row { var upper: Double; var free: [Int]; var ventsUnder: Set<Int>; var headroom: Double? }

    static func x0(_ fr: Frame, _ p: Params) -> Double {
        p.clearance + min(max(0, p.offX), max(0, fr.fw - 2 * p.clearance - p.width(max(1, p.columns(fr.fw)))))
    }

    /// Each row's free module columns (§3 steps 2–4, no posts).
    static func rows(_ fr: Frame, _ open: [Opening], _ p: Params, circle: TankPoints.Circle? = nil) -> [Row] {
        let e = p.clearance, n = p.columns(fr.fw), x0 = x0(fr, p)
        guard n > 0 else { return [] }
        let fo = open.map { Opening(rect: fr.rect($0.rect), vent: $0.vent) }
        var out: [Row] = []
        var lower = fr.fh - e - max(0, p.offY)
        while lower - p.depth >= e - 1e-9 {
            let upper = lower - p.depth, front = lower - p.frontIn
            var row = Row(upper: upper, free: [], ventsUnder: [], headroom: nil)
            for c in 0..<n {
                let strip = TankPoints.Rect(x: x0 + Double(c) * (p.cellW + p.moduleGap), y: upper, w: p.cellW, h: p.depth)
                // a round tank: the column's two modules inside the circle less the setback (a quarter turn of the
                // bounding square keeps the circle where it is)
                if let circle, !circle.contains(strip, margin: p.clearance) { continue }
                var ok = true
                for (i, o) in fo.enumerated() {
                    let grown = TankPoints.Rect(x: o.rect.x - p.openClear, y: o.rect.y - p.openClear, w: o.rect.w + 2 * p.openClear, h: o.rect.h + 2 * p.openClear)
                    guard grown.overlaps(strip) else { continue }
                    if !o.vent { ok = false; break }
                    // a vent under the panels: the panel underside above its southmost point
                    guard o.rect.overlaps(strip) else { continue }
                    let ys = min(o.rect.y + o.rect.h, lower), h = p.hFront + (front - ys) * p.tanT
                    if h < p.ventH + p.underClear - 1e-9 { ok = false; break }
                    row.ventsUnder.insert(i); row.headroom = min(row.headroom ?? h - p.ventH, h - p.ventH)
                }
                if ok { row.free.append(c) }
            }
            out.append(row)
            lower -= p.rowPitch
        }
        return out
    }

    /// Runs of consecutive columns.
    static func runs(_ cols: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        for c in cols { if let l = out.last?.last, l == c - 1 { out[out.count - 1].append(c) } else { out.append([c]) } }
        return out
    }

    init(size t: (w: Double, h: Double), turn q: Int, openings open: [Opening], params p: Params, off: Set<String>,
         circle: TankPoints.Circle? = nil) {
        params = p; size = t; turn = q; self.circle = circle
        let fr = Frame(q: q, W: t.w, H: t.h), x0 = Self.x0(fr, p)
        func colX(_ c: Int) -> Double { x0 + Double(c) * (p.cellW + p.moduleGap) }
        // footing keep-out: each opening grown by the clearance and half a footing
        let keep = open.map { fr.rect($0.rect) }.map { r in
            TankPoints.Rect(x: r.x - p.legClear - p.footing / 2, y: r.y - p.legClear - p.footing / 2,
                            w: r.w + 2 * p.legClear + p.footing, h: r.h + 2 * p.legClear + p.footing)
        }
        func free(_ x: Double, _ ys: [Double]) -> Bool {
            ys.allSatisfy { y in
                x >= p.footing / 2 && x <= fr.fw - p.footing / 2 && y >= p.footing / 2 && y <= fr.fh - p.footing / 2
                    && (circle?.contains(x, y, margin: p.footing / 2) ?? true)
                    && !keep.contains { x > $0.x + 1e-9 && x < $0.x + $0.w - 1e-9 && y > $0.y + 1e-9 && y < $0.y + $0.h - 1e-9 }
            }
        }
        var list: [Table] = [], cutList: [Cut] = []
        var under = Set<Int>(), headroom: Double?
        for (r, row) in Self.rows(fr, open, p, circle: circle).enumerated() {
            under.formUnion(row.ventsUnder)
            if let h = row.headroom { headroom = min(headroom ?? h, h) }
            let upper = row.upper, yF = upper + p.depth - p.frontIn, ys = [yF, yF - p.postDY]
            let posted = Self.post(row.free, colX: colX, ys: ys, p, free: free)
            cutList += posted.cut.map { Cut(x: colX($0), y: upper, w: p.cellW, h: p.depth) }
            for (index, (run, xs)) in posted.tables.enumerated() {
                var panels: [Panel] = []
                for (ci, c) in run.enumerated() {
                    for k in 0..<2 {
                        let key = "\(r).\(index).\(ci).\(k)"
                        let y = upper + Double(k) * (p.cellH + p.moduleGap * p.cosT)
                        let b = fr.rect(TankPoints.Rect(x: colX(c), y: y, w: p.cellW, h: p.cellH), back: true)
                        panels.append(Panel(key: key, x: b.x, y: b.y, w: b.w, h: b.h, on: !off.contains(key)))
                    }
                }
                let a = colX(run.first!), box = fr.rect(TankPoints.Rect(x: a, y: upper, w: colX(run.last!) + p.cellW - a, h: p.depth), back: true)
                let posts = xs.flatMap { x in ys.map { y -> Pt in let q = fr.from(x, y); return Pt(q.0, q.1) } }
                list.append(Table(row: r, index: index, columns: run.count, x: box.x, y: box.y, w: box.w, h: box.h, panels: panels, posts: posts))
            }
        }
        cuts = cutList.map { c in let b = fr.rect(TankPoints.Rect(x: c.x, y: c.y, w: c.w, h: c.h), back: true); return Cut(x: b.x, y: b.y, w: b.w, h: b.h) }
        tables = list
        let built = list.filter { $0.count > 0 }
        rows = Set(built.map(\.row)).count

        var b = BOM()
        for tb in built {
            let q = TableBOM(columns: tb.columns, length: p.width(tb.columns), pairs: tb.pairs)
            b.posts += q.posts; b.footings += q.footings; b.rafters += q.rafters; b.railClamps += q.railClamps
            b.midClamps += q.midClamps; b.endClamps += q.endClamps; b.braces += q.braces; b.groundLugs += q.groundLugs
            b.railLength += q.railLength
            b.bases += q.bases; b.anchors += q.anchors; b.sideBraces += q.sideBraces; b.struts += q.struts
        }
        bom = b

        var ck = Checks()
        let on = built.flatMap { $0.panels.filter(\.on) }
        if !on.isEmpty {
            if let circle { ck.edge = on.map { circle.clearance(TankPoints.Rect(x: $0.x, y: $0.y, w: $0.w, h: $0.h)) }.min() }
            else { ck.edge = on.map { min($0.x, $0.y, t.w - ($0.x + $0.w), t.h - ($0.y + $0.h)) }.min() }
            ck.edgeOK = (ck.edge ?? 0) >= p.clearance - 1e-6
        }
        ck.ventsUnder = under.count
        ck.ventHeadroom = headroom
        ck.ventsOK = (headroom ?? .infinity) >= p.underClear - 1e-6
        ck.posts = b.posts
        ck.cutColumns = cutList.count
        let rects = open.map(\.rect)
        ck.legsOK = !built.isEmpty && built.allSatisfy { tb in
            tb.pairs >= 2 && tb.posts.allSatisfy { pt in
                rects.allSatisfy { r in
                    max(r.x - pt.x, 0, pt.x - (r.x + r.w), r.y - pt.y, pt.y - (r.y + r.h)) >= p.legClear + p.footing / 2 - 1e-6
                }
            }
        }
        checks = ck
    }

    // MARK: posts (§3 step 6)

    static func grid(_ lo: Double, _ hi: Double) -> [Double] {
        guard hi >= lo - 1e-9 else { return [] }
        return (0...Int(((hi - lo) / TankPoints.grid + 1e-9).rounded(.down))).map { lo + Double($0) * TankPoints.grid }
    }

    /// Post pairs for a table from `a` to `b` along the row: the equal spacing, else greedy from the west end;
    /// nil and where it failed when no pair fits. `free` says whether a pair at x with its footings at `ys` is clear.
    static func pairs(_ a: Double, _ b: Double, _ ys: [Double], _ p: Params, free: (Double, [Double]) -> Bool) -> (xs: [Double]?, fail: Double) {
        let len = b - a, k = max(1, Int(((len - 2 * p.endOver) / p.postDX).rounded(.up))) + 1
        let span: Double = len - 2 * p.endOver
        let even: [Double] = (0..<k).map { (i: Int) -> Double in a + p.endOver + span * Double(i) / Double(k - 1) }
        if len > 2 * p.endOver, even.allSatisfy({ free($0, ys) }) { return (even, 0) }
        guard var x = grid(a, a + p.maxCantilever).filter({ free($0, ys) }).min(by: { abs($0 - a - p.endOver) < abs($1 - a - p.endOver) })
        else { return (nil, a + p.cellW / 2) }
        var xs = [x]
        while b - x > p.maxCantilever + 1e-9 {
            let reach = grid(x + p.minPairGap, min(b, x + p.postDX)).filter { free($0, ys) }
            if let last = reach.filter({ b - $0 <= p.maxCantilever + 1e-9 }).min(by: { abs(b - p.endOver - $0) < abs(b - p.endOver - $1) }) {
                xs.append(last); return (xs, 0)
            }
            guard let next = reach.max() else { return (nil, min(b, x + p.postDX)) }
            x = next; xs.append(x)
        }
        return (xs, 0)
    }

    /// One row's tables: each run of ≥ 2 free columns posted, a column cut where no pair fits and the parts posted
    /// again. The tables west to east with their pair positions, and the columns cut.
    static func post(_ freeColumns: [Int], colX: (Int) -> Double, ys: [Double], _ p: Params,
                     free: (Double, [Double]) -> Bool) -> (tables: [([Int], [Double])], cut: [Int]) {
        var queue = runs(freeColumns).filter { $0.count >= 2 }, done: [([Int], [Double])] = [], cut: [Int] = [], guardN = 0
        while !queue.isEmpty && guardN < 500 {
            let run = queue.removeFirst(); guardN += 1
            let res = pairs(colX(run.first!), colX(run.last!) + p.cellW, ys, p, free: free)
            if let xs = res.xs { done.append((run, xs)); continue }
            let c = run.min { abs(colX($0) + p.cellW / 2 - res.fail) < abs(colX($1) + p.cellW / 2 - res.fail) }!
            cut.append(c)
            queue.insert(contentsOf: [run.filter { $0 < c }, run.filter { $0 > c }].filter { $0.count >= 2 }, at: 0)
        }
        return (done.sorted { $0.0.first! < $1.0.first! }, cut)
    }

    // MARK: offsets and the max search

    /// How far the columns can move from the west setback and the rows from the south one.
    public static func offsetRange(_ v: Values, _ p: Params) -> (x: Double, y: Double) {
        guard let t = TankPoints.tankSize(v) else { return (0, 0) }
        let fr = Frame(q: turn(v), W: t.w, H: t.h), uw = fr.fw - 2 * p.clearance, uh = fr.fh - 2 * p.clearance
        // a rectangle's row count is fixed, so only the remainder moves; a circle's rows can take any phase of a pitch
        let sy = uh >= p.depth ? (TankPoints.circle(v) == nil ? (uh - p.depth).truncatingRemainder(dividingBy: p.rowPitch)
                                                              : min(p.rowPitch, uh - p.depth)) : 0
        return (max(0, uw - p.width(p.columns(fr.fw))), max(0, sy))
    }
    public static func snap(_ d: Double) -> Double { TankPoints.snap(d) }

    /// The automatic layout: columns centred, rows from the south setback (§3).
    public static func auto(_ v: Values, base: Params? = nil) -> Params {
        var p = base ?? defaults(v)
        p.offX = snap(offsetRange(v, p).x / 2)
        p.offY = 0
        return p
    }

    /// The modules without posts (the search's first stage).
    static func count(size t: (w: Double, h: Double), turn q: Int, openings: [Opening], params p: Params,
                      circle: TankPoints.Circle? = nil) -> Int {
        rows(Frame(q: q, W: t.w, H: t.h), openings, p, circle: circle).reduce(0) { $0 + runs($1.free).filter { $0.count >= 2 }.reduce(0) { $0 + 2 * $1.count } }
    }

    /// `หาผังแผงมากสุด`: every offset on the 5 cm grid; stage 1 counts modules without posts, stage 2 lays out the ten
    /// best with posts, as a cut column can change the order (§3a step 5). The most modules wins, then the smallest offset.
    /// `stepX` / `stepY` (m, multiples of the 5 cm grid) make the energy search's coarser pass (§3a step 5).
    public static func best(_ v: Values, base: Params? = nil, stepX: Double = TankPoints.grid, stepY: Double = TankPoints.grid) -> Params? {
        let base = base ?? defaults(v)
        guard let t = TankPoints.tankSize(v) else { return nil }
        let q = turn(v), open = openings(v), r = offsetRange(v, base), circle = TankPoints.circle(v)
        let nx = Int((r.x / stepX + 1e-9).rounded(.down)), ny = Int((r.y / stepY + 1e-9).rounded(.down))
        var found: [(n: Int, p: Params)] = []
        for j in 0...ny {
            for i in 0...nx {
                var p = base
                p.offX = snap(Double(i) * stepX); p.offY = snap(Double(j) * stepY)
                found.append((count(size: t, turn: q, openings: open, params: p, circle: circle), p))
            }
        }
        let top = found.enumerated().sorted { $0.element.n != $1.element.n ? $0.element.n > $1.element.n : $0.offset < $1.offset }
            .prefix(10).map(\.element.p)
        let laid = top.map { TankLayout(size: t, turn: q, openings: open, params: $0, off: [], circle: circle) }
        var pick: TankLayout?
        for l in laid where pick == nil || l.count > pick!.count { pick = l }
        return pick?.params
    }

    // MARK: stored answers

    /// The team's standard (`TankStandard.Store`): what a new layout is made with.
    public static func defaults() -> Params { TankStandard.Store.shared.current.params }
    /// The standard for this tank: the measured vent height when there is one.
    public static func defaults(_ v: Values) -> Params {
        var p = defaults()
        if let h = Tank.ventHeight(v) { p.ventH = h }
        return p
    }
    /// The stored layout's parameters, nil before the first layout.
    public static func params(_ v: Values) -> Params? {
        guard !v.text(Key.orient).isEmpty else { return nil }
        var p = standard(v).params
        if let h = Tank.ventHeight(v) { p.ventH = h }
        p.offX = v.number(Key.offX) ?? 0; p.offY = v.number(Key.offY) ?? 0
        // never closer than the standard (maintenance access and bracing, §3a step 5)
        if let g = v.number(Key.gap) { p.rowGap = max(p.rowGap, g) }
        return p
    }
    /// The standard the stored layout was made with: its copy, else the built-in one (layouts made before it was editable).
    public static func standard(_ v: Values) -> TankStandard {
        TankStandard.decode(v.text(Key.standard)) ?? .builtIn
    }
    /// The team's standard has changed since the stored layout was made (`จัดแผงใหม่` takes it).
    public static func standardChanged(_ v: Values) -> Bool {
        guard params(v) != nil else { return false }
        return !standard(v).sameValues(TankStandard.Store.shared.current)
    }
    /// The panels switched off, while the layout still has the arrangement they were switched off on; none once the
    /// tank, its openings or a move has cut the tables differently (docs/specs/tank-mounting-layout.md, question 8).
    public static func off(_ v: Values) -> Set<String> {
        let keys = storedOff(v)
        // keys saved before the arrangement was kept have none: they stay as they are
        let base = v.text(Key.offBase)
        guard !keys.isEmpty, !base.isEmpty, let p = params(v), let l = TankLayout(v, params: p, off: keys) else { return keys }
        return arrangement(l, p) == base ? keys : []
    }
    static func storedOff(_ v: Values) -> Set<String> { Set(v.text(Key.off).split(separator: " ").map(String.init)) }

    /// Every panel's key and place relative to the layout's offset (so moving the whole layout keeps it), as a short
    /// stable hash.
    static func arrangement(_ l: TankLayout, _ p: Params) -> String {
        let text = l.tables.flatMap(\.panels).map { q in
            "\(q.key):" + [q.x - p.offX, q.y - p.offY, q.w, q.h].map { String(format: "%.2f", $0) }.joined(separator: ",")
        }.sorted().joined(separator: ";")
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 36)
    }
    /// The stored layout, nil before the first layout or without a size.
    public static func current(_ v: Values) -> TankLayout? {
        if let hit = currentCache.get(v) { return hit.layout }
        guard let p = params(v) else { return nil }
        let layout = TankLayout(v, params: p, off: off(v))
        currentCache.set(v, layout)
        return layout
    }
    /// The last answer of `current`: one render asks for it from several cards with the same `Values`.
    private static let currentCache = LastLayout()
    private final class LastLayout: @unchecked Sendable {
        private let lock = NSLock()
        struct Entry { var values: Values; var layout: TankLayout? }
        private var entry: Entry?
        func get(_ v: Values) -> Entry? {
            lock.lock(); defer { lock.unlock() }
            return entry?.values == v ? entry : nil
        }
        func set(_ v: Values, _ l: TankLayout?) { lock.lock(); entry = Entry(values: v, layout: l); lock.unlock() }
    }
    /// Stores the offsets and the panels switched off, and writes `panelsBefore` = the panel count.
    public static func save(_ v: inout Values, _ p: Params, off: Set<String>) {
        v[Key.orient] = .text("portrait")
        v[Key.offX] = .text(fmt(snap(p.offX))); v[Key.offY] = .text(fmt(snap(p.offY)))
        v[Key.gap] = p.rowGap > p.standardGap + 1e-6 ? .text(fmt(p.rowGap)) : nil
        var std = TankStandard(p)
        if let kept = TankStandard.decode(v.text(Key.standard)), kept.sameValues(std) { std = kept } else {
            let team = TankStandard.Store.shared.current
            if team.sameValues(std) { std = team }
        }
        v[Key.standard] = .text(std.json)
        // keys made on another arrangement (a move that re-cut the tables) would switch off other panels: dropped
        var off = off
        if !off.isEmpty, let l = TankLayout(v, params: p, off: off) {
            let now = arrangement(l, p), before = v.text(Key.offBase)
            if !before.isEmpty, before != now, off == storedOff(v) { off = [] }
            v[Key.offBase] = off.isEmpty ? nil : .text(now)
        } else {
            v[Key.offBase] = nil
        }
        v[Key.off] = off.isEmpty ? nil : .text(off.sorted().joined(separator: " "))
        if let l = TankLayout(v, params: p, off: off) { v["panelsBefore"] = .text(String(l.count)) }
    }
    /// Toggles one panel.
    public static func toggle(_ v: inout Values, _ key: String) {
        guard let p = params(v) else { return }
        var o = off(v)
        if o.contains(key) { o.remove(key) } else { o.insert(key) }
        save(&v, p, off: o)
    }
    /// Switches off every panel of a table (row r, table t).
    public static func removeTable(_ v: inout Values, row r: Int, index t: Int) {
        guard let p = params(v), let l = current(v), let tb = l.tables.first(where: { $0.row == r && $0.index == t }) else { return }
        save(&v, p, off: off(v).union(tb.panels.map(\.key)))
    }
    /// The sub-step is done when a layout is stored and all three checks pass.
    public static func done(_ v: Values) -> Bool { current(v)?.checks.allOK ?? false }
}

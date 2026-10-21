import Foundation

/// The PV layout on a pitched roof (docs/specs/roof-pv-layout.md §3), a port of docs/specs/img/roof_pv.py: modules flush
/// on each face in rows on the purlins, kept out of setbacks, obstacle clearances and the shade of tall obstacles, with
/// L-feet that never land on an obstacle (a module column is cut instead), the yield of each face and which faces are
/// used. `best` searches column offsets, row shifts and packed or centred rows per face for the most modules.
public struct RoofMountLayout: Sendable {
    public struct Options: Sendable, Equatable {
        /// Rails at ¼ and ¾ of the module, clamped to the sheet's ribs (metal sheet), instead of on the purlins.
        public var ribClamp = false
        /// Keep modules out of obstacles' shade 09:00–15:00 all year.
        public var avoidShade = true
        /// A face switched on or off by the user; nil = automatic (≥ the standard's share of the best face).
        public var faceUse: [String: Bool] = [:]
        /// Slots the user removed (a walkway).
        public var removed: Set<SlotRef> = []
        /// A tile roof: rails at ¼ and ¾ of the module on tile hooks screwed into the rafters, instead of L-feet on purlins.
        public var tileHooks = false
        /// A walkway one module wide after every n columns, for cleaning; 0 = none.
        public var walkwayEvery = 0
        /// Modules landscape: the long side along the eave (ด้านยาวตามแป); false = portrait, the long side up the slope.
        public var landscape = false
        /// Rails up the slope across the purlins (รางตัดแป), an L-foot on each purlin they cross; false = rails along the
        /// eave on the purlins (รางตามแป). Only with L-feet on purlins.
        public var railsAcross = false
        public init(ribClamp: Bool = false, avoidShade: Bool = true, faceUse: [String: Bool] = [:], removed: Set<SlotRef> = [],
                    tileHooks: Bool = false, walkwayEvery: Int = 0, landscape: Bool = false, railsAcross: Bool = false) {
            self.ribClamp = ribClamp; self.avoidShade = avoidShade; self.faceUse = faceUse; self.removed = removed
            self.tileHooks = tileHooks; self.walkwayEvery = walkwayEvery; self.landscape = landscape; self.railsAcross = railsAcross
        }
        /// Rows don't depend on the purlins: rib clamps or tile hooks hold the rails at ¼ and ¾ of the module, or the rails
        /// cross the purlins.
        public var freeRows: Bool { ribClamp || tileHooks || railsAcross }
        /// Rails up the slope on purlins (rib clamps and tile hooks keep their rails along the eave).
        public var acrossPurlins: Bool { railsAcross && !ribClamp && !tileHooks }
    }

    /// A module slot: the face, the row up the slope and the column along it.
    public struct SlotRef: Hashable, Sendable, Codable {
        public var face: String, row: Int, column: Int
        public init(face: String, row: Int, column: Int) { self.face = face; self.row = row; self.column = column }
    }

    /// Where one face's rows and columns start.
    public struct Placement: Sendable, Equatable, Codable {
        public var columnOffset: Double, rowShift: Double, centred: Bool
        public init(columnOffset: Double, rowShift: Double, centred: Bool) {
            self.columnOffset = columnOffset; self.rowShift = rowShift; self.centred = centred
        }
    }

    public struct Slot: Sendable {
        /// Start along the eave.
        public var u: Double
        /// Why no module goes here; nil = a module.
        public var blocked: String?
        /// Cut so no L-foot lands on an obstacle.
        public var cut = false
        public var isModule: Bool { blocked == nil }
    }

    /// Neighbouring modules on one pair of rails: along the eave, the columns of one row (its rails are the row's); up the
    /// slope (`acrossPurlins`), the rows of one column, on the rails at `railsAt` (u).
    public struct Run: Sendable {
        public var columns: [Int]
        /// Rail ends along the rail: along the eave (u), or up the slope (v) for a run across the purlins.
        public var start: Double, end: Double
        /// L-foot positions along each rail (lower, upper; or left, right across the purlins).
        public var feet: [[Double]]
        /// The feet were moved off equal spacing to miss an obstacle.
        public var moved: Bool
        /// Across the purlins: the rows the run holds and where its two rails are along the eave.
        public var rows: [Int] = []
        public var railsAt: [Double] = []
        public var railLength: Double { end - start }
        /// Modules on the run.
        public var count: Int { rows.isEmpty ? columns.count : rows.count }
        public var across: Bool { !rows.isEmpty }
        /// The run holds that slot.
        public func holds(row: Int, column: Int, inRow r: Int) -> Bool {
            across ? rows.contains(row) && columns.contains(column) : r == row && columns.contains(column)
        }
    }

    public struct Row: Sendable {
        /// The module's lower end, up the slope from the eave.
        public var v: Double
        /// The two rails, up the slope.
        public var rails: (Double, Double)
        public var slots: [Slot]
        public var runs: [Run] = []
    }

    /// An obstacle as one face sees it.
    public struct FaceObstacle: Sendable {
        public var obstacle: RoofMountInput.Obstacle
        /// Its box in the face's (u, v).
        public var box: (u0: Double, v0: Double, u1: Double, v1: Double)
        /// It stands on this face (its centre is here).
        public var home: Bool
    }

    public struct Face: Sendable {
        public var face: RoofFace
        public var rows: [Row]
        public var placement: Placement
        public var modules: Int
        public var cuts: Int
        /// Layouts the search tried.
        public var tried = 0
        /// kWh per kWp per year.
        public var yield: Double
        public var used: Bool
        public var obstacles: [FaceObstacle]
        /// Shade outlines on this face, in (u, v).
        public var shade: [[Pt]]
        /// Runs up the slope, one per column stretch, when the rails cross the purlins.
        public var columnRuns: [Run] = []
        /// Every run of the face: each row's along the eave, then those across the purlins.
        public var allRuns: [Run] { rows.flatMap(\.runs) + columnRuns }
        /// The run holding a slot.
        public func run(row: Int, column: Int) -> Run? {
            rows.indices.contains(row) ? rows[row].runs.first { $0.columns.contains(column) } ?? columnRuns.first { $0.rows.contains(row) && $0.columns.contains(column) } : nil
        }
    }

    public var faces: [Face]
    public var roof: RoofFaces
    public var purlins: [Double]
    public var standard: RoofMountStandard
    public var options: Options

    // MARK: - Reasons

    public static let outside = "นอกพื้นที่ (ระยะร่นขอบ)"
    public static let shaded = "เงาสิ่งกีดขวาง 09:00–15:00"
    public static let cutForFeet = "ตัดแผงเพื่อไม่ให้ขาโครงสร้างชนสิ่งกีดขวาง"
    public static let removedByUser = "เอาออกเอง"
    public static let walkway = "ทางเดินสำหรับล้างแผง"

    /// Sun positions for the shade: 09:00–15:00 every 30 minutes on 21 Dec, 21 Jun and 21 Mar.
    static let shadeTimes: [(day: Int, time: Double)] = [355, 172, 80].flatMap { d in (18...30).map { (d, Double($0) / 2) } }

    // MARK: - Layout

    /// The layout with each face's placement given (or the best one where none is).
    public static func compute(_ input: RoofMountInput, standard: RoofMountStandard = .standard, options: Options = .init(),
                               placements: [String: Placement] = [:]) -> RoofMountLayout {
        let roof = RoofFaces(input, standard: standard)
        let purlins = RoofFaces.purlins(slopeLength: roof.slopeLength, spacing: input.purlinSpacing)
        let contexts = Context.make(roof, input: input, standard: standard, options: options, purlins: purlins)
        contexts.forEach { $0.spacing = input.purlinSpacing }
        // faces are independent: each searches on its own thread
        let results = Results(count: contexts.count)
        DispatchQueue.concurrentPerform(iterations: contexts.count) { i in
            let ctx = contexts[i]
            results.set(i, placements[ctx.face.id].map(ctx.layout) ?? ctx.best())
        }
        let faces = results.all
        var out = RoofMountLayout(faces: faces, roof: roof, purlins: purlins, standard: standard, options: options)
        out.decideFaces(latitude: input.latitude)
        return out
    }

    /// The best layout of every face (§3.6), ignoring removed slots.
    public static func best(_ input: RoofMountInput, standard: RoofMountStandard = .standard, options: Options = .init()) -> RoofMountLayout {
        var o = options
        o.removed = []
        return compute(input, standard: standard, options: o)
    }

    /// Each face's yield, and which faces get modules.
    mutating func decideFaces(latitude: Double) {
        for i in faces.indices {
            let f = faces[i].face
            let fromSouth = (f.azimuth - 180 + 540).truncatingRemainder(dividingBy: 360) - 180
            faces[i].yield = SolarModel.yield(lat: latitude, tilt: f.tilt * 180 / .pi, azimuthFromSouth: fromSouth)
        }
        let top = faces.map(\.yield).max() ?? 0
        for i in faces.indices {
            faces[i].used = options.faceUse[faces[i].face.id] ?? (faces[i].yield >= standard.faceMinShare * top)
        }
    }

    public var placements: [String: Placement] { Dictionary(uniqueKeysWithValues: faces.map { ($0.face.id, $0.placement) }) }

    /// The module's size up the slope and along the eave, as laid (portrait or landscape).
    public var moduleUp: Double { Self.up(standard, options) }
    public var moduleAlong: Double { Self.along(standard, options) }
    static func up(_ s: RoofMountStandard, _ o: Options) -> Double { o.landscape ? s.moduleWidth : s.moduleLength }
    static func along(_ s: RoofMountStandard, _ o: Options) -> Double { o.landscape ? s.moduleLength : s.moduleWidth }
    /// Whether landscape modules can sit on rails along the purlins: two purlins `purlinSpacing` apart must both fall in the
    /// clamping zone of the module's short side. Wider purlins need the rails across them (รางตัดแป).
    public static func purlinsHoldLandscape(_ s: RoofMountStandard, purlinSpacing: Double) -> Bool {
        let z = clampZone(s, side: s.moduleWidth)
        return purlinSpacing >= s.moduleWidth - 2 * z.max - 1e-9 && purlinSpacing <= s.moduleWidth - 2 * z.min + 1e-9
    }

    /// The clamping zone from a module end along a side of length `side`: the standard's on the long side, the same share
    /// of the short one.
    public static func clampZone(_ s: RoofMountStandard, side: Double) -> (min: Double, max: Double) {
        let k = s.moduleLength > 0 ? side / s.moduleLength : 1
        return (s.clampMin * k, s.clampMax * k)
    }

    // MARK: - One face

    /// One result per face, written from the parallel search.
    final class Results: @unchecked Sendable {
        private var items: [Face?]
        private let lock = NSLock()
        init(count: Int) { items = Array(repeating: nil, count: count) }
        func set(_ i: Int, _ f: Face) { lock.lock(); items[i] = f; lock.unlock() }
        var all: [Face] { items.compactMap { $0 } }
    }

    /// One face's obstacles, shade and slot checks, kept across the layouts the search tries.
    final class Context: @unchecked Sendable {
        let face: RoofFace
        let standard: RoofMountStandard
        let options: Options
        let purlins: [Double]
        let obstacles: [FaceObstacle]
        let shade: [[Pt]]
        private let shadeBounds: [(x0: Double, y0: Double, x1: Double, y1: Double)]
        private var cache: [Int: String?] = [:]
        /// The module up the slope and along the eave, as laid.
        var up: Double { RoofMountLayout.up(standard, options) }
        var along: Double { RoofMountLayout.along(standard, options) }
        private var forbiddenCache: [Double: [(Double, Double)]] = [:]

        init(face: RoofFace, standard: RoofMountStandard, options: Options, purlins: [Double], obstacles: [FaceObstacle], shade: [[Pt]]) {
            self.face = face; self.standard = standard; self.options = options; self.purlins = purlins
            self.obstacles = obstacles; self.shade = shade
            shadeBounds = shade.map(Polygon.bounds)
        }

        static func make(_ roof: RoofFaces, input: RoofMountInput, standard: RoofMountStandard, options: Options,
                         purlins: [Double]) -> [Context] {
            // each obstacle stands on the face holding its centre; its base corners in 3D on that face
            struct Placed { var o: RoofMountInput.Obstacle; var home: String; var corners: [Pt]; var base: [V3] }
            let placed: [Placed] = input.obstacles.map { o in
                let corners = [Pt(o.x, o.y), Pt(o.x + o.w, o.y), Pt(o.x + o.w, o.y + o.h), Pt(o.x, o.y + o.h)]
                let home = roof.faces.first { $0.contains([$0.uv(o.x + o.w / 2, o.y + o.h / 2)], whole: true) } ?? roof.faces[0]
                let base = corners.map { c in let p = home.uv(c.x, c.y); return home.point3(p.x, p.y) }
                return Placed(o: o, home: home.id, corners: corners, base: base)
            }
            let suns: [V3] = shadeTimes.compactMap { t in
                guard let s = SolarModel.sun(lat: input.latitude, day: t.day, time: t.time) else { return nil }
                let alt = s.altitude * .pi / 180, az = (180 + s.azimuth - input.bearing) * .pi / 180
                return V3(x: sin(az) * cos(alt), y: -cos(az) * cos(alt), z: sin(alt))
            }
            return roof.faces.map { f in
                var obstacles: [FaceObstacle] = [], shade: [[Pt]] = []
                let n = f.normal
                for p in placed {
                    let uv = p.corners.map { f.uv($0.x, $0.y) }
                    let box = (uv.map(\.x).min()!, uv.map(\.y).min()!, uv.map(\.x).max()!, uv.map(\.y).max()!)
                    if p.home == f.id { obstacles.append(FaceObstacle(obstacle: p.o, box: box, home: true)) }
                    let height = p.o.heightOrDefault
                    guard height > 0 else { continue }
                    for sv in suns {
                        let ns = n.dot(sv)
                        guard ns > 1e-6 else { continue }
                        var pts: [Pt] = []
                        for b in p.base {
                            let top = b + V3(x: 0, y: 0, z: height)
                            let t = n.dot(top - f.origin) / ns
                            guard t >= 0 else { continue }
                            pts.append(f.uv(top - t * sv))
                            pts.append(p.home == f.id ? f.uv(b) : f.uv(b - (n.dot(b - f.origin) / ns) * sv))
                        }
                        guard pts.count >= 3 else { continue }
                        let h = Polygon.hull(pts)
                        if h.count >= 3 { shade.append(h) }
                    }
                }
                return Context(face: f, standard: standard, options: options, purlins: purlins, obstacles: obstacles, shade: shade)
            }
        }

        /// Why a module can't start at (u, v); nil when it can (§3.3).
        func blocked(_ u: Double, _ v: Double) -> String? {
            let key = Int((u * 1000).rounded()) &* 1_000_003 &+ Int((v * 1000).rounded())
            if let hit = cache[key] { return hit }
            let reason = check(u, v)
            cache[key] = reason
            return reason
        }

        private func check(_ u: Double, _ v: Double) -> String? {
            let l = up, w = along
            let rect = [Pt(u, v), Pt(u + w, v), Pt(u + w, v + l), Pt(u, v + l)]
            if !face.contains(rect) { return RoofMountLayout.outside }
            for ob in obstacles where !ob.obstacle.coverable {
                let m = ob.obstacle.kind.moduleClearance, b = ob.box
                if u < b.u1 + m && b.u0 - m < u + w && v < b.v1 + m && b.v0 - m < v + l {
                    return "\(ob.obstacle.title): เว้นระยะ \(String(format: "%.2f", m)) ม."
                }
            }
            guard options.avoidShade else { return nil }
            for (i, bx) in shadeBounds.enumerated() where bx.x0 < u + w && u < bx.x1 && bx.y0 < v + l && v < bx.y1 {
                if Polygon.overlap(rect, shade[i]) { return RoofMountLayout.shaded }
            }
            return nil
        }

        /// Stretches of a rail at `v` where no foot may go (§3.5).
        func forbidden(_ v: Double) -> [(Double, Double)] {
            if let hit = forbiddenCache[v] { return hit }
            let out: [(Double, Double)] = obstacles.compactMap { ob in
                let m = ob.obstacle.footClearance, b = ob.box
                return b.v0 - m <= v && v <= b.v1 + m ? (b.u0 - m, b.u1 + m) : nil
            }
            forbiddenCache[v] = out
            return out
        }

        /// Rows from the eave (§3.2): each row's start and its two rails. Packing from the earliest valid start gives the
        /// most rows, since every row is the same length; `centred` then centres each row between its purlins where its
        /// neighbours allow.
        func rows(shift: Double, centred: Bool) -> [(v: Double, a: Double, b: Double)] {
            let l = up, g = standard.moduleGap, zone = RoofMountLayout.clampZone(standard, side: l), lo = zone.min, hi = zone.max
            let vmin = face.vMin, vmax = face.vMax(standard)
            var out: [(v: Double, a: Double, b: Double)] = []
            var v = vmin + shift
            while v + l <= vmax + 1e-9 {
                if options.freeRows {
                    out.append((v, v + l / 4, v + 3 * l / 4)); v += l + g; continue
                }
                var found: (v: Double, a: Double, b: Double)?
                var w = v
                while w + l <= vmax + 1e-9 {
                    let a = purlins.first { $0 - w >= lo - 1e-9 && $0 - w <= hi + 1e-9 }
                    let b = purlins.last { w + l - $0 >= lo - 1e-9 && w + l - $0 <= hi + 1e-9 }
                    if let a, let b { found = (w, a, b); break }
                    w = ((w + 0.01) * 10_000).rounded() / 10_000
                }
                guard let found else { break }
                out.append(found)
                v = found.v + l + g
            }
            guard centred else { return out }
            for i in out.indices.reversed() {
                let (_, a, b) = out[i]
                let low = max(a - hi, b + lo - l, i == 0 ? vmin : out[i - 1].v + l + g)
                let high = min(a - lo, b + hi - l, vmax - l, i + 1 < out.count ? out[i + 1].v - l - g : 1e9)
                out[i].v = min(max((a + b) / 2 - l / 2, low), high)
            }
            return out
        }

        /// L-feet along a rail from `xa` to `xb`: equal spacing when it misses every forbidden stretch, else greedy on a
        /// 5 cm grid taking the furthest allowed point. Nil (with where it failed) when neither works.
        func feet(_ xa: Double, _ xb: Double, avoiding bad: [(Double, Double)]) -> (feet: [Double]?, failedAt: Double, moved: Bool) {
            func ok(_ x: Double) -> Bool { bad.allSatisfy { !($0.0 < x && x < $0.1) } }
            if options.tileHooks { return hooks(xa, xb, ok: ok) }
            let dx = standard.footSpacing, c = standard.footCantilever, mn = standard.footMinBay
            let lr = xb - xa
            let m = max(1, Int(((lr - 0.4) / dx).rounded(.up)))
            let equal = lr > 0.4 ? (0...m).map { xa + 0.2 + Double($0) * (lr - 0.4) / Double(m) } : [(xa + xb) / 2]
            if equal.allSatisfy(ok) { return (equal, 0, false) }
            // descending from hi in 5 cm steps
            func grid(_ lo: Double, _ hi: Double) -> [Double] {
                guard hi >= lo else { return [] }
                return (0...Int((hi - lo) / 0.05)).map { ((hi - Double($0) * 0.05) * 1000).rounded() / 1000 }
            }
            guard let first = grid(xa + 0.05, min(xb, xa + c)).first(where: ok) else { return (nil, xa + c / 2, true) }
            var out = [first]
            while out[out.count - 1] < xb - c - 1e-9 {
                let last = out[out.count - 1]
                guard let next = grid(last + mn, min(xb - 0.05, last + dx)).first(where: ok) else { return (nil, last + dx / 2, true) }
                out.append(next)
            }
            return (out, 0, true)
        }

        /// Tile hooks along a rail from `xa` to `xb`: one on every rafter under it (rafters every `rafterSpacing` from the
        /// face's start), none on an obstacle. Nil when a rafter had to be skipped (a gap of two spacings), the rail
        /// overhangs its end hook by more than one spacing, or it has no hook at all.
        func hooks(_ xa: Double, _ xb: Double, ok: (Double) -> Bool) -> (feet: [Double]?, failedAt: Double, moved: Bool) {
            let r = standard.rafterSpacing, u0 = face.polygon.map(\.x).min() ?? 0
            let first = ((xa + 0.05 - u0) / r).rounded(.up), last = ((xb - 0.05 - u0) / r).rounded(.down)
            guard first <= last else { return (nil, (xa + xb) / 2, false) }
            let rafters = stride(from: first, through: last, by: 1).map { u0 + $0 * r }
            let out = rafters.filter(ok)
            guard let lo = out.first, let hi = out.last else { return (nil, (xa + xb) / 2, false) }
            if lo - xa > r + 1e-9 { return (nil, xa + r / 2, true) }
            if xb - hi > r + 1e-9 { return (nil, xb - r / 2, true) }
            for (a, b) in zip(out, out.dropFirst()) where b - a > r + 1e-9 { return (nil, (a + b) / 2, true) }
            return (out, 0, out.count != rafters.count)
        }

        /// The face laid out with a placement (§3.3–3.5).
        func layout(_ p: Placement) -> Face {
            let w = along, pitch = w + standard.moduleGap
            let umin = face.polygon.map(\.x).min() ?? 0, umax = face.polygon.map(\.x).max() ?? 0
            var rows: [Row] = []
            for (r, row) in self.rows(shift: p.rowShift, centred: p.centred).enumerated() {
                var slots: [Slot] = []
                var u = umin + standard.setVerge + p.columnOffset
                while u + w <= umax + 1e-9 {
                    let column = slots.count, n = options.walkwayEvery
                    let walk = n > 0 && column % (n + 1) == n
                    let removed = options.removed.contains(SlotRef(face: face.id, row: r, column: column))
                    slots.append(Slot(u: u, blocked: walk ? RoofMountLayout.walkway : removed ? RoofMountLayout.removedByUser : blocked(u, row.v)))
                    u += pitch
                }
                rows.append(Row(v: row.v, rails: (row.a, row.b), slots: slots))
            }
            var cuts = 0
            var columnRuns: [Run] = []
            if options.acrossPurlins {
                (columnRuns, cuts) = acrossRuns(&rows)
            }
            for r in rows.indices where !options.acrossPurlins {
                for _ in 0..<200 {
                    var runs: [[Int]] = [], current: [Int] = []
                    for (i, s) in rows[r].slots.enumerated() {
                        if s.isModule { current.append(i) } else if !current.isEmpty { runs.append(current); current = [] }
                    }
                    if !current.isEmpty { runs.append(current) }
                    var failure: (run: [Int], at: Double)?
                    rows[r].runs = []
                    for run in runs {
                        let xa = rows[r].slots[run[0]].u - standard.railOverhang
                        let xb = rows[r].slots[run[run.count - 1]].u + w + standard.railOverhang
                        var feet: [[Double]] = [], moved = false
                        for rail in [rows[r].rails.0, rows[r].rails.1] {
                            let f = self.feet(xa, xb, avoiding: forbidden(rail))
                            moved = moved || f.moved
                            guard let placed = f.feet else { failure = (run, f.failedAt); break }
                            feet.append(placed)
                        }
                        if failure != nil { break }
                        rows[r].runs.append(Run(columns: run, start: xa, end: xb, feet: feet, moved: moved))
                    }
                    guard let failure else { break }
                    // cut the column nearest where the feet failed, and try the row again
                    let i = failure.run.min { abs(rows[r].slots[$0].u + w / 2 - failure.at) < abs(rows[r].slots[$1].u + w / 2 - failure.at) }!
                    rows[r].slots[i].blocked = RoofMountLayout.cutForFeet
                    rows[r].slots[i].cut = true
                    cuts += 1
                }
            }
            let n = rows.reduce(0) { $0 + $1.slots.filter(\.isModule).count }
            return Face(face: face, rows: rows, placement: p, modules: n, cuts: cuts, yield: 0, used: true,
                        obstacles: obstacles, shade: shade, columnRuns: columnRuns)
        }

        /// Rails up the slope across the purlins: each column's stretch of touching modules on two rails at ¼ and ¾ of the
        /// module (inside the clamping zone), an L-foot on every purlin under a rail, none on an obstacle. A stretch whose
        /// rails can't be held (a purlin skipped past the foot spacing, too long an overhang, under two feet) has the module
        /// nearest the failure cut, and is tried again.
        func acrossRuns(_ rows: inout [Row]) -> (runs: [Run], cuts: Int) {
            let l = up, w = along, g = standard.moduleGap
            let zone = RoofMountLayout.clampZone(standard, side: w)
            let a = min(max(w / 4, zone.min), zone.max)
            let columns = rows.map(\.slots.count).max() ?? 0
            var out: [Run] = [], cuts = 0
            for c in 0..<columns {
                for _ in 0..<200 {
                    // stretches of touching modules in this column
                    var stretches: [[Int]] = [], current: [Int] = []
                    for r in rows.indices {
                        let here = rows[r].slots.indices.contains(c) && rows[r].slots[c].isModule
                        let touches = current.last.map { rows[r].v - (rows[$0].v + l) <= g + 1e-6 } ?? true
                        if here && touches { current.append(r); continue }
                        if !current.isEmpty { stretches.append(current) }
                        current = here ? [r] : []
                    }
                    if !current.isEmpty { stretches.append(current) }
                    var runs: [Run] = [], failure: (stretch: [Int], at: Double)?
                    for st in stretches {
                        let u = rows[st[0]].slots[c].u
                        let va = rows[st[0]].v - standard.railOverhang, vb = rows[st[st.count - 1]].v + l + standard.railOverhang
                        var feet: [[Double]] = [], moved = false
                        for x in [u + a, u + w - a] {
                            let f = purlinFeet(va, vb, avoiding: forbidden(alongEaveAt: x))
                            moved = moved || f.moved
                            guard let placed = f.feet else { failure = (st, f.failedAt); break }
                            feet.append(placed)
                        }
                        if failure != nil { break }
                        runs.append(Run(columns: [c], start: va, end: vb, feet: feet, moved: moved, rows: st, railsAt: [u + a, u + w - a]))
                    }
                    guard let failure else { out += runs; break }
                    let r = failure.stretch.min { abs(rows[$0].v + l / 2 - failure.at) < abs(rows[$1].v + l / 2 - failure.at) }!
                    rows[r].slots[c].blocked = RoofMountLayout.cutForFeet
                    rows[r].slots[c].cut = true
                    cuts += 1
                }
            }
            return (out, cuts)
        }

        /// Stretches up the slope of a rail at `u` where no foot may go.
        func forbidden(alongEaveAt u: Double) -> [(Double, Double)] {
            obstacles.compactMap { ob in
                let m = ob.obstacle.footClearance, b = ob.box
                return b.u0 - m <= u && u <= b.u1 + m ? (b.v0 - m, b.v1 + m) : nil
            }
        }

        /// L-feet of a rail up the slope from `va` to `vb`: one on every purlin under it that misses the obstacles. Nil
        /// (with where it failed) under two feet, when the rail overhangs a foot by more than the cantilever (at least half
        /// a purlin spacing, which the row shift can't always avoid), or when a gap passes the foot spacing.
        func purlinFeet(_ va: Double, _ vb: Double, avoiding bad: [(Double, Double)]) -> (feet: [Double]?, failedAt: Double, moved: Bool) {
            func ok(_ x: Double) -> Bool { bad.allSatisfy { !($0.0 < x && x < $0.1) } }
            let under = purlins.filter { $0 > va + 0.02 && $0 < vb - 0.02 }
            let feet = under.filter(ok)
            let cantilever = max(standard.footCantilever, purlinSpacing / 2 + 0.05)
            let gap = max(standard.footSpacing, purlinSpacing) + 1e-6
            guard feet.count >= 2, let lo = feet.first, let hi = feet.last else { return (nil, (va + vb) / 2, false) }
            if lo - va > cantilever { return (nil, va + cantilever / 2, true) }
            if vb - hi > cantilever { return (nil, vb - cantilever / 2, true) }
            for (x, y) in zip(feet, feet.dropFirst()) where y - x > gap { return (nil, (x + y) / 2, true) }
            return (feet, 0, feet.count != under.count)
        }

        /// The most modules over every column offset (5 cm steps), row shift (10 cm steps up to one row pitch) and
        /// centred or packed rows; then fewer cut columns, then centred (§3.6).
        func best() -> Face {
            let rowPitch = up + standard.moduleGap + (options.freeRows ? 0 : purlinSpacing)
            var best: Face?, tried = 0
            for j in 0...Int(rowPitch / 0.10) {
                for k in 0...Int((along + standard.moduleGap) / 0.05) {
                    for centred in [true, false] {
                        let f = layout(Placement(columnOffset: Double(k) * 0.05, rowShift: Double(j) * 0.10, centred: centred))
                        tried += 1
                        if let b = best {
                            let better = f.modules != b.modules ? f.modules > b.modules
                                : f.cuts != b.cuts ? f.cuts < b.cuts : (f.placement.centred && !b.placement.centred)
                            if better { best = f }
                        } else {
                            best = f
                        }
                    }
                }
            }
            var out = best!
            out.tried = tried
            return out
        }

        /// The purlin spacing as surveyed.
        var spacing = 1.0
        var purlinSpacing: Double { spacing }
    }
}

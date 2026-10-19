import Foundation

/// What the roof PV layout reads from C1 (docs/specs/roof-pv-layout.md §2), in metres on the plan: x along `spansX`,
/// y along `spansY`, from the plan's top-left.
public struct RoofMountInput: Sendable {
    public enum Shape: String, Sendable { case gable, hip, shed }

    public struct Obstacle: Sendable, Equatable {
        public var kind: RoofObstacleKind
        public var x, y, w, h: Double
        /// Height above the roof; nil takes the kind's default.
        public var height: Double?
        public var label: String?
        /// Modules may cover it (a skylight marked วางทับได้); its L-foot clearance still holds.
        public var coverable = false
        public init(kind: RoofObstacleKind, x: Double, y: Double, w: Double, h: Double, height: Double? = nil, label: String? = nil,
                    coverable: Bool = false) {
            self.kind = kind; self.x = x; self.y = y; self.w = w; self.h = h; self.height = height; self.label = label
            self.coverable = coverable
        }
        public var heightOrDefault: Double { height ?? kind.defaultHeight }
        /// L-feet keep this far from it. A skylight panels may cover is bridged by the rails, so only its lap (0.20 m)
        /// is kept clear: with the full 0.50 m the stretch without feet would pass the foot spacing and cut every column.
        public var footClearance: Double { coverable ? min(kind.footClearance, Self.coveredLap) : kind.footClearance }
        public static let coveredLap = 0.20
        public var title: String { label.flatMap { $0.isEmpty ? nil : $0 } ?? kind.title }
    }

    public var spansX: [Double]
    public var spansY: [Double]
    /// The ridge runs along x (vertical sheets on the plan).
    public var ridgeAlongX: Bool
    public var shape: Shape
    public var eaveHeight: Double
    public var ridgeHeight: Double
    public var purlinSpacing: Double
    public var latitude: Double
    /// Compass bearing of the plan's top edge, degrees.
    public var bearing: Double
    public var obstacles: [Obstacle]
    /// A shed roof's low eave is at the plan's top (ridge along x) or left (ridge along y), instead of bottom or right.
    public var shedLowAtStart: Bool
    /// Concrete tiles (กระเบื้องซีแพค): the rails go on tile hooks screwed into the rafters.
    public var tileRoof = false

    public init(spansX: [Double], spansY: [Double], ridgeAlongX: Bool = true, shape: Shape = .gable, eaveHeight: Double,
                ridgeHeight: Double, purlinSpacing: Double, latitude: Double, bearing: Double = 0, obstacles: [Obstacle] = [],
                shedLowAtStart: Bool = false) {
        self.spansX = spansX; self.spansY = spansY; self.ridgeAlongX = ridgeAlongX; self.shape = shape
        self.eaveHeight = eaveHeight; self.ridgeHeight = ridgeHeight; self.purlinSpacing = purlinSpacing
        self.latitude = latitude; self.bearing = bearing; self.obstacles = obstacles; self.shedLowAtStart = shedLowAtStart
    }

    public var lengthX: Double { spansX.reduce(0, +) }
    public var lengthY: Double { spansY.reduce(0, +) }
}

/// A point or direction in 3D: x, y on the plan, z up.
struct V3: Sendable {
    var x, y, z: Double
    static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (k: Double, a: V3) -> V3 { V3(x: k * a.x, y: k * a.y, z: k * a.z) }
    func dot(_ b: V3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: V3) -> V3 { V3(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
}

/// One roof face in its own plane (§3.1): u along the eave, v up the slope from it. The polygon is convex and
/// counter-clockwise, each edge has a kind, and an affine map takes (u, v) to the plan.
public struct RoofFace: Sendable, Identifiable {
    public enum Edge: String, Sendable { case eave, verge, ridge, hip }

    /// S, N, E or W: the side of the plan the face drains to.
    public let id: String
    public let polygon: [Pt]
    public let edges: [Edge]
    /// Radians.
    public let tilt: Double
    public let slopeLength: Double
    /// Compass azimuth of the downslope direction, degrees.
    public let azimuth: Double
    let origin: V3, eu: V3, ev: V3
    /// Inward half-planes n·p ≥ d: with the setbacks, and without them (the face itself).
    let usable: [(n: Pt, d: Double)]
    let whole: [(n: Pt, d: Double)]

    init(id: String, polygon: [Pt], edges: [Edge], tilt: Double, slopeLength: Double, azimuth: Double,
         map: (Double, Double) -> Pt, standard: RoofMountStandard) {
        self.id = id; self.polygon = polygon; self.edges = edges; self.tilt = tilt; self.slopeLength = slopeLength
        self.azimuth = azimuth
        let o = map(0, 0), u1 = map(1, 0), v1 = map(0, 1)
        origin = V3(x: o.x, y: o.y, z: 0)
        eu = V3(x: u1.x - o.x, y: u1.y - o.y, z: 0)
        ev = V3(x: v1.x - o.x, y: v1.y - o.y, z: sin(tilt))
        var usable: [(n: Pt, d: Double)] = [], whole: [(n: Pt, d: Double)] = []
        for (i, kind) in edges.enumerated() {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let l = hypot(b.x - a.x, b.y - a.y), n = Pt(-(b.y - a.y) / l, (b.x - a.x) / l)
            let d = n.x * a.x + n.y * a.y
            usable.append((n, d + standard.setback(kind)))
            whole.append((n, d))
        }
        self.usable = usable; self.whole = whole
    }

    /// The plan point of (u, v).
    public func plan(_ u: Double, _ v: Double) -> Pt { Pt(origin.x + u * eu.x + v * ev.x, origin.y + u * eu.y + v * ev.y) }

    /// The (u, v) of a plan point.
    public func uv(_ x: Double, _ y: Double) -> Pt {
        let dx = x - origin.x, dy = y - origin.y
        return Pt((dx * eu.x + dy * eu.y) / (eu.x * eu.x + eu.y * eu.y), (dx * ev.x + dy * ev.y) / (ev.x * ev.x + ev.y * ev.y))
    }

    /// The (u, v) of a point in 3D, projected onto the face's axes.
    func uv(_ p: V3) -> Pt {
        let d = p - origin
        return Pt(d.dot(eu) / eu.dot(eu), d.dot(ev) / ev.dot(ev))
    }

    func point3(_ u: Double, _ v: Double) -> V3 { origin + u * eu + v * ev }

    /// The face's upward normal.
    var normal: V3 {
        let n = eu.cross(ev)
        return n.z > 0 ? n : -1 * n
    }

    /// All points inside the usable area (or the whole face).
    func contains(_ points: [Pt], whole: Bool = false) -> Bool {
        let planes = whole ? self.whole : usable
        return points.allSatisfy { p in planes.allSatisfy { $0.n.x * p.x + $0.n.y * p.y >= $0.d - 1e-9 } }
    }

    /// The usable area's corners, for drawing.
    public var usableArea: [Pt] {
        var out: [Pt] = []
        for i in usable.indices {
            let (n1, d1) = usable[(i + usable.count - 1) % usable.count], (n2, d2) = usable[i]
            let det = n1.x * n2.y - n1.y * n2.x
            guard abs(det) > 1e-12 else { continue }
            out.append(Pt((d1 * n2.y - d2 * n1.y) / det, (n1.x * d2 - n2.x * d1) / det))
        }
        return out
    }

    /// Where the line at `v` up the slope crosses the face (u from, to), or nil when it misses.
    public func span(atV v: Double) -> (Double, Double)? {
        var us: [Double] = []
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            guard (a.y - v) * (b.y - v) <= 0, a.y != b.y || a.y == v else { continue }
            if a.y == b.y { us += [a.x, b.x] } else { us.append(a.x + (v - a.y) / (b.y - a.y) * (b.x - a.x)) }
        }
        guard let lo = us.min(), let hi = us.max(), hi > lo else { return nil }
        return (lo, hi)
    }

    /// The face's middle, for its label.
    public var centre: Pt {
        Pt(polygon.map(\.x).reduce(0, +) / Double(polygon.count), polygon.map(\.y).reduce(0, +) / Double(polygon.count))
    }

    /// `ใต้` … for a compass azimuth.
    public static func direction(_ az: Double) -> String {
        let names = ["เหนือ", "ตะวันออกเฉียงเหนือ", "ตะวันออก", "ตะวันออกเฉียงใต้", "ใต้", "ตะวันตกเฉียงใต้", "ตะวันตก", "ตะวันตกเฉียงเหนือ"]
        let a = (az.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return names[Int((a + 22.5) / 45) % 8]
    }

    /// The lowest v a module may start at: the eave setback.
    var vMin: Double { usable.filter { $0.n.y > 0.99 }.map(\.d).max() ?? 0 }
    /// The highest v a module may reach: the ridge setback.
    func vMax(_ standard: RoofMountStandard) -> Double {
        let ridge = usable.filter { $0.n.y < -0.99 }.map { -$0.d }
        return ridge.min() ?? slopeLength - standard.setRidge
    }
}

/// The faces of a roof from its outline, shape, heights and plan bearing (§3.1).
public struct RoofFaces: Sendable {
    public let faces: [RoofFace]
    /// Along and across the ridge (m).
    public let along: Double, across: Double
    public let rise: Double
    /// Radians.
    public let tilt: Double
    public let slopeLength: Double

    public init(_ input: RoofMountInput, standard: RoofMountStandard = .standard) {
        let lx = input.lengthX, ly = input.lengthY, rx = input.ridgeAlongX
        let a = rx ? lx : ly, b = rx ? ly : lx
        let rise = max(input.ridgeHeight - input.eaveHeight, 0.01)
        let h = input.shape == .shed ? b : b / 2
        let th = atan(rise / h), c = cos(th), ls = h / c
        let sw: (Double, Double) -> Pt = rx ? { Pt($0, $1) } : { Pt($1, $0) }
        // a plan direction (dx, dy) as a compass azimuth: the plan's top edge faces `bearing`
        func down(_ d: Pt) -> Double {
            (input.bearing + atan2(d.x, -d.y) * 180 / .pi).truncatingRemainder(dividingBy: 360).normalizedDegrees
        }
        var out: [RoofFace] = []
        func add(_ id: String, _ poly: [Pt], _ edges: [RoofFace.Edge], _ map: @escaping (Double, Double) -> Pt, _ dir: Pt) {
            out.append(RoofFace(id: id, polygon: poly, edges: edges, tilt: th, slopeLength: ls, azimuth: down(sw(dir.x, dir.y)),
                                map: { u, v in let p = map(u, v); return sw(p.x, p.y) }, standard: standard))
        }
        let rect = [Pt(0, 0), Pt(a, 0), Pt(a, ls), Pt(0, ls)], gableEdges: [RoofFace.Edge] = [.eave, .verge, .ridge, .verge]
        switch input.shape {
        case .shed:
            // the low eave at the plan's bottom (or right), or at its top (or left) when the survey turned it
            if input.shedLowAtStart {
                add("N", rect, gableEdges, { u, v in Pt(a - u, v * c) }, Pt(0, -1))
            } else {
                add("S", rect, gableEdges, { u, v in Pt(u, b - v * c) }, Pt(0, 1))
            }
        case .hip:
            let rl = max(0, a - b)
            let trap = [Pt(0, 0), Pt(a, 0), Pt(a - (a - rl) / 2, ls), Pt((a - rl) / 2, ls)], hipEdges: [RoofFace.Edge] = [.eave, .hip, .ridge, .hip]
            add("S", trap, hipEdges, { u, v in Pt(u, b - v * c) }, Pt(0, 1))
            add("N", trap, hipEdges, { u, v in Pt(a - u, v * c) }, Pt(0, -1))
            let tri = [Pt(0, 0), Pt(b, 0), Pt(h, ls)]
            add("E", tri, [.eave, .hip, .hip], { u, v in Pt(a - v * c, b - u) }, Pt(1, 0))
            add("W", tri, [.eave, .hip, .hip], { u, v in Pt(v * c, u) }, Pt(-1, 0))
        case .gable:
            add("S", rect, gableEdges, { u, v in Pt(u, b - v * c) }, Pt(0, 1))
            add("N", rect, gableEdges, { u, v in Pt(a - u, v * c) }, Pt(0, -1))
        }
        faces = out; along = a; across = b; self.rise = rise; tilt = th; slopeLength = ls
    }

    /// Purlins up the slope from the eave, `s` apart, plus one at the ridge when the last gap is over a quarter of `s`.
    public static func purlins(slopeLength ls: Double, spacing s: Double) -> [Double] {
        var t = [0.0]
        while t[t.count - 1] + s <= ls + 1e-9 { t.append(t[t.count - 1] + s) }
        if ls - t[t.count - 1] > 0.25 * s { t.append(ls) }
        return t
    }
}

extension Double {
    /// 0 ..< 360.
    var normalizedDegrees: Double { self < 0 ? self + 360 : self }
}

// MARK: - Polygons

enum Polygon {
    /// The convex hull, counter-clockwise (Andrew's monotone chain), of points rounded to 1 µm.
    static func hull(_ points: [Pt]) -> [Pt] {
        let p = Array(Set(points.map { Pt(($0.x * 1e6).rounded() / 1e6, ($0.y * 1e6).rounded() / 1e6) }))
            .sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count >= 3 else { return p }
        func cross(_ o: Pt, _ a: Pt, _ b: Pt) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [Pt] = [], upper: [Pt] = []
        for q in p {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    /// Two convex polygons overlap (separating axis test; touching edges don't count).
    static func overlap(_ a: [Pt], _ b: [Pt]) -> Bool {
        // the projections' ranges on each edge normal, without allocating
        func separated(_ poly: [Pt]) -> Bool {
            let n = poly.count
            for i in 0..<n {
                let p1 = poly[i], p2 = poly[i + 1 == n ? 0 : i + 1]
                let nx = p2.y - p1.y, ny = p1.x - p2.x
                var aMin = Double.infinity, aMax = -Double.infinity, bMin = Double.infinity, bMax = -Double.infinity
                for q in a { let d = nx * q.x + ny * q.y; aMin = min(aMin, d); aMax = max(aMax, d) }
                for q in b { let d = nx * q.x + ny * q.y; bMin = min(bMin, d); bMax = max(bMax, d) }
                if aMax <= bMin || bMax <= aMin { return true }
            }
            return false
        }
        return !separated(a) && !separated(b)
    }

    /// `subject` clipped to the convex, counter-clockwise polygon `clip` (Sutherland–Hodgman).
    static func clip(_ subject: [Pt], to clip: [Pt]) -> [Pt] {
        var out = subject
        for i in clip.indices {
            let a = clip[i], b = clip[(i + 1) % clip.count]
            func inside(_ p: Pt) -> Bool { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0 }
            func cross(_ p: Pt, _ q: Pt) -> Pt {
                let d1 = Pt(q.x - p.x, q.y - p.y), d2 = Pt(b.x - a.x, b.y - a.y)
                let den = d1.x * d2.y - d1.y * d2.x
                guard abs(den) > 1e-12 else { return p }
                let t = ((a.x - p.x) * d2.y - (a.y - p.y) * d2.x) / den
                return Pt(p.x + t * d1.x, p.y + t * d1.y)
            }
            let input = out
            out = []
            guard !input.isEmpty else { break }
            var prev = input[input.count - 1]
            for p in input {
                if inside(p) {
                    if !inside(prev) { out.append(cross(prev, p)) }
                    out.append(p)
                } else if inside(prev) {
                    out.append(cross(prev, p))
                }
                prev = p
            }
        }
        return out
    }

    static func bounds(_ p: [Pt]) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
        (p.map(\.x).min() ?? 0, p.map(\.y).min() ?? 0, p.map(\.x).max() ?? 0, p.map(\.y).max() ?? 0)
    }
}

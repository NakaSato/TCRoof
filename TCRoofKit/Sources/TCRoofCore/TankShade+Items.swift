import Foundation

/// D1's shade objects placed one by one around the tank (docs/ui/survey-d1-obstacles-ipad Part B): trees, buildings and
/// water towers, each with its own position, height and width, in place of the long walls per compass side. Stored in
/// the hidden `shadeItems` field (JSON); a job without it keeps the long walls (`TankShade.objects`).
extension TankShade {
    /// A thing that stands beside the tank and may shade it.
    ///
    /// Shapes the simulation uses (assumptions, the same for every job):
    /// - **tree**: an ellipsoid crown from 40 % of the height to the top, as wide as `width`; the trunk is ignored and the
    ///   crown blocks all direct sun (the worst case, as the long walls are).
    /// - **building**: a box, `width` × `width` on the ground, flat top at `height`.
    /// - **tower**: a cylinder tank `width` across over the top quarter of the height, on a column of 15 % of the width
    ///   (at least 0.30 m) from the ground to the tank.
    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable { case tree, building, tower }
        /// `T1`, `B1`, `W1` …: a letter per kind and a number.
        public var id: String
        public var kind: Kind
        /// The centre on the plan, metres right of and below the tank's top-left corner (outside the tank: < 0 or > size).
        public var x: Double, y: Double
        /// Above the ground (m).
        public var height: Double
        /// The crown, the footprint's side or the tower tank's diameter (m).
        public var width: Double

        public init(id: String, kind: Kind, x: Double, y: Double, height: Double, width: Double) {
            self.id = id; self.kind = kind; self.x = x; self.y = y; self.height = height; self.width = width
        }

        public static func letter(_ k: Kind) -> String { k == .tree ? "T" : k == .building ? "B" : "W" }
        /// The form's `shadeFrom` option for the kind.
        public static func source(_ k: Kind) -> String { k == .tree ? "ต้นไม้" : k == .building ? "อาคาร" : "หอถังสูง" }
        public static func name(_ k: Kind) -> String { k == .tree ? "ต้นไม้" : k == .building ? "อาคาร" : "หอถังสูง" }

        /// The vertical pieces the shape is made of: (centre radius or half side, bottom, top, round).
        var pieces: [(r: Double, z0: Double, z1: Double, round: Bool)] {
            switch kind {
            case .building: return [(width / 2, 0, height, false)]
            case .tower:
                let tank = 0.75 * height
                return [(max(0.15 * width, 0.3) / 2, 0, tank, true), (width / 2, tank, height, true)]
            case .tree: return []   // the ellipsoid, handled apart
            }
        }

        /// Whether the ray from `o` (x, y on the plan, z above the ground) along `d` (unit) meets the shape ahead.
        func blocks(_ o: (Double, Double, Double), _ d: (Double, Double, Double)) -> Bool {
            // cheap rejects first: above the item, behind the spot, or out of the shadow's reach
            guard o.2 < height else { return false }
            let hx = x - o.0, hy = y - o.1, dist = hypot(hx, hy), reachR = width * 0.75
            if dist > reachR {
                guard hx * d.0 + hy * d.1 > 0 else { return false }
                let horiz = hypot(d.0, d.1)
                if d.2 > 1e-9, (height - o.2) / d.2 * horiz < dist - reachR { return false }
            }
            if kind == .tree {
                // the crown as a unit sphere in scaled space
                let rx = max(width / 2, 0.05), rz = max(0.3 * height, 0.05), zc = 0.7 * height
                let ox = (o.0 - x) / rx, oy = (o.1 - y) / rx, oz = (o.2 - zc) / rz
                let dx = d.0 / rx, dy = d.1 / rx, dz = d.2 / rz
                let a = dx * dx + dy * dy + dz * dz, b = 2 * (ox * dx + oy * dy + oz * dz), c = ox * ox + oy * oy + oz * oz - 1
                let disc = b * b - 4 * a * c
                guard disc >= 0, a > 0 else { return false }
                return (-b + disc.squareRoot()) / (2 * a) > 1e-6
            }
            return pieces.contains { p in
                guard var span = Self.zSpan(o.2, d.2, p.z0, p.z1) else { return false }
                guard let flat = p.round ? Self.circleSpan(o, d, x, y, p.r) : Self.squareSpan(o, d, x, y, p.r) else { return false }
                span = (max(span.0, flat.0), min(span.1, flat.1))
                return span.1 > max(span.0, 1e-6)
            }
        }

        /// The t interval where z(t) = oz + dz·t is between z0 and z1.
        static func zSpan(_ oz: Double, _ dz: Double, _ z0: Double, _ z1: Double) -> (Double, Double)? {
            if abs(dz) < 1e-12 { return oz >= z0 && oz <= z1 ? (-.infinity, .infinity) : nil }
            let a = (z0 - oz) / dz, b = (z1 - oz) / dz
            return (min(a, b), max(a, b))
        }
        /// The t interval inside a vertical cylinder of radius r around (cx, cy).
        static func circleSpan(_ o: (Double, Double, Double), _ d: (Double, Double, Double), _ cx: Double, _ cy: Double, _ r: Double) -> (Double, Double)? {
            let ox = o.0 - cx, oy = o.1 - cy, a = d.0 * d.0 + d.1 * d.1
            if a < 1e-12 { return ox * ox + oy * oy <= r * r ? (-.infinity, .infinity) : nil }
            let b = 2 * (ox * d.0 + oy * d.1), c = ox * ox + oy * oy - r * r, disc = b * b - 4 * a * c
            guard disc >= 0 else { return nil }
            let s = disc.squareRoot()
            return ((-b - s) / (2 * a), (-b + s) / (2 * a))
        }
        /// The t interval inside a vertical square prism of half side h around (cx, cy).
        static func squareSpan(_ o: (Double, Double, Double), _ d: (Double, Double, Double), _ cx: Double, _ cy: Double, _ h: Double) -> (Double, Double)? {
            var lo = -Double.infinity, hi = Double.infinity
            for (p, v, c) in [(o.0, d.0, cx), (o.1, d.1, cy)] {
                if abs(v) < 1e-12 {
                    if p < c - h || p > c + h { return nil }
                } else {
                    let a = (c - h - p) / v, b = (c + h - p) / v
                    lo = max(lo, min(a, b)); hi = min(hi, max(a, b))
                }
            }
            return hi >= lo ? (lo, hi) : nil
        }

        /// Points on the shape's surface, for its shadow outline.
        var samples: [(Double, Double, Double)] {
            var out: [(Double, Double, Double)] = []
            let n = 24
            func ring(_ r: Double, _ z: Double, square: Bool) {
                if square {
                    for (dx, dy) in [(-r, -r), (r, -r), (r, r), (-r, r)] { out.append((x + dx, y + dy, z)) }
                } else {
                    for k in 0..<n { let a = Double(k) / Double(n) * 2 * .pi; out.append((x + r * cos(a), y + r * sin(a), z)) }
                }
            }
            switch kind {
            case .building: ring(width / 2, 0, square: true); ring(width / 2, height, square: true)
            case .tower: for p in pieces { ring(p.r, p.z0, square: false); ring(p.r, p.z1, square: false) }
            case .tree:
                let rz = 0.3 * height, zc = 0.7 * height
                for k in -3...3 {
                    let f = Double(k) / 3, z = zc + f * rz, r = width / 2 * (1 - f * f).squareRoot()
                    ring(max(r, 0.01), z, square: false)
                }
            }
            return out
        }
    }

    public enum ItemKey { public static let items = "shadeItems" }

    // MARK: stored

    public static func items(_ v: Values) -> [Item] {
        let t = v.text(ItemKey.items)
        guard !t.isEmpty, let data = t.data(using: .utf8), let list = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return list
    }

    /// Writes the items and, when there are any, the form's shade answers from them, so Excel, the PDF and the
    /// completion keep reading them: `shade` มี, `shadeFrom` (the kinds), `shadeDir` (each item's side), the tallest
    /// height and the nearest gap to the wall. No items: the field goes and the answers stay as they were.
    public static func setItems(_ v: inout Values, _ list: [Item]) {
        guard !list.isEmpty, let data = try? JSONEncoder().encode(list), let json = String(data: data, encoding: .utf8) else {
            v[ItemKey.items] = nil
            return
        }
        v[ItemKey.items] = .text(json)
        v["shade"] = .choice("มี", other: "")
        let kinds = Item.Kind.allCases.filter { k in list.contains { $0.kind == k } }.map(Item.source)
        v["shadeFrom"] = .multi(kinds)
        let size = TankPoints.tankSize(v) ?? (0, 0), az = Double(Tank.azimuth(v) ?? 0)
        var dirs: [String] = []
        for i in list { let d = direction(of: i, size: size, azimuth: az); if !dirs.contains(d) { dirs.append(d) } }
        v["shadeDir"] = .multi(Schema.shadeDirs.filter(dirs.contains))
        v[Key.height] = .text(fmt(list.map(\.height).max() ?? 0))
        v[Key.distance] = .text(fmt(list.map { gap($0, in: v) }.min() ?? 0))
    }

    /// `T3`: one more than the highest number of that kind.
    public static func nextID(_ kind: Item.Kind, in list: [Item]) -> String {
        let p = Item.letter(kind)
        let n = list.compactMap { $0.id.hasPrefix(p) ? Int($0.id.dropFirst()) : nil }.max() ?? 0
        return p + "\(n + 1)"
    }

    // MARK: geometry

    /// The item's compass side seen from the tank's centre (N … NW); the plan's top faces `azimuth`.
    public static func direction(of i: Item, size: (w: Double, h: Double), azimuth az: Double) -> String {
        let dx = i.x - size.w / 2, dy = i.y - size.h / 2
        let plan = atan2(dx, -dy) * 180 / .pi
        let compass = (plan + az).truncatingRemainder(dividingBy: 360) + (plan + az < 0 ? 360 : 0)
        return Schema.shadeDirs[Int((compass / 45).rounded()) % 8]
    }

    /// The gap between the item's edge and the tank's wall (rim), 0 when it overlaps.
    public static func gap(_ i: Item, in v: Values) -> Double {
        if let c = TankPoints.circle(v) { return max(0, hypot(i.x - c.cx, i.y - c.cy) - c.r - i.width / 2) }
        guard let t = TankPoints.tankSize(v) else { return 0 }
        let dx = max(0, -i.x, i.x - t.w), dy = max(0, -i.y, i.y - t.h)
        return max(0, hypot(dx, dy) - i.width / 2)
    }

    /// Moves the item so its gap to the wall is `g`, along the line from the tank's centre (or nearest wall).
    public static func setGap(_ i: inout Item, _ g: Double, in v: Values) {
        let now = gap(i, in: v), d = max(0, g) - now
        guard abs(d) > 1e-9, let t = TankPoints.tankSize(v) else { return }
        let cx = t.w / 2, cy = t.h / 2
        var ux = i.x - cx, uy = i.y - cy
        if TankPoints.circle(v) == nil {
            // straight out from the nearest wall
            let outX = i.x < 0 || i.x > t.w, outY = i.y < 0 || i.y > t.h
            if outX && !outY { uy = 0 } else if outY && !outX { ux = 0 }
        }
        let len = hypot(ux, uy)
        guard len > 1e-9 else { return }
        i.x += ux / len * d; i.y += uy / len * d
    }

    /// The direction towards the sun, on the plan (x right, y down) and up: unit.
    static func toward(_ alt: Double, _ sAz: Double, planAzimuth az: Double) -> (Double, Double, Double) {
        let sv = Sim.planVector(sAz + 180, az), a = SolarModel.rad(alt)
        return (sv.0 * cos(a), sv.1 * cos(a), sin(a))
    }

    /// The item's shadow on the plane `z` above the ground with the sun at `alt`, `sAz` (from south, + west): its outline
    /// on the plan (the convex hull of the shape's points cast along the sun); empty with the sun down or the item
    /// below the plane.
    public static func shadow(_ i: Item, altitude alt: Double, azimuth sAz: Double, planAzimuth az: Double, onPlane z: Double) -> [(x: Double, y: Double)] {
        guard alt > 0.5 else { return [] }
        let d = toward(alt, sAz, planAzimuth: az)
        let cast = i.samples.compactMap { p -> (Double, Double)? in
            guard p.2 > z else { return nil }
            let t = (p.2 - z) / d.2
            return (p.0 - d.0 * t, p.1 - d.1 * t)
        }
        // the footprint at the plane too, so the shadow starts at the object
        let base = i.samples.compactMap { p -> (Double, Double)? in p.2 > z ? (p.0, p.1) : nil }
        return hull(cast + base).map { (x: $0.0, y: $0.1) }
    }

    /// Andrew's monotone chain.
    static func hull(_ pts: [(Double, Double)]) -> [(Double, Double)] {
        let p = pts.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        guard p.count > 2 else { return p }
        func cross(_ o: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
            (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
        }
        var lower: [(Double, Double)] = [], upper: [(Double, Double)] = []
        for q in p { while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }; lower.append(q) }
        for q in p.reversed() { while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }; upper.append(q) }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// The item's skyline seen from the tank's centre on the roof: the compass span it covers and its top altitude.
    public static func skyline(_ i: Item, size: (w: Double, h: Double), planAzimuth az: Double, exposed: Double) -> (from: Double, to: Double, altitude: Double) {
        let dx = i.x - size.w / 2, dy = i.y - size.h / 2, dist = max(hypot(dx, dy), 0.1)
        let centre = (atan2(dx, -dy) * 180 / .pi + az + 360).truncatingRemainder(dividingBy: 360)
        let half = atan(i.width / 2 / dist) * 180 / .pi
        let alt = max(0, atan((i.height - exposed) / dist) * 180 / .pi)
        return (centre - half, centre + half, alt)
    }

    // MARK: a moment

    /// One moment on the screen: the sun, and the panels without direct sun to the rows and to each item.
    public struct Moment: Sendable {
        public var altitude: Double, azimuth: Double
        public var rowShaded: Set<String> = []
        public var itemShaded: [String: Set<String>] = [:]
    }

    /// The moment at the 21st of `month`, `time` hours; nil with the sun down. Without a stored layout only the sun.
    public static func moment(_ v: Values, latitude: Double, month: Int, time: Double) -> Moment? {
        guard let s = sun(latitude: latitude, month: month, time: time) else { return nil }
        var m = Moment(altitude: s.altitude, azimuth: s.azimuth)
        guard let l = TankLayout.current(v), l.count > 0 else { return m }
        let list = items(v)
        let sim = Sim(layout: l, objects: list.isEmpty ? objects(v) : [], azimuth: Tank.azimuth(v).map(Double.init), exposed: Tank.exposed(v) ?? 0, items: list)
        let split = sim.shadedSplit(s.altitude, s.azimuth)
        m.rowShaded = Set(split.row.map { sim.spots[$0].key })
        for (spot, k) in sim.itemHits(s.altitude, s.azimuth) { m.itemShaded[list[k].id, default: []].insert(sim.spots[spot].key) }
        return m
    }

    // MARK: the sun

    /// Day of the year of the 21st of `month` (0–11), the day the screen and the sun path use.
    public static func day21(_ month: Int) -> Int {
        let starts = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        return starts[min(max(month, 0), 11)] + 21
    }

    /// The sun at the 21st of the month, `time` hours (solar time); nil below the horizon.
    public static func sun(latitude: Double, month: Int, time: Double) -> (altitude: Double, azimuth: Double)? {
        SolarModel.sun(lat: latitude, day: day21(month), time: time)
    }

    /// The month's sun in 30-minute steps while it is up: time, altitude, azimuth from south (+ west).
    public static func sunPath(latitude: Double, month: Int) -> [(time: Double, altitude: Double, azimuth: Double)] {
        stride(from: 4.0, through: 20.0, by: 0.5).compactMap { t in sun(latitude: latitude, month: month, time: t).map { (t, $0.altitude, $0.azimuth) } }
    }
}

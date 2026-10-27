import Foundation
import PVYield

/// The roof's own obstacles shading its modules (docs/ui/survey-c1-ipad-shade, change 1): each obstacle with a height
/// (`RoofMountInput.Obstacle.heightOrDefault` > 0) stands on its face as a box (its plan rectangle × its height); for a
/// sun direction, the part of the box above a face is projected along the sun onto that face's plane, and the share of
/// the face's module rectangles it covers is the beam that face loses. One projection serves the hourly figures
/// (`hourly`, into PVYield's `ArrayFace.beamShadeHourly`), the plan's moment (`shadedSlots`, `shadows`) and the shade
/// card's sun-path silhouettes, so they agree. Nil for a layout with no obstacle of any height: the figures stay as
/// they were.
public struct RoofObstacleShade: Hashable, Sendable {
    /// A point or direction in 3D: x, y on the plan (metres from its top-left, y down), z up.
    public struct P3: Hashable, Sendable {
        public var x, y, z: Double
        public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
        static func + (a: P3, b: P3) -> P3 { P3(a.x + b.x, a.y + b.y, a.z + b.z) }
        static func - (a: P3, b: P3) -> P3 { P3(a.x - b.x, a.y - b.y, a.z - b.z) }
        static func * (k: Double, a: P3) -> P3 { P3(k * a.x, k * a.y, k * a.z) }
        func dot(_ b: P3) -> Double { x * b.x + y * b.y + z * b.z }
        init(_ v: V3) { self.init(v.x, v.y, v.z) }
    }

    public struct Obstacle: Hashable, Sendable {
        public var title: String
        /// The face it stands on.
        public var face: String
        /// Its base corners on that face, and its height above them.
        public var base: [P3]
        public var height: Double
    }

    /// A face's plane and the modules on it, in its own (u, v).
    public struct Face: Hashable, Sendable {
        public var id: String
        var origin: P3, eu: P3, ev: P3, normal: P3
        /// Module rectangles (u0, v0, u1, v1) and their slots.
        public var modules: [[Double]]
        public var slots: [RoofMountLayout.SlotRef]
        /// Faces in use only: the estimate runs on those.
        public var used: Bool

        func uv(_ p: P3) -> Pt {
            let d = p - origin
            return Pt(d.dot(eu) / eu.dot(eu), d.dot(ev) / ev.dot(ev))
        }
        func point(_ u: Double, _ v: Double) -> P3 { origin + u * eu + v * ev }
        /// Height of a point above the plane, along its normal.
        func above(_ p: P3) -> Double { normal.dot(p - origin) }
    }

    public var obstacles: [Obstacle]
    public var faces: [Face]
    /// Compass bearing of the plan's top edge.
    public var bearing: Double

    /// The layout's obstacles with a height and its modules; nil when no obstacle has a height.
    public init?(_ layout: RoofMountLayout) {
        let w = layout.moduleAlong, l = layout.moduleUp
        var faces: [Face] = [], obstacles: [Obstacle] = []
        for f in layout.faces {
            let rf = f.face
            var rects: [[Double]] = [], slots: [RoofMountLayout.SlotRef] = []
            for (r, row) in f.rows.enumerated() {
                for (c, s) in row.slots.enumerated() where s.isModule {
                    rects.append([s.u, row.v, s.u + w, row.v + l])
                    slots.append(.init(face: rf.id, row: r, column: c))
                }
            }
            faces.append(Face(id: rf.id, origin: P3(rf.origin), eu: P3(rf.eu), ev: P3(rf.ev), normal: P3(rf.normal),
                              modules: rects, slots: slots, used: f.used))
            for ob in f.obstacles where ob.home && ob.obstacle.heightOrDefault > 0 {
                let o = ob.obstacle
                let base = [Pt(o.x, o.y), Pt(o.x + o.w, o.y), Pt(o.x + o.w, o.y + o.h), Pt(o.x, o.y + o.h)]
                    .map { c -> P3 in let p = rf.uv(c.x, c.y); return P3(rf.point3(p.x, p.y)) }
                obstacles.append(Obstacle(title: o.title, face: rf.id, base: base, height: o.heightOrDefault))
            }
        }
        guard !obstacles.isEmpty, let first = layout.faces.first?.face else { return nil }
        self.obstacles = obstacles
        self.faces = faces
        // the face's downslope on the plan is −ev; its azimuth = bearing + atan2(dx, −dy)
        bearing = first.azimuth - atan2(-first.ev.x, first.ev.y) * 180 / .pi
    }

    // MARK: - Sun

    /// The direction to the sun in plan axes, from its compass azimuth and elevation (°).
    public func sun(azimuth: Double, elevation: Double) -> P3 {
        let alt = elevation * .pi / 180, az = (azimuth - bearing) * .pi / 180
        return P3(sin(az) * cos(alt), -cos(az) * cos(alt), sin(alt))
    }

    /// The plan's moment (docs/ui/survey-c1-ipad-shade 3b): 21 December 09:00 local time.
    public static func planMoment(latitude: Double, longitude: Double, utcOffsetHours: Double = 7) -> (azimuth: Double, elevation: Double) {
        let midnight = 1_797_811_200.0   // 2026-12-21 00:00 UTC
        let p = SolarPosition.position(unix: midnight + (9 - utcOffsetHours) * 3600, site: .init(latitude: latitude, longitude: longitude))
        return (p.azimuth, p.apparentElevation)
    }

    // MARK: - Projection

    /// Each obstacle's shadow on a face's plane, in its (u, v): the part of the box above the plane projected along
    /// `sun`. Nil where the sun is behind the face or the obstacle casts nothing on it.
    func shadows(on f: Face, sun s: P3) -> [[Pt]?] {
        let ns = f.normal.dot(s)
        guard ns > 1e-6, s.z > 0 else { return obstacles.map { _ in nil } }
        return obstacles.map { o in
            var pts: [Pt] = []
            for b in o.base {
                let top = b + P3(0, 0, o.height)
                let db = f.above(b), dt = f.above(top)
                guard dt > 1e-9 else { continue }
                // a vertical edge's part above the plane: from where it crosses it, or from its foot
                let low = db >= 0 ? b : b + (db / (db - dt)) * (top - b)
                for p in [low, top] { pts.append(f.uv(p - (f.above(p) / ns) * s)) }
            }
            guard pts.count >= 3 else { return nil }
            let h = Polygon.hull(pts)
            return h.count >= 3 ? h : nil
        }
    }

    /// The share of each module of face `i` in a shadow with the sun at `sun` (0–1, overlapping shadows capped at 1).
    public func moduleShade(face i: Int, sun: P3) -> [Double] {
        let f = faces[i]
        var out = [Double](repeating: 0, count: f.modules.count)
        let hulls = shadows(on: f, sun: sun).compactMap { $0 }
        guard !hulls.isEmpty else { return out }
        for h in hulls {
            let b = Polygon.bounds(h)
            for (m, r) in f.modules.enumerated() where r[0] < b.x1 && b.x0 < r[2] && r[1] < b.y1 && b.y0 < r[3] {
                let rect = [Pt(r[0], r[1]), Pt(r[2], r[1]), Pt(r[2], r[3]), Pt(r[0], r[3])]
                let a = (r[2] - r[0]) * (r[3] - r[1])
                guard a > 0 else { continue }
                out[m] = min(1, out[m] + Self.area(Polygon.clip(rect, to: h)) / a)
            }
        }
        return out
    }

    /// The share of face `i`'s module area in shadow.
    public func fraction(face i: Int, sun: P3) -> Double {
        let m = moduleShade(face: i, sun: sun)
        return m.isEmpty ? 0 : m.reduce(0, +) / Double(m.count)
    }

    /// Every hour of a sun track, per face id: the share of the face's modules in shadow (0 with the sun down).
    public func hourly(_ track: SunTrack) -> [String: [Double]] {
        var out: [String: [Double]] = [:]
        for (i, f) in faces.enumerated() where f.used && !f.modules.isEmpty {
            var v = [Double](repeating: 0, count: track.hours.count)
            for (k, h) in track.hours.enumerated() where h.zenith < 90 && h.dni > 0 {
                v[k] = fraction(face: i, sun: sun(azimuth: h.azimuth, elevation: 90 - h.zenith))
            }
            out[f.id] = v
        }
        return out
    }

    /// The modules in shadow (any part) with the sun at `sun`, faces in use only.
    public func shadedSlots(sun: P3) -> Set<RoofMountLayout.SlotRef> {
        var out: Set<RoofMountLayout.SlotRef> = []
        for (i, f) in faces.enumerated() where f.used {
            for (m, x) in moduleShade(face: i, sun: sun).enumerated() where x > 1e-9 { out.insert(f.slots[m]) }
        }
        return out
    }

    /// Each obstacle's shadow on the face it stands on, on the plan (metres): its base and its top moved away from the
    /// sun along that face, so the plan's bearing and the face's slope are in it.
    public func shadows(sun: P3) -> [[Pt]] {
        obstacles.indices.compactMap { k in
            guard let f = faces.first(where: { $0.id == obstacles[k].face }), let h = shadows(on: f, sun: sun)[k] else { return nil }
            return h.map { p in let q = f.point(p.x, p.y); return Pt(q.x, q.y) }
        }
    }

    /// The plan's marks at the shade card's moment (21 December 09:00 at the site).
    public func moment(latitude: Double, longitude: Double) -> RoofPlan.ShadeMoment {
        let m = Self.planMoment(latitude: latitude, longitude: longitude), s = sun(azimuth: m.azimuth, elevation: m.elevation)
        return RoofPlan.ShadeMoment(slots: shadedSlots(sun: s), shadows: m.elevation > 0 ? shadows(sun: s) : [])
    }

    // MARK: - Seen from the modules

    /// The middle of the modules of the faces named (all in use when empty), in 3D.
    public func centre(faces ids: Set<String> = []) -> P3? {
        var sum = P3(0, 0, 0), n = 0.0
        for f in faces where f.used && (ids.isEmpty || ids.contains(f.id)) {
            for r in f.modules { sum = sum + f.point((r[0] + r[2]) / 2, (r[1] + r[3]) / 2); n += 1 }
        }
        return n > 0 ? (1 / n) * sum : nil
    }

    /// Each obstacle as seen from `from`: the hull of its corners as (compass azimuth, elevation) in degrees, the
    /// part below the horizon left out.
    public func silhouettes(from c: P3) -> [[Pt]] {
        obstacles.compactMap { o in
            let pts = (o.base + o.base.map { $0 + P3(0, 0, o.height) }).map { p -> Pt in
                let d = p - c, flat = hypot(d.x, d.y)
                let az = (bearing + atan2(d.x, -d.y) * 180 / .pi).truncatingRemainder(dividingBy: 360)
                return Pt(az < 0 ? az + 360 : az, max(0, atan2(d.z, flat) * 180 / .pi))
            }
            guard pts.contains(where: { $0.y > 0.5 }) else { return nil }
            // unwrap around north so the hull doesn't span the whole circle
            let ref = pts[0].x
            let unwrapped = pts.map { p -> Pt in
                var a = p.x
                while a - ref > 180 { a -= 360 }
                while ref - a > 180 { a += 360 }
                return Pt(a, p.y)
            }
            let h = Polygon.hull(unwrapped)
            return h.count >= 3 ? h : nil
        }
    }

    static func area(_ p: [Pt]) -> Double {
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        for i in p.indices { let a = p[i], b = p[(i + 1) % p.count]; s += a.x * b.y - b.x * a.y }
        return abs(s) / 2
    }
}

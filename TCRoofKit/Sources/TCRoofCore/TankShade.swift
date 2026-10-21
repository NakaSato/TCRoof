import Foundation

/// D1's shade simulation (docs/specs/tank-drawing-swift.md, old step 4 `เงาบัง`): over a year of clear-sky sun
/// (`SolarModel`'s samples), which panels of the stored layout lose their direct sun, to the row in front of them
/// (tank-mounting-layout.md §3a step 4, with the portrait-2 rule) or to what stands beside the tank (`shadeFrom` in
/// the `shadeDir` directions, `shadeHeight` above the ground and `shadeDistance` from the wall). Diffuse light is kept.
/// Each object is taken as running the whole length of its side (ค่าสมมติ, the worst case).
public struct TankShade: Sendable {
    public enum Key {
        public static let height = "shadeHeight", distance = "shadeDistance"
    }

    /// An object beside the tank: its compass direction from the tank, height above the ground and distance from the wall.
    public struct Object: Sendable, Equatable {
        public var direction: String, height: Double, distance: Double
        public init(direction: String, height: Double, distance: Double) { self.direction = direction; self.height = height; self.distance = distance }
    }

    /// A moment drawn on the plan: the panels without direct sun then.
    public struct Snapshot: Sendable {
        public var title: String
        public var shaded: Set<String>
    }

    /// Yearly losses, as shares of the unshaded energy.
    public var rowLoss = 0.0, objectLoss = 0.0
    public var totalLoss: Double { rowLoss + objectLoss }
    /// MWh a year: unshaded, and lost to the objects.
    public var energy = 0.0, objectMWh = 0.0
    /// The share of panels without direct sun by month (0–11) and hour (0–23); nil when the sun is down all hour.
    public var heat: [[Double?]] = Array(repeating: Array(repeating: nil, count: 24), count: 12)
    public var snapshots: [Snapshot] = []
    /// The objects simulated (none when the survey says nothing shades the tank, or gives no height).
    public var objects: [Object] = []
    /// The height the objects would have to be cut to for less than 1 % loss (nil: not needed, or no cut helps).
    public var cutTo: Double?

    // MARK: inputs

    public static func objects(_ v: Values) -> [Object] {
        guard Schema.shaded(v), let h = v.number(Key.height), h > 0 else { return [] }
        let d = max(0, v.number(Key.distance) ?? 0)
        return v.multi("shadeDir").filter { direction($0) != nil }.map { Object(direction: $0, height: h, distance: d) }
    }

    /// N, NE, … as a compass bearing.
    static func direction(_ d: String) -> Double? { Schema.shadeDirs.firstIndex(of: d).map { Double($0) * 45 } }

    // MARK: the simulation

    /// The shade on the stored layout; nil without one.
    public init?(_ v: Values, latitude: Double) {
        guard let l = TankLayout.current(v), l.count > 0 else { return nil }
        self.init(layout: l, objects: Self.objects(v), azimuth: Tank.azimuth(v).map(Double.init), exposed: Tank.exposed(v) ?? 0,
                  latitude: latitude)
    }

    /// One panel as the simulation sees it: its centre on the plan, its height above the roof, its row and whether a
    /// row stands in front of it, and its place on the slope (0 the upper module, 1 the lower).
    struct Spot { var key: String; var x, y, z: Double; var lower: Bool; var behindRow: Bool }

    public init(layout l: TankLayout, objects: [Object], azimuth: Double?, exposed: Double, latitude lat: Double) {
        self.objects = objects
        let sim = Sim(layout: l, objects: objects, azimuth: azimuth, exposed: exposed)
        let r = sim.run(latitude: lat, dayStep: SolarModel.dayStep, minutes: SolarModel.stepMinutes)
        rowLoss = r.rowLoss; objectLoss = r.objectLoss
        energy = l.kWp * l.yield(latitude: lat, facing: sim.facing) / 1000
        objectMWh = energy * objectLoss
        heat = r.heat
        let moments: [(day: Int, time: Double, title: String)] = [
            (80, 9, "21 มี.ค. 09:00"), (80, 15, "21 มี.ค. 15:00"), (172, 9, "21 มิ.ย. 09:00"),
            (172, 15, "21 มิ.ย. 15:00"), (355, 9, "21 ธ.ค. 09:00"), (355, 15, "21 ธ.ค. 15:00"),
        ]
        snapshots = moments.map { m in
            guard let s = SolarModel.sun(lat: lat, day: m.day, time: m.time) else { return Snapshot(title: m.title, shaded: []) }
            return Snapshot(title: m.title, shaded: Set(sim.shaded(s.altitude, s.azimuth).map { sim.spots[$0].key }))
        }
        // how low the objects would have to be for under 1 % loss, in 0.5 m steps (on fewer samples)
        if objectLoss >= 0.01, let top = objects.map(\.height).max() {
            var h = top - 0.5
            while h > exposed {
                let lower = objects.map { o -> Object in var o = o; o.height = min(o.height, h); return o }
                let trial = Sim(layout: l, objects: lower, azimuth: azimuth, exposed: exposed).run(latitude: lat, dayStep: 9, minutes: 30)
                if trial.objectLoss < 0.01 { cutTo = h; break }
                h -= 0.5
            }
        }
    }

    /// The simulation's geometry: the panels, the plan's compass and the objects as long walls beside the tank.
    struct Sim {
        struct Line { var ux, uy, s0, h: Double }
        let spots: [Spot], lines: [Line]
        let az, facing, gp, beta, slope, pitch: Double

        init(layout l: TankLayout, objects: [Object], azimuth: Double?, exposed: Double) {
            // the panels face the wall they slope down to
            let facing = ((azimuth ?? 0) + [180.0, 90, 0, 270][l.turn]).truncatingRemainder(dividingBy: 360)
            self.init(spots: TankShade.spots(l), facing: facing, params: l.params, size: l.size, objects: objects, azimuth: azimuth, exposed: exposed,
                      circle: l.circle)
        }

        /// Any panels on the plan facing `facing` (compass), such as the true-south comparison's. A round tank's
        /// objects stand beside its rim.
        init(spots: [Spot], facing: Double, params p: TankLayout.Params, size: (w: Double, h: Double), objects: [Object],
             azimuth: Double?, exposed: Double, circle: TankPoints.Circle? = nil) {
            az = azimuth ?? 0
            self.facing = facing
            gp = (facing - 180 + 540).truncatingRemainder(dividingBy: 360) - 180
            self.spots = spots
            beta = SolarModel.rad(p.tilt); slope = 2 * p.moduleL + p.moduleGap; pitch = p.rowPitch
            let corners = [(0.0, 0.0), (size.w, 0), (0, size.h), (size.w, size.h)], a = az
            lines = objects.compactMap { o in
                guard let b = TankShade.direction(o.direction) else { return nil }
                let u = Sim.planVector(b, a)
                let edge = circle.map { $0.cx * u.0 + $0.cy * u.1 + $0.r } ?? (corners.map { $0.0 * u.0 + $0.1 * u.1 }.max() ?? 0)
                return Line(ux: u.0, uy: u.1, s0: edge + o.distance, h: o.height - exposed)
            }
        }

        /// A compass bearing on the plan, whose top faces `az`.
        static func planVector(_ b: Double, _ az: Double) -> (Double, Double) { let r = SolarModel.rad(b - az); return (sin(r), -cos(r)) }

        /// The panels without direct sun with the sun at `alt`, `sAz` (from south, + west): to the row in front
        /// (row) and to the objects (object).
        func shadedSplit(_ alt: Double, _ sAz: Double) -> (row: Set<Int>, object: Set<Int>) {
            let a = SolarModel.rad(alt), rel = SolarModel.rad(sAz - gp)
            var row = Set<Int>(), obj = Set<Int>()
            if cos(rel) > 1e-6 {
                // the row in front shades the share f of the slope (tank-mounting-layout.md §3a step 4)
                let ap = atan(tan(a) / cos(rel))
                let f = 1 - (pitch / slope) * sin(ap) / sin(ap + beta)
                if f > 0.04 { for (i, s) in spots.enumerated() where s.behindRow && (s.lower || f > 0.54) { row.insert(i) } }
            }
            if !lines.isEmpty {
                // towards the sun on the plan: the sun's compass bearing is 180 + its azimuth from south
                let sv = Sim.planVector(sAz + 180, az), ta = tan(a)
                for (i, s) in spots.enumerated() {
                    for o in lines {
                        let toward = sv.0 * o.ux + sv.1 * o.uy
                        guard toward > 1e-6, o.h - s.z > 0 else { continue }
                        let run = (o.s0 - (s.x * o.ux + s.y * o.uy)) / toward
                        if run > 0, run * ta < o.h - s.z { obj.insert(i); break }
                    }
                }
            }
            return (row, obj)
        }
        func shaded(_ alt: Double, _ sAz: Double) -> Set<Int> { let h = shadedSplit(alt, sAz); return h.row.union(h.object) }

        /// The year: losses as shares of the unshaded energy, and the heat map.
        func run(latitude lat: Double, dayStep: Int, minutes: Double) -> (rowLoss: Double, objectLoss: Double, heat: [[Double?]]) {
            var unshaded = 0.0, rowOnly = 0.0, both = 0.0
            var sum = Array(repeating: Array(repeating: 0.0, count: 24), count: 12), cnt = Array(repeating: Array(repeating: 0, count: 24), count: 12)
            let k = Double(spots.count)
            var n = 1
            while n < 366 {
                let month = TankShade.month(n)
                var t = 5.0
                while t <= 19.0 {
                    if let s = SolarModel.sun(lat: lat, day: n, time: t) {
                        let irr = SolarModel.irradiance(day: n, altitude: s.altitude)
                        let a = SolarModel.rad(s.altitude), rel = SolarModel.rad(s.azimuth - gp)
                        let beam = irr.dni * max(0, cos(beta) * sin(a) + sin(beta) * cos(a) * cos(rel))
                        let diffuse = irr.dhi * (1 + cos(beta)) / 2 + irr.ghi * SolarModel.albedo * (1 - cos(beta)) / 2
                        let hit = shadedSplit(s.altitude, s.azimuth)
                        let rowLost = Double(hit.row.count), anyLost = Double(hit.row.union(hit.object).count)
                        unshaded += (beam + diffuse) * k
                        rowOnly += beam * (k - rowLost) + diffuse * k
                        both += beam * (k - anyLost) + diffuse * k
                        if k > 0 { sum[month][Int(t)] += anyLost / k; cnt[month][Int(t)] += 1 }
                    }
                    t += minutes / 60
                }
                n += dayStep
            }
            var heat: [[Double?]] = Array(repeating: Array(repeating: nil, count: 24), count: 12)
            for m in 0..<12 { for h in 0..<24 where cnt[m][h] > 0 { heat[m][h] = sum[m][h] / Double(cnt[m][h]) } }
            guard unshaded > 0 else { return (0, 0, heat) }
            return ((unshaded - rowOnly) / unshaded, (rowOnly - both) / unshaded, heat)
        }
    }

    // MARK: the last answer

    /// The simulation for these values, kept for the next call with the same values and latitude (E1 asks on every render).
    public static func current(_ v: Values, latitude: Double) -> TankShade? {
        if let hit = cache.get(v, latitude) { return hit.shade }
        let s = TankShade(v, latitude: latitude)
        cache.set(v, latitude, s)
        return s
    }
    private static let cache = Last()
    private final class Last: @unchecked Sendable {
        private let lock = NSLock()
        struct Entry { var values: Values; var latitude: Double; var shade: TankShade? }
        private var entry: Entry?
        func get(_ v: Values, _ lat: Double) -> Entry? {
            lock.lock(); defer { lock.unlock() }
            return entry?.values == v && entry?.latitude == lat ? entry : nil
        }
        func set(_ v: Values, _ lat: Double, _ s: TankShade?) { lock.lock(); entry = Entry(values: v, latitude: lat, shade: s); lock.unlock() }
    }

    // MARK: report

    /// `เงาแถวหน้า 1.7% | เงาสิ่งบัง 0.4% | สูญเสียรวม 2.1% | เสียจากสิ่งบัง 1.2 MWh/ปี`
    public var summaryLine: String {
        String(format: "เงาแถวหน้า %.1f%% | เงาสิ่งบัง %.1f%% | สูญเสียรวม %.1f%% | เสียจากสิ่งบัง %.1f MWh/ปี",
               rowLoss * 100, objectLoss * 100, totalLoss * 100, objectMWh)
    }

    /// One recommendation line (a proposal for E1).
    public func recommendation(_ v: Values) -> String {
        if objects.isEmpty {
            return Schema.shaded(v) ? "ใส่ความสูงและระยะห่างของสิ่งที่บังในขั้นที่ 2 เพื่อคิดเงาจากสิ่งบัง" : "ไม่มีสิ่งบังรอบถัง | เงามาจากแถวแผงหน้าเท่านั้น"
        }
        let what = v.multi("shadeFrom").joined(separator: " / "), side = objects.map(\.direction).joined(separator: ", ")
        let name = what.isEmpty ? "สิ่งที่บัง" : what
        if objectLoss < 0.01 { return String(format: "%@ด้าน %@ ทำให้เสียพลังงาน %.1f%% | ยอมรับได้ ไม่ต้องแก้", name, side, objectLoss * 100) }
        if let h = cutTo {
            return String(format: "เสนอตัดแต่ง%@ด้าน %@ ให้สูงไม่เกิน %@ ม. จะเหลือการสูญเสียต่ำกว่า 1%% (ตอนนี้ %.1f%%, %.1f MWh/ปี)", name, side,
                          fmt(h), objectLoss * 100, objectMWh)
        }
        return String(format: "%@ด้าน %@ ทำให้เสียพลังงาน %.1f%% (%.1f MWh/ปี) | เสนอเว้นแผงด้านนั้นหรือย้ายสิ่งบัง", name, side, objectLoss * 100, objectMWh)
    }

    // MARK: helpers

    /// The layout's panels with the height of their centre above the roof and whether a row stands in front of them.
    static func spots(_ l: TankLayout) -> [Spot] {
        let p = l.params, alongX = l.turn % 2 == 0
        let built = l.builtTables
        func span(_ t: TankLayout.Table) -> (Double, Double) { alongX ? (t.x, t.x + t.w) : (t.y, t.y + t.h) }
        var out: [Spot] = []
        for t in built {
            let ahead = built.filter { $0.row == t.row - 1 }
            let (a, b) = span(t)
            let behind = ahead.contains { let (c, d) = span($0); return c < b - 1e-6 && a < d - 1e-6 }
            for panel in t.panels where panel.on {
                let lower = panel.key.hasSuffix(".1")
                out.append(Spot(key: panel.key, x: panel.x + panel.w / 2, y: panel.y + panel.h / 2, z: height(p, lower: lower),
                                lower: lower, behindRow: behind))
            }
        }
        return out
    }

    /// A module's centre above the roof: the lower module's middle or the upper's, along the tilt from the front post.
    static func height(_ p: TankLayout.Params, lower: Bool) -> Double {
        let along = lower ? p.cellH / 2 - p.frontIn : p.cellH * 1.5 + p.moduleGap * p.cosT - p.frontIn
        return p.hFront + along * p.tanT
    }

    /// The month (0–11) of day `n` of the year.
    static func month(_ n: Int) -> Int {
        let ends = [31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]
        return ends.firstIndex { n <= $0 } ?? 11
    }
}

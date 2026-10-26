import Foundation

/// The clear-sky sun and yield model of the mounting layouts (docs/specs/roof-pv-layout.md §3.4 and §3.7, the same as
/// the tank's `energy_factors` in docs/specs/img/tank_mount_opt.py): sun positions by day and solar time, irradiance,
/// and the yearly kWh per kWp of an unshaded plane.
public enum SolarModel {
    static let clearness = 0.72, performanceRatio = 0.80, albedo = 0.20
    static let stepMinutes = 15.0, dayStep = 3

    /// The sun's altitude and azimuth (degrees; azimuth from south, + west) on day `n` of the year at solar time `t`
    /// (hours), at latitude `lat`; nil below the horizon.
    public static func sun(lat: Double, day n: Int, time t: Double) -> (altitude: Double, azimuth: Double)? {
        let d = rad(23.45 * sin(rad(360 * Double(284 + n) / 365)))
        let w = rad(15 * (t - 12)), p = rad(lat)
        let sa = sin(p) * sin(d) + cos(p) * cos(d) * cos(w)
        let a = asin(max(-1, min(1, sa)))
        guard a > 0 else { return nil }
        let cz = (sin(a) * sin(p) - sin(d)) / (cos(a) * cos(p))
        let g = deg(acos(max(-1, min(1, cz)))) * (w > 0 ? 1 : -1)
        return (deg(a), g)
    }

    /// Clear-sky global, direct normal and diffuse irradiance (W/m²) at sun altitude `alt` on day `n`.
    static func irradiance(day n: Int, altitude alt: Double) -> (ghi: Double, dni: Double, dhi: Double) {
        let cz = sin(rad(alt))
        let ghi = 1098 * cz * exp(-0.057 / cz) * clearness
        let i0 = 1367 * (1 + 0.033 * cos(rad(360 * Double(n) / 365))) * cz
        let kt = i0 > 0 ? ghi / i0 : 0
        let fd = kt <= 0.22 ? 1 - 0.09 * kt
            : kt <= 0.8 ? 0.9511 - 0.1604 * kt + 4.388 * pow(kt, 2) - 16.638 * pow(kt, 3) + 12.336 * pow(kt, 4) : 0.165
        let dhi = ghi * fd
        return (ghi, (ghi - dhi) / cz, dhi)
    }

    struct Sample { let altitude, azimuth, ghi, dni, dhi: Double }

    /// Every 15 minutes from 05:00 to 19:00 on every third day, with the sun up. About 6,000 sun positions, so they
    /// are kept per latitude: pages ask for a plane's yield on every redraw.
    static func samples(lat: Double) -> [Sample] {
        if let hit = sampleCache.get(lat) { return hit }
        let out = computeSamples(lat: lat)
        sampleCache.set(lat, out)
        return out
    }

    static func computeSamples(lat: Double) -> [Sample] {
        var out: [Sample] = []
        for n in stride(from: 1, to: 366, by: dayStep) {
            var t = 5.0
            while t <= 19.0 {
                if let s = sun(lat: lat, day: n, time: t) {
                    let i = irradiance(day: n, altitude: s.altitude)
                    out.append(Sample(altitude: s.altitude, azimuth: s.azimuth, ghi: i.ghi, dni: i.dni, dhi: i.dhi))
                }
                t += stepMinutes / 60
            }
        }
        return out
    }

    /// Yearly kWh per kWp of an unshaded plane tilted `tilt`° and facing `azimuth`° from south (+ west), with the
    /// performance ratio.
    public static func yield(lat: Double, tilt: Double, azimuthFromSouth gp: Double) -> Double {
        let key = YieldKey(lat: lat, tilt: tilt, azimuth: gp)
        if let hit = yieldCache.get(key) { return hit }
        let y = computeYield(lat: lat, tilt: tilt, azimuthFromSouth: gp)
        yieldCache.set(key, y)
        return y
    }

    static func computeYield(lat: Double, tilt: Double, azimuthFromSouth gp: Double) -> Double {
        let b = rad(tilt), dt = stepMinutes / 60 * Double(dayStep)
        var sum = 0.0
        for s in samples(lat: lat) {
            let a = rad(s.altitude), rel = rad(s.azimuth - gp)
            let cosI = cos(b) * sin(a) + sin(b) * cos(a) * cos(rel)
            let beam = s.dni * max(0, cosI)
            let diffuse = s.dhi * (1 + cos(b)) / 2 + s.ghi * albedo * (1 - cos(b)) / 2
            sum += (beam + diffuse) * dt
        }
        return sum * performanceRatio / 1000
    }

    /// The last few latitudes' samples (a page shows one site; a test may try several).
    final class SampleCache: @unchecked Sendable {
        private var items: [(lat: Double, samples: [Sample])] = []
        private let lock = NSLock()
        func get(_ lat: Double) -> [Sample]? { lock.lock(); defer { lock.unlock() }; return items.first { $0.lat == lat }?.samples }
        func set(_ lat: Double, _ s: [Sample]) {
            lock.lock(); defer { lock.unlock() }
            items.removeAll { $0.lat == lat }
            items.insert((lat, s), at: 0)
            if items.count > 8 { items.removeLast() }
        }
    }
    static let sampleCache = SampleCache()

    struct YieldKey: Hashable { let lat, tilt, azimuth: Double }

    /// Planes already worked out, by their exact inputs.
    final class YieldCache: @unchecked Sendable {
        private var items: [YieldKey: Double] = [:]
        private let lock = NSLock()
        func get(_ k: YieldKey) -> Double? { lock.lock(); defer { lock.unlock() }; return items[k] }
        func set(_ k: YieldKey, _ v: Double) {
            lock.lock(); defer { lock.unlock() }
            if items.count > 1024 { items.removeAll() }
            items[k] = v
        }
    }
    static let yieldCache = YieldCache()

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }
}

import Foundation

/// NREL Solar Position Algorithm (Reda & Andreas 2008), as pvlib's `spa_python` runs it with `get_solarposition`'s
/// defaults: elevation 0 m, 1013.25 hPa, 12 °C, ΔT = 67 s, refraction 0.5667°. Angles in degrees; azimuth from north,
/// clockwise.
///
/// The slow terms (Earth's heliocentric position, nutation, obliquity: `Geocentric`) cost ~330 trig calls; the
/// local hour angle, parallax and refraction (`topocentric`) cost a dozen. `SunTrack` works the slow terms out once
/// at each end of an hour and interpolates them for the 5-minute samples inside it.
public enum SolarPosition {
    public struct Position: Sendable, Equatable {
        /// Zenith with refraction (pvlib `apparent_zenith`).
        public var apparentZenith: Double
        /// Zenith without refraction.
        public var zenith: Double
        public var azimuth: Double
        public var apparentElevation: Double { 90 - apparentZenith }
    }

    public struct Site: Sendable, Equatable {
        public var latitude: Double, longitude: Double
        public var elevation: Double
        /// hPa (millibar).
        public var pressure: Double
        public var temperature: Double
        public var refraction: Double
        public init(latitude: Double, longitude: Double, elevation: Double = 0, pressure: Double = 1013.25,
                    temperature: Double = 12, refraction: Double = 0.5667) {
            self.latitude = latitude; self.longitude = longitude; self.elevation = elevation
            self.pressure = pressure; self.temperature = temperature; self.refraction = refraction
        }
    }

    public static let defaultDeltaT = 67.0

    /// The Sun's geocentric place at one instant: everything that doesn't depend on the observer.
    public struct Geocentric: Sendable, Equatable {
        /// Right ascension and declination (°).
        public var alpha: Double, delta: Double
        /// Nutation in longitude and the true obliquity (°).
        public var deltaPsi: Double, epsilon: Double
        /// Equatorial horizontal parallax (°).
        public var xi: Double

        /// Linear interpolation (`alpha` unwrapped across 360°).
        public func lerp(_ o: Geocentric, _ f: Double) -> Geocentric {
            var da = o.alpha - alpha
            if da > 180 { da -= 360 } else if da < -180 { da += 360 }
            return Geocentric(alpha: alpha + da * f, delta: delta + (o.delta - delta) * f,
                              deltaPsi: deltaPsi + (o.deltaPsi - deltaPsi) * f,
                              epsilon: epsilon + (o.epsilon - epsilon) * f, xi: xi + (o.xi - xi) * f)
        }
    }

    public static func position(unix: Double, site: Site, deltaT: Double = defaultDeltaT) -> Position {
        topocentric(unix: unix, geocentric(unix: unix, deltaT: deltaT), site: site)
    }

    // MARK: - Slow terms

    public static func geocentric(unix: Double, deltaT: Double = defaultDeltaT) -> Geocentric {
        let jd = unix / 86400 + 2440587.5
        let jde = jd + deltaT / 86400
        let jce = (jde - 2451545) / 36525
        let jme = jce / 10
        let r = series([R0, R1, R2, R3, R4], jme)
        let l = mod360(deg(series([L0, L1, L2, L3, L4, L5], jme)))
        let b = deg(series([B0, B1], jme))
        let theta = mod360(l + 180), beta = -b
        let x0 = 297.85036 + 445267.111480 * jce - 0.0019142 * jce * jce + pow(jce, 3) / 189474
        let x1 = 357.52772 + 35999.050340 * jce - 0.0001603 * jce * jce - pow(jce, 3) / 300000
        let x2 = 134.96298 + 477198.867398 * jce + 0.0086972 * jce * jce + pow(jce, 3) / 56250
        let x3 = 93.27191 + 483202.017538 * jce - 0.0036825 * jce * jce + pow(jce, 3) / 327270
        let x4 = 125.04452 - 1934.136261 * jce + 0.0020708 * jce * jce + pow(jce, 3) / 450000
        var psiSum = 0.0, epsSum = 0.0
        for t in nutation {
            let arg = rad(t.y.0 * x0 + t.y.1 * x1 + t.y.2 * x2 + t.y.3 * x3 + t.y.4 * x4)
            psiSum += (t.a + t.b * jce) * sin(arg)
            epsSum += (t.c + t.d * jce) * cos(arg)
        }
        let deltaPsi = psiSum / 36_000_000, deltaEps = epsSum / 36_000_000
        let u = jme / 10
        var e0 = 84381.448 - 4680.93 * u - 1.55 * pow(u, 2) + 1999.25 * pow(u, 3) - 51.38 * pow(u, 4)
        e0 += -249.67 * pow(u, 5) - 39.05 * pow(u, 6) + 7.12 * pow(u, 7) + 27.87 * pow(u, 8) + 5.79 * pow(u, 9) + 2.45 * pow(u, 10)
        let epsilon = e0 / 3600 + deltaEps
        let lambda = theta + deltaPsi - 20.4898 / (3600 * r)
        let le = rad(lambda), ee = rad(epsilon), be = rad(beta)
        let alpha = mod360(deg(atan2(sin(le) * cos(ee) - tan(be) * sin(ee), cos(le))))
        let delta = deg(asin(sin(be) * cos(ee) + cos(be) * sin(ee) * sin(le)))
        return Geocentric(alpha: alpha, delta: delta, deltaPsi: deltaPsi, epsilon: epsilon, xi: 8.794 / (3600 * r))
    }

    /// Σ_k (Σ_i A·cos(B + C·x)) · x^k / 10⁸.
    static func series(_ tables: [[(Double, Double, Double)]], _ x: Double) -> Double {
        var total = 0.0, p = 1.0
        for t in tables {
            var s = 0.0
            for row in t { s += row.0 * cos(row.1 + row.2 * x) }
            total += s * p
            p *= x
        }
        return total / 1e8
    }

    // MARK: - Observer

    public static func topocentric(unix: Double, _ g: Geocentric, site: Site) -> Position {
        let jd = unix / 86400 + 2440587.5
        let jc = (jd - 2451545) / 36525
        let v0 = mod360(280.46061837 + 360.98564736629 * (jd - 2451545) + 0.000387933 * jc * jc - pow(jc, 3) / 38_710_000)
        let v = v0 + g.deltaPsi * cos(rad(g.epsilon))
        let h = mod360(v + site.longitude - g.alpha)
        let lat = rad(site.latitude)
        let u = atan(0.99664719 * tan(lat))
        let x = cos(u) + site.elevation / 6378140 * cos(lat)
        let y = 0.99664719 * sin(u) + site.elevation / 6378140 * sin(lat)
        let xi = rad(g.xi), hr = rad(h), dr = rad(g.delta)
        let dAlpha = deg(atan2(-x * sin(xi) * sin(hr), cos(dr) - x * sin(xi) * cos(hr)))
        let deltaP = deg(atan2((sin(dr) - y * sin(xi)) * cos(rad(dAlpha)), cos(dr) - x * sin(xi) * cos(hr)))
        let hp = rad(h - dAlpha), dp = rad(deltaP)
        let e0 = deg(asin(sin(lat) * sin(dp) + cos(lat) * cos(dp) * cos(hp)))
        var de = 0.0
        if e0 >= -(0.26667 + site.refraction) {
            de = (site.pressure / 1010) * (283 / (273 + site.temperature)) * 1.02 / (60 * tan(rad(e0 + 10.3 / (e0 + 5.11))))
        }
        let gamma = mod360(deg(atan2(sin(hp), cos(hp) * sin(lat) - tan(dp) * cos(lat))))
        return Position(apparentZenith: 90 - (e0 + de), zenith: 90 - e0, azimuth: mod360(gamma + 180))
    }

    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }
    @inline(__always) static func mod360(_ d: Double) -> Double {
        let m = d.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }
}

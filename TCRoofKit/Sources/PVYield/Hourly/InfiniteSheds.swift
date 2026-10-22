import Foundation

/// pvlib's infinite sheds (`pvlib.bifacial.infinite_sheds`, isotropic sky, 0.16.1): 2D view factors for long rows
/// of equal pitch on flat ground, which the reference engine uses for row-to-row shading on the front
/// (`sheds`) and for the bifacial rear side (`rear_irradiance`).
///
/// For each side of a row (the front, and the back at 180° − tilt facing the other way) and each hour:
/// - beam on the unshaded part of the row: `shadedFraction` from the row in front;
/// - sky diffuse through the row's averaged view of the sky between its neighbours;
/// - light reflected by the ground between the rows, of which the beam part only lands on the unshaded ground and
///   the sky part on the ground's averaged view of the sky.
///
/// The view factors depend only on the geometry, so they are worked out once per array. Angles in degrees,
/// azimuths from north clockwise, irradiance in W/m², lengths in any one unit.
public struct InfiniteSheds: Sendable, Equatable {
    public struct Geometry: Sendable, Equatable {
        /// Row tilt and the compass bearing the front faces.
        public var tilt: Double, azimuth: Double
        /// Ground coverage ratio: slant length over pitch.
        public var gcr: Double
        /// Height of the row's centre above the ground, and the row pitch.
        public var height: Double, pitch: Double
        public var albedo: Double
        public init(tilt: Double, azimuth: Double, gcr: Double, height: Double, pitch: Double, albedo: Double) {
            self.tilt = tilt; self.azimuth = azimuth; self.gcr = gcr; self.height = height; self.pitch = pitch; self.albedo = albedo
        }
    }

    /// One side of the row in one hour (pvlib's `poa_*` and `shaded_fraction` of that side).
    public struct Side: Sendable, Equatable {
        public var direct: Double, skyDiffuse: Double, groundDiffuse: Double
        /// Share of the side in the next row's shadow, 0…1.
        public var shadedFraction: Double
        public var global: Double { direct + skyDiffuse + groundDiffuse }
        public static let zero = Side(direct: 0, skyDiffuse: 0, groundDiffuse: 0, shadedFraction: 0)
    }

    /// The geometry's view factors for one side.
    public struct ViewFactors: Sendable, Equatable {
        /// The side's tilt and the bearing it faces.
        public var tilt: Double, azimuth: Double
        /// Row to sky, row to ground, and ground (between two rows) to sky, each averaged over the surface.
        public var rowSky: Double, rowGround: Double, groundSky: Double
    }

    public var geometry: Geometry
    public var front: ViewFactors, back: ViewFactors

    public init(_ g: Geometry) {
        geometry = g
        let backTilt = 180 - g.tilt, backAzimuth = (180 + g.azimuth).truncatingRemainder(dividingBy: 360)
        // rows either side whose shadow can still reach the ground between the two rows (5° above the horizon)
        let maxRows = (g.height / (g.pitch * tan(Self.rad(5)))).rounded(.up)
        func factors(_ tilt: Double, _ azimuth: Double) -> ViewFactors {
            ViewFactors(tilt: tilt, azimuth: azimuth, rowSky: Self.rowSkyIntegrated(tilt: tilt, gcr: g.gcr),
                        rowGround: Self.rowGroundIntegrated(tilt: tilt, gcr: g.gcr),
                        groundSky: Self.groundSkyIntegrated(rotation: tilt, gcr: g.gcr, height: g.height, pitch: g.pitch, maxRows: maxRows))
        }
        front = factors(g.tilt, g.azimuth)
        back = factors(backTilt, backAzimuth)
    }

    /// Both sides for one hour: `get_irradiance` (its `poa_front_*` and `poa_back_*`). NaN, which pvlib's callers
    /// fill with 0, comes out as 0.
    public func irradiance(zenith: Double, sunAzimuth: Double, ghi: Double, dhi: Double, dni: Double) -> (front: Side, back: Side) {
        (side(front, zenith: zenith, sunAzimuth: sunAzimuth, ghi: ghi, dhi: dhi, dni: dni),
         side(back, zenith: zenith, sunAzimuth: sunAzimuth, ghi: ghi, dhi: dhi, dni: dni))
    }

    /// `get_irradiance_poa` for one side.
    func side(_ v: ViewFactors, zenith: Double, sunAzimuth: Double, ghi: Double, dhi: Double, dni: Double) -> Side {
        let g = geometry
        let tanPhi = Self.solarProjectionTangent(zenith: zenith, sunAzimuth: sunAzimuth, surfaceAzimuth: v.azimuth)
        let phi = Self.deg(atan(tanPhi))
        let groundBeam = Self.unshadedGroundFraction(rotation: v.tilt, phi: phi, gcr: g.gcr)
        let fx = Self.shadedFraction(zenith: zenith, sunAzimuth: sunAzimuth, tilt: v.tilt, azimuth: v.azimuth, gcr: g.gcr)
        let sky = dhi * v.rowSky
        let groundLight = g.albedo * (groundBeam * (ghi - dhi) + v.groundSky * dhi)
        let ground = groundLight * v.rowGround
        let beam = max(dni * Irradiance.aoiProjection(tilt: v.tilt, azimuth: v.azimuth, zenith: zenith, sunAzimuth: sunAzimuth), 0)
        let direct = beam * (1 - fx)
        return Side(direct: finite(direct), skyDiffuse: finite(sky), groundDiffuse: finite(ground), shadedFraction: finite(fx))
    }

    // MARK: pvlib.bifacial.utils

    /// Tangent of the sun's elevation projected onto the plane across the rows.
    static func solarProjectionTangent(zenith: Double, sunAzimuth: Double, surfaceAzimuth: Double) -> Double {
        cos(rad(sunAzimuth - surfaceAzimuth)) * tan(rad(zenith))
    }

    /// `_shaded_fraction`: the share of the row's slant in the shadow of the row in front.
    static func shadedFraction(zenith: Double, sunAzimuth: Double, tilt: Double, azimuth: Double, gcr: Double) -> Double {
        let tanPhi = solarProjectionTangent(zenith: zenith, sunAzimuth: sunAzimuth, surfaceAzimuth: azimuth)
        let x = gcr * (sin(rad(tilt)) * tanPhi + cos(rad(tilt)))
        var f = 1 - 1 / x
        if !(Irradiance.aoi(tilt: tilt, azimuth: azimuth, zenith: zenith, sunAzimuth: sunAzimuth) < 90) { f = 1 }
        if !(x > 1) { f = 0 }
        return f
    }

    /// `_unshaded_ground_fraction` over the whole gap between two rows (g0 = 0, g1 = 1): the share of the ground
    /// the beam reaches. Rows −10…11 cast shadows; 0 when the projected sun is lower than 5° (|φ| > 85°).
    static func unshadedGroundFraction(rotation: Double, phi: Double, gcr: Double, maxRows: Int = 10, maxZenith: Double = 85) -> Double {
        let height = 1.0, pitch = 1 / gcr
        let width = pitch * gcr
        let lCos = width * cos(rad(rotation)), lSin = width * sin(rad(rotation))
        let tanPhi = tan(rad(phi))
        let a = 0.0, b = pitch
        var sum = 0.0
        for k in -maxRows...(maxRows + 1) {
            let kp = Double(k) * pitch
            var cp = (kp + 0.5 * lCos) + (height + 0.5 * lSin) * tanPhi
            var dp = (kp - 0.5 * lCos) + (height - 0.5 * lSin) * tanPhi
            if dp > cp { swap(&cp, &dp) }
            // numpy's chain of `where`s: a later condition wins
            var fs = 1.0
            if dp <= a && a <= cp && cp < b { fs = (cp - a) / (b - a) }
            if dp < a && cp < a { fs = 0 }
            if a < dp && dp <= b && cp >= b { fs = (b - dp) / (b - a) }
            if a < dp && dp < b && a < cp && cp < b { fs = (cp - dp) / (b - a) }
            if dp > b && cp > b { fs = 0 }
            sum += fs
        }
        if abs(phi) > maxZenith { return 0 }
        return 1 - min(1, max(0, sum))
    }

    /// `vf_row_sky_2d_integ` over the whole slant (x0 = 0, x1 = 1).
    static func rowSkyIntegrated(tilt: Double, gcr: Double) -> Double {
        let p0 = poly(tilt: tilt, gcr: gcr, x: 1, delta: -1), p1 = poly(tilt: tilt, gcr: gcr, x: 0, delta: -1)
        return 0.5 * (1 + (p1 - p0))
    }

    static func poly(tilt: Double, gcr: Double, x: Double, delta: Double) -> Double {
        let a = 1 / gcr, c = cos(rad(tilt))
        return (a * a + 2 * delta * a * c * x + x * x).squareRoot()
    }

    /// `vf_row_ground_2d_integ` over the whole slant and the whole gap (x and g from 0 to 1), rows −20…19.
    static func rowGroundIntegrated(tilt t: Double, gcr: Double, maxRows: Int = 20) -> Double {
        let tilt = t == 180 ? 179.9999 : (t == -180 ? -179.9999 : t)
        let height = 1.0, pitch = 1 / gcr, width = pitch * gcr
        let lCos = width * cos(rad(tilt)), lSin = width * sin(rad(tilt))
        var obRight = P(-pitch - 0.5001 * lCos, height - 0.5001 * abs(lSin))
        var obLeft = P(obRight.x + pitch, obRight.y)
        if tilt < 0 { let r = obRight.x; obRight.x = -obLeft.x; obLeft.x = -r }
        let a = P(-0.5 * lCos, height - 0.5 * lSin), b = P(0.5 * lCos, height + 0.5 * lSin)
        var total = 0.0
        for k in -maxRows..<maxRows {
            let c = P(Double(k) * pitch, 0), d = P(Double(k + 1) * pitch, 0)
            let s = obstructedStringLengths(a, b, c, d, obLeft, obRight)
            total += max(1 / (2 * width) * ((s.ac + s.bd) - (s.bc + s.ad)), 0)
        }
        return total
    }

    /// `vf_ground_sky_2d_integ` over the whole gap (g0 = 0, g1 = 1): the sky the ground between two rows sees.
    static func groundSkyIntegrated(rotation: Double, gcr: Double, height: Double, pitch: Double, maxRows: Double) -> Double {
        let width = pitch * gcr
        let lCos = width * cos(rad(rotation)), lSin = width * sin(rad(rotation))
        let sign: Double = rotation > 0 ? 1 : (rotation < 0 ? -1 : 0)
        let a = P(0, 0), b = P(pitch, 0)
        var total = 0.0
        var k = -maxRows
        while k < maxRows + 1 {
            let c = P((k + 1) * pitch + sign * 0.5 * lCos, height + sign * 0.5 * lSin)
            let d = P(c.x - pitch, c.y)
            let left = P(k * pitch - 0.5 * lCos, height - 0.5 * lSin), right = P(k * pitch + 0.5 * lCos, height + 0.5 * lSin)
            let obLeft = angle(a, left) > angle(a, right) ? right : left
            let left2 = P(left.x + pitch, left.y), right2 = P(right.x + pitch, right.y)
            let obRight = angle(b, left2) > angle(b, right2) ? left2 : right2
            let s = obstructedStringLengths(a, b, c, d, obLeft, obRight)
            total += max(0.5 / pitch * ((s.ac + s.bd) - (s.bc + s.ad)), 0)
            k += 1
        }
        return total
    }

    struct P: Equatable { var x: Double, y: Double; init(_ x: Double, _ y: Double) { self.x = x; self.y = y } }

    /// Hottel's crossed strings with each string bent round the obstruction it passes (`_obstructed_string_lengths`).
    static func obstructedStringLengths(_ a: P, _ b: P, _ c: P, _ d: P, _ obLeft: P, _ obRight: P)
        -> (ac: Double, ad: Double, bc: Double, bd: Double) {
        func string(_ from: P, _ to: P) -> Double {
            let direct = angle(from, to)
            var len = dist(from, to)
            if direct - angle(from, obLeft) > 1e-8 { len = dist(from, obLeft) + dist(obLeft, to) }
            if angle(from, obRight) - direct > 1e-8 { len = dist(from, obRight) + dist(obRight, to) }
            return len
        }
        return (string(a, c), string(a, d), string(b, c), string(b, d))
    }

    @inline(__always) static func dist(_ p: P, _ q: P) -> Double { ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot() }
    @inline(__always) static func angle(_ p: P, _ q: P) -> Double { atan2(q.y - p.y, q.x - p.x) }
    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }
    @inline(__always) func finite(_ x: Double) -> Double { x.isFinite ? x : 0 }
}

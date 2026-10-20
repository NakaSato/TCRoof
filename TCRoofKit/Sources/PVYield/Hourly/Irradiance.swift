import Foundation

/// Plane-of-array irradiance, as the reference engine gets it from pvlib `get_total_irradiance(model="perez")`:
/// beam on the plane, Perez 1990 sky diffuse ("allsitescomposite1990"), isotropic ground reflection. Angles in
/// degrees, azimuths from north clockwise (180 = south), irradiance in W/m².
public enum Irradiance {
    public struct PlaneOfArray: Sendable, Equatable {
        public var direct: Double, sky: Double, ground: Double
        /// Angle of incidence of the beam (°).
        public var aoi: Double
        public var global: Double { direct + sky + ground }
        public static let zero = PlaneOfArray(direct: 0, sky: 0, ground: 0, aoi: 90)
    }

    /// Extraterrestrial normal irradiance (Spencer 1971, pvlib's default, solar constant 1366.1 W/m²).
    public static func extraterrestrial(dayOfYear doy: Int, solarConstant: Double = 1366.1) -> Double {
        let b = 2 * Double.pi / 365 * Double(doy - 1)
        return solarConstant * (1.00011 + 0.034221 * cos(b) + 0.00128 * sin(b) + 0.000719 * cos(2 * b) + 0.000077 * sin(2 * b))
    }

    /// Kasten & Young (1989) relative airmass from the apparent zenith; nil below the horizon (> 90°).
    public static func relativeAirmass(apparentZenith z: Double) -> Double? {
        guard z <= 90, !z.isNaN else { return nil }
        return 1 / (cos(rad(z)) + 0.50572 * pow(6.07995 + (90 - z), -1.6364))
    }

    /// cos(angle of incidence), clipped to −1…1.
    public static func aoiProjection(tilt: Double, azimuth: Double, zenith: Double, sunAzimuth: Double) -> Double {
        let p = cos(rad(tilt)) * cos(rad(zenith)) + sin(rad(tilt)) * sin(rad(zenith)) * cos(rad(sunAzimuth - azimuth))
        return min(1, max(-1, p))
    }

    public static func aoi(tilt: Double, azimuth: Double, zenith: Double, sunAzimuth: Double) -> Double {
        deg(acos(aoiProjection(tilt: tilt, azimuth: azimuth, zenith: zenith, sunAzimuth: sunAzimuth)))
    }

    /// Perez et al. (1990) clearness bins (lower edges of bins 2…8) and F1 / F2 coefficients.
    static let perezBins = [0, 1.065, 1.23, 1.5, 1.95, 2.8, 4.5, 6.2]
    static let perezF1: [(Double, Double, Double)] = [
        (-0.008, 0.588, -0.062), (0.13, 0.683, -0.151), (0.33, 0.487, -0.221), (0.568, 0.187, -0.295),
        (0.873, -0.392, -0.362), (1.132, -1.237, -0.412), (1.06, -1.6, -0.359), (0.678, -0.327, -0.25),
    ]
    static let perezF2: [(Double, Double, Double)] = [
        (-0.06, 0.072, -0.022), (-0.019, 0.066, -0.029), (0.055, -0.064, -0.026), (0.109, -0.152, -0.014),
        (0.226, -0.462, 0.001), (0.288, -0.823, 0.056), (0.264, -1.127, 0.131), (0.156, -1.377, 0.251),
    ]

    /// Perez sky diffuse on a tilted plane (pvlib `perez`). Returns 0 where pvlib gives NaN (no sky light, or the
    /// sun below the horizon, where the engine fills NaN with 0).
    public static func perezSkyDiffuse(tilt: Double, azimuth: Double, dhi: Double, dni: Double, dniExtra: Double,
                                       zenith: Double, sunAzimuth: Double, airmass: Double?) -> Double {
        guard let am = airmass, dhi > 0 else { return 0 }
        let kappa = 1.041, z = rad(zenith)
        let delta = dhi * am / dniExtra
        let eps = ((dhi + dni) / dhi + kappa * z * z * z) / (1 + kappa * z * z * z)
        guard eps >= 0 else { return 0 }
        var bin = 7
        for k in 1..<perezBins.count where eps < perezBins[k] { bin = k - 1; break }
        let c1 = perezF1[bin], c2 = perezF2[bin]
        let f1 = max(c1.0 + c1.1 * delta + c1.2 * z, 0)
        let f2 = c2.0 + c2.1 * delta + c2.2 * z
        let a = max(aoiProjection(tilt: tilt, azimuth: azimuth, zenith: zenith, sunAzimuth: sunAzimuth), 0)
        let b = max(cos(z), cos(rad(85)))
        let t1 = 0.5 * (1 - f1) * (1 + cos(rad(tilt))), t2 = f1 * a / b, t3 = f2 * sin(rad(tilt))
        return max(dhi * (t1 + t2 + t3), 0)
    }

    /// Ground-reflected light on a tilted plane, isotropic.
    public static func groundDiffuse(tilt: Double, ghi: Double, albedo: Double) -> Double {
        ghi * albedo * (1 - cos(rad(tilt))) * 0.5
    }

    /// The plane's beam, sky and ground parts for one hour of `SunTrack`.
    public static func planeOfArray(tilt: Double, azimuth: Double, albedo: Double, hour h: SunTrack.Hour) -> PlaneOfArray {
        let proj = aoiProjection(tilt: tilt, azimuth: azimuth, zenith: h.zenith, sunAzimuth: h.azimuth)
        let sky = perezSkyDiffuse(tilt: tilt, azimuth: azimuth, dhi: h.dhi, dni: h.dni, dniExtra: h.dniExtra,
                                  zenith: h.zenith, sunAzimuth: h.azimuth, airmass: h.airmass)
        // pvlib's 0/0 in Perez (no DHI and no DNI) happens only when GHI is 0 too (`SunTrack`), so the NaN it fills
        // with 0 leaves nothing to lose here
        return PlaneOfArray(direct: max(h.dni * proj, 0), sky: sky, ground: groundDiffuse(tilt: tilt, ghi: h.ghi, albedo: albedo),
                            aoi: deg(acos(proj)))
    }

    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }
}

/// Incidence angle modifiers: ASHRAE for the beam, Marion (2017) integration of it for sky and ground diffuse.
public enum IAM {
    /// ASHRAE: 1 − b0·(1/cos θ − 1), 0 at and beyond 90°, never below 0.
    public static func ashrae(aoi: Double, b0: Double = 0.05) -> Double {
        guard abs(aoi) < 90 else { return 0 }
        return max(0, 1 - b0 * (1 / cos(aoi * .pi / 180) - 1))
    }

    /// Diffuse correction factors of a plane tilted `tilt`° for the sky dome and the ground (pvlib
    /// `marion_diffuse`, 180 zenith steps).
    public static func marionDiffuse(tilt: Double, b0: Double = 0.05) -> (sky: Double, ground: Double) {
        (marion(tilt: tilt, sky: true, b0: b0), marion(tilt: tilt, sky: false, b0: b0))
    }

    static func marion(tilt: Double, sky: Bool, b0: Double, steps num: Int = 180) -> Double {
        let beta = tilt * .pi / 180, ai = Double.pi / Double(num)
        var numerator = 0.0, denominator = 0.0
        for i in 0..<num {
            let phi1 = Double(i) * ai
            if sky ? !(phi1 + ai <= .pi / 2) : !(phi1 >= .pi / 2) { continue }
            let phiAvg = phi1 + 0.5 * ai
            let dAs = ai * (cos(phi1) - cos(phi1 + ai))
            let t1 = cos(beta) * cos(phiAvg), s = sin(beta) * sin(phiAvg)
            for j in 0..<(2 * num) {
                let cosAoi = t1 + s * cos(Double(j) * ai + 0.5 * ai)
                let aoi = acos(cosAoi)
                guard aoi < .pi / 2 else { continue }
                numerator += ashrae(aoi: aoi * 180 / .pi, b0: b0) * cosAoi * dAs
                denominator += cosAoi * dAs
            }
        }
        return denominator != 0 ? numerator / denominator : 0
    }
}

/// PVsyst cell temperature: T_air + G_poa·α·(1 − η) / (Uc + Uv·wind).
public struct ThermalModel: Codable, Sendable, Equatable {
    /// W/m²K: 29 free-standing, 20 semi-integrated (railed roof), 15 integrated.
    public var uc: Double
    public var uv: Double
    public var alpha: Double
    public init(uc: Double = 20, uv: Double = 0, alpha: Double = 0.9) { self.uc = uc; self.uv = uv; self.alpha = alpha }

    public func cellTemperature(poaGlobal g: Double, airTemp t: Double, wind: Double, moduleEfficiency eta: Double) -> Double {
        t + g * alpha * (1 - eta) / (uc + uv * wind)
    }
}

import Foundation

/// The bifacial rear side without rows (the reference's `rear_irradiance`): infinite sheds in the rear's own frame.
extension BifacialRear {
    /// The sheds the rear side sits in, for a face tilted `tilt` towards `azimuth`. In the roof frame the rows lie on
    /// the roof at `tiltRelDeg` (at least 0.01°), facing up the slope (180° in that frame).
    func sheds(faceTilt tilt: Double, faceAzimuth azimuth: Double) -> InfiniteSheds {
        let gcr = moduleSlantM / pitchM
        switch frame {
        case .roof:
            return InfiniteSheds(.init(tilt: max(tiltRelDeg, 0.01), azimuth: 180, gcr: gcr, height: heightM, pitch: pitchM, albedo: albedo))
        case .ground:
            return InfiniteSheds(.init(tilt: tilt, azimuth: azimuth, gcr: gcr, height: heightM, pitch: pitchM, albedo: albedo))
        }
    }

    /// Light on the back of the modules (W/m²), before bifaciality and rear mismatch; 0 while GHI is 0.
    /// - Parameter roofSky: the Perez sky diffuse on the roof plane (the sky the roof frame sees).
    func rearIrradiance(_ sheds: InfiniteSheds, faceTilt tilt: Double, faceAzimuth azimuth: Double, roofSky: Double,
                        hour h: SunTrack.Hour) -> Double {
        guard h.ghi > 0 else { return 0 }
        switch frame {
        case .ground:
            return sheds.irradiance(zenith: h.zenith, sunAzimuth: h.azimuth, ghi: h.ghi, dhi: h.dhi, dni: h.dni).back.global
        case .roof:
            let sun = Self.sunInRoofFrame(zenith: h.zenith, azimuth: h.azimuth, roofTilt: tilt, roofAzimuth: azimuth)
            let ghiRoof = h.dni * max(cos(sun.zenith * .pi / 180), 0) + roofSky
            return sheds.irradiance(zenith: sun.zenith, sunAzimuth: sun.azimuth, ghi: ghiRoof, dhi: roofSky, dni: h.dni).back.global
        }
    }

    /// The sun's zenith and azimuth (°) seen from a roof tilted `roofTilt` towards `roofAzimuth`: zenith from the
    /// roof's normal, azimuth from up the slope (0°) turning towards the roof's "across" axis (up-slope × normal).
    static func sunInRoofFrame(zenith: Double, azimuth: Double, roofTilt: Double, roofAzimuth: Double) -> (zenith: Double, azimuth: Double) {
        let z = zenith * .pi / 180, a = azimuth * .pi / 180, b = roofTilt * .pi / 180, ra = roofAzimuth * .pi / 180
        let s = (sin(z) * sin(a), sin(z) * cos(a), cos(z))                       // east, north, up
        let n = (sin(b) * sin(ra), sin(b) * cos(ra), cos(b))                     // roof normal
        let u = (-cos(b) * sin(ra), -cos(b) * cos(ra), sin(b))                   // up the slope
        let c = (u.1 * n.2 - u.2 * n.1, u.2 * n.0 - u.0 * n.2, u.0 * n.1 - u.1 * n.0)
        func dot(_ p: (Double, Double, Double), _ q: (Double, Double, Double)) -> Double { p.0 * q.0 + p.1 * q.1 + p.2 * q.2 }
        let zf = acos(min(1, max(-1, dot(s, n)))) * 180 / .pi
        let af = (atan2(dot(s, c), dot(s, u)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (zf, af)
    }
}

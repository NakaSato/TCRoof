import Foundation

/// System losses of the hourly chain, fractions (the reference's `Losses`).
public struct YieldLosses: Codable, Sendable, Equatable {
    public var albedo = 0.20
    /// ASHRAE IAM b0.
    public var iamB0 = 0.05
    public var soiling = 0.03
    /// Negative = gain.
    public var moduleQuality = 0.0
    public var lid = 0.01
    public var mismatch = 0.01
    /// DC wiring loss at STC current, scaled with I/Imp and Vmp/V each hour.
    public var dcOhmicAtSTC = 0.015
    /// AC wiring loss at nominal AC power, scaled with AC/nominal.
    public var acOhmicAtNominal = 0.005
    public var unavailability = 0.01
    public init() {}
}

/// String layout, for the MPPT current limit: when there are more strings than MPPTs, the extra ones double up and
/// each MPPT shares its operating current limit between two strings.
public struct StringDesign: Codable, Sendable, Equatable {
    public var modulesPerString: Int
    public var strings: Int
    public init(modulesPerString: Int, strings: Int) { self.modulesPerString = modulesPerString; self.strings = strings }
}

/// Far obstacles as (azimuth from north, elevation) pairs in degrees: the beam is cut while the sun is below the
/// profile, and the sky diffuse loses the blocked share of the sky (isotropic).
public struct HorizonProfile: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public var azimuth: Double, elevation: Double
        public init(azimuth: Double, elevation: Double) { self.azimuth = azimuth; self.elevation = elevation }
    }
    public var points: [Point]
    public init(_ points: [Point]) { self.points = points }
    public init(pairs: [(Double, Double)]) { points = pairs.map { Point(azimuth: $0.0, elevation: $0.1) } }

    /// The profile's elevation at an azimuth: periodic linear interpolation (numpy `interp(..., period=360)`).
    public func elevation(at azimuth: Double) -> Double {
        let pts = points.map { (a: ($0.azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360), e: $0.elevation) }
            .sorted { $0.a < $1.a }
        guard let first = pts.first, let last = pts.last else { return 0 }
        let x = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let ext = [(a: last.a - 360, e: last.e)] + pts + [(a: first.a + 360, e: first.e)]
        for k in 1..<ext.count where x <= ext[k].a {
            let a = ext[k - 1], b = ext[k]
            return b.a == a.a ? b.e : a.e + (b.e - a.e) * (x - a.a) / (b.a - a.a)
        }
        return last.e
    }

    /// Share of the tilted plane's isotropic sky the profile hides: mean sin²(h) over the horizon, over the plane's
    /// sky view (1 + cos β)/2.
    public func skyFactor(tilt: Double) -> Double {
        var blocked = 0.0
        for a in 0..<360 { let s = sin(elevation(at: Double(a)) * .pi / 180); blocked += s * s }
        blocked /= 360
        return max(0, 1 - blocked / ((1 + cos(tilt * .pi / 180)) / 2))
    }
}

/// One roof face or array block with its own orientation and shading (the reference's `Face`).
public struct ArrayFace: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var moduleCount: Int
    public var tiltDeg: Double
    /// Compass bearing the face looks to: 0 = N, 90 = E, 180 = S (the spec's canonical form, same as pvlib).
    public var azimuthDegTrueN: Double
    /// Annual near-shading loss from the survey, applied to all front light.
    public var nearShadingLossFrac: Double
    public var horizon: HorizonProfile?
    /// Overrides the system's Uc (W/m²K) for this face.
    public var uc: Double?
    /// Hour by hour along the sun track (0–1): the share of the face's modules in the shadow of something standing on
    /// the roof (C1's obstacles), which takes that share of the beam; nil is none.
    public var beamShadeHourly: [Double]?
    public init(id: String, moduleCount: Int, tiltDeg: Double, azimuthDegTrueN: Double, nearShadingLossFrac: Double = 0,
                horizon: HorizonProfile? = nil, uc: Double? = nil, beamShadeHourly: [Double]? = nil) {
        self.id = id; self.moduleCount = moduleCount; self.tiltDeg = tiltDeg; self.azimuthDegTrueN = azimuthDegTrueN
        self.nearShadingLossFrac = nearShadingLossFrac; self.horizon = horizon; self.uc = uc
        self.beamShadeHourly = beamShadeHourly
    }
}

/// Rows of racks on flat ground or a flat roof (the reference's `RowGeometry`): turns on row-to-row shading of the
/// front (linear beam shading × an electrical factor, the sky the next row leaves, the shaded ground between rows,
/// pvlib infinite sheds), and gives a bifacial rear side its geometry.
public struct RowGeometry: Codable, Sendable, Equatable {
    /// Module length across the row (m): 2 in portrait is 2 × 2.278 + 0.02.
    public var slantM = 4.576
    /// Lowest module edge above the ground (m).
    public var clearanceM = 0.60
    /// Row pitch (m); nil takes `designPitch`, no row shading 09:00–15:00 on 21 December.
    public var pitchM: Double?
    /// Ground under the rows: grass ≈ 0.2, bare soil 0.15–0.25, white gravel ≈ 0.4.
    public var albedo = 0.20
    /// 1 = linear; above 1 approximates the string-level loss of a partial shadow.
    public var electricalFactor = 1.0
    public init(slantM: Double = 4.576, clearanceM: Double = 0.60, pitchM: Double? = nil, albedo: Double = 0.20,
                electricalFactor: Double = 1.0) {
        self.slantM = slantM; self.clearanceM = clearanceM; self.pitchM = pitchM; self.albedo = albedo
        self.electricalFactor = electricalFactor
    }

    /// Height of the row's centre above the ground (m).
    public func heightM(tiltDeg: Double) -> Double { clearanceM + 0.5 * slantM * sin(tiltDeg * .pi / 180) }

    /// The reference's `design_pitch`: the pitch at which the row behind is just unshaded at `localHour` (and its
    /// mirror in the afternoon) on 21 December 2026, at the site, for rows facing `azimuthDegTrueN`.
    public static func designPitch(site: SolarPosition.Site, tiltDeg: Double, slantM: Double, azimuthDegTrueN: Double = 180,
                                   localHour: Double = 9, utcOffsetHours: Double = 7) -> Double {
        let midnight = 1_797_811_200.0   // 2026-12-21 00:00 UTC
        let p = SolarPosition.position(unix: midnight + (localHour - utcOffsetHours) * 3600, site: site)
        let alt = (90 - p.apparentZenith) * .pi / 180, rel = (p.azimuth - azimuthDegTrueN) * .pi / 180
        let b = tiltDeg * .pi / 180
        let rise = slantM * sin(b)
        return slantM * cos(b) + rise * abs(cos(rel)) / tan(alt)
    }
}

/// The bifacial rear side (the reference's `Bifacial`), pvlib infinite sheds as PVsyst's 2D bifacial model.
public struct BifacialRear: Codable, Sendable, Equatable {
    /// What the rear side looks at.
    public enum Frame: String, Codable, Sendable {
        /// Modules railed parallel to a pitched roof: the roof is the "ground", so the sun is turned into the roof's
        /// plane first, and the rows run across the slope.
        case roof
        /// Racks on flat ground or a flat roof, at the face's tilt.
        case ground
    }
    /// Znshine datasheet: 80 ± 10 %.
    public var bifaciality = 0.80
    /// The surface under the array (coloured metal sheet ≈ 0.3).
    public var albedo = 0.30
    /// Rear surface centre above that surface, the row pitch along it and the module length across the row (m).
    public var heightM = 0.12, pitchM = 2.30, moduleSlantM = 2.278
    /// Module tilt relative to that surface (roof frame only).
    public var tiltRelDeg = 0.0
    public var frame = Frame.roof
    /// Mismatch from the uneven light on the rear.
    public var rearMismatch = 0.10
    public init(bifaciality: Double = 0.80, albedo: Double = 0.30, heightM: Double = 0.12, pitchM: Double = 2.30,
                moduleSlantM: Double = 2.278, tiltRelDeg: Double = 0, frame: Frame = .roof, rearMismatch: Double = 0.10) {
        self.bifaciality = bifaciality; self.albedo = albedo; self.heightM = heightM; self.pitchM = pitchM
        self.moduleSlantM = moduleSlantM; self.tiltRelDeg = tiltRelDeg; self.frame = frame; self.rearMismatch = rearMismatch
    }
}

/// PVsyst-style P50/P90 components, 1 σ fractions (degradation excluded).
public struct YieldUncertainty: Codable, Sendable, Equatable {
    /// Year-to-year climate; PVGIS SD_y at Bangkok ≈ 2 %.
    public var climateIAV = 0.020
    /// 0.05 when scaled to Solargis / GSA, 0.08 for ERA5 as it is.
    public var meteoData = 0.08
    public var pvModuleModel = 0.01
    public var moduleQuality = 0.01
    public var soilingMismatch = 0.01
    public var inverter = 0.005
    public var unmodelledShading = 0.02
    public init(meteoData: Double = 0.08) { self.meteoData = meteoData }

    var others: [Double] { [meteoData, pvModuleModel, moduleQuality, soilingMismatch, inverter, unmodelledShading] }
    /// σ of one year, and of the mean of `years` years.
    public func sigma(years: Double = 1) -> Double {
        (pow(climateIAV / years.squareRoot(), 2) + others.reduce(0) { $0 + $1 * $1 }).squareRoot()
    }
}

/// The array, its inverters and assumptions: what `YieldEngine` runs over a `SunTrack`.
public struct YieldSystem: Sendable, Equatable {
    public var module: PVModuleSpec
    public var inverter: InverterSpec
    /// Identical inverters sharing the array's DC power evenly.
    public var inverterCount: Int
    /// nil skips the MPPT current limit (no string design yet).
    public var design: StringDesign?
    public var faces: [ArrayFace]
    public var losses = YieldLosses()
    public var thermal = ThermalModel()
    public var uncertainty = YieldUncertainty()
    /// Linear module ageing per year after LID (PVsyst, mid-year): Znshine warranty 0.40 %/yr.
    public var ageingPerYear = 0.004
    public var years = 25
    public var acLimit: InverterEfficiencyModel.ACLimit = .nominalPower
    /// Rows on flat ground or a flat roof: row-to-row shading on every face, and the rear side's geometry.
    public var rows: RowGeometry?
    /// The bifacial rear side; nil is monofacial. With `rows`, the rear sees the rows' ground (their pitch, height
    /// and albedo); without, its own geometry in its frame.
    public var bifacial: BifacialRear?

    public init(module: PVModuleSpec, inverter: InverterSpec, inverterCount: Int = 1, design: StringDesign? = nil,
                faces: [ArrayFace]) {
        self.module = module; self.inverter = inverter; self.inverterCount = max(1, inverterCount)
        self.design = design; self.faces = faces
    }

    public var moduleCount: Int { faces.reduce(0) { $0 + $1.moduleCount } }
    /// kWp at STC.
    public var dcKWp: Double { Double(moduleCount) * module.stc.pNomW / 1000 }
    public var acKW: Double { Double(inverterCount) * inverter.acNominalPowerW / 1000 }
}


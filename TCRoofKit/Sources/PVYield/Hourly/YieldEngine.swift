import Foundation

/// The PVsyst-style hourly chain of tools/yield-reference/reference_engine.py (`run_array` and `run`), for front-lit
/// arrays on one or more faces:
///
///     sun (SPA, hour-effective) ─► Perez POA ─► IAM (ASHRAE, Marion diffuse) ─► horizon, near shading ─► soiling
///     ─► PVsyst cell temperature ─► one-diode MPP ─► quality, LID, mismatch ─► DC ohmic ─► MPPT current limit
///     ─► inverter efficiency ─► clipping ─► AC ohmic ─► unavailability, night consumption ─► E_grid
///
/// then PR, the monthly table, PVsyst ageing and P50/P90. Not ported yet: the bifacial rear side and row-to-row
/// shading (pvlib infinite sheds), so `YieldSystem` has no rows or rear gain.
///
/// Pure and synchronous: run it off the main thread. A year on one face takes tens of milliseconds (release).
public enum YieldEngine {
    /// What one face gives up to the inverter input, hour by hour.
    struct FaceRun {
        var face: ArrayFace
        var poa: [Double], gEff: [Double], tCell: [Double], pMpp: [Double], pDcIn: [Double]
        var sunny: [Bool], over: [Bool]
        var e: FaceEnergies
    }

    struct FaceEnergies {
        var hInc = 0.0, hIAM = 0.0, hShade = 0.0, hFrontEff = 0.0
        var eNominal = 0.0, eIrrLevel = 0.0, eTemp = 0.0, eQuality = 0.0, eArrMpp = 0.0, eCurrentLimit = 0.0
    }

    public static func run(_ system: YieldSystem, track: SunTrack, hourly keepHourly: Bool = false) -> YieldResult {
        let model = PVsystSingleDiodeModel(spec: system.module)
        let n = track.hours.count
        let parts = system.faces.map { runFace($0, system: system, model: model, track: track) }
        let nMod = Double(system.moduleCount), pNomDC = nMod * system.module.stc.pNomW
        let weights = parts.map { Double($0.face.moduleCount) / nMod }
        let inv = system.inverter, count = Double(system.inverterCount), L = system.losses
        let cap = (system.acLimit == .nominalPower ? inv.acNominalPowerW : inv.acMaxApparentPowerVA) * count

        var dcIn = [Double](repeating: 0, count: n), poaW = dcIn, gEffW = dcIn, tCellW = dcIn, pModW = dcIn
        var acFree = dcIn, ac = dcIn, acOhm = dcIn, grid = dcIn
        var sunny = [Bool](repeating: false, count: n), over = sunny, clipped = sunny
        for (w, p) in zip(weights, parts) {
            for k in 0..<n {
                dcIn[k] += p.pDcIn[k]; poaW[k] += w * p.poa[k]; gEffW[k] += w * p.gEff[k]
                tCellW[k] += w * p.tCell[k]; pModW[k] += w * p.pMpp[k]
                if p.sunny[k] { sunny[k] = true }
                if p.over[k] { over[k] = true }
            }
        }
        let lm = inv.lossModel
        for k in 0..<n {
            // every inverter takes an equal share of the array
            let dc = dcIn[k] / count
            let free = dc > 0 ? count * dc * InverterEfficiencyModel.efficiency(atLoad: dc / lm.pDC0W, lm) : 0
            acFree[k] = free
            clipped[k] = free > cap
            ac[k] = clipped[k] ? cap : free
            acOhm[k] = ac[k] * (1 - L.acOhmicAtNominal * ac[k] / (count * inv.acNominalPowerW))
            grid[k] = acOhm[k] * (1 - L.unavailability) - (sunny[k] ? 0 : inv.nightConsumptionW * count)
        }

        func kwh(_ x: [Double]) -> Double { x.reduce(0, +) / 1000 }
        func weighted(_ f: (FaceEnergies) -> Double) -> Double { zip(weights, parts).reduce(0) { $0 + $1.0 * f($1.1.e) } }
        func summed(_ f: (FaceEnergies) -> Double) -> Double { parts.reduce(0) { $0 + f($1.e) } }
        var e = YieldEnergies()
        e.hHor = kwh(track.hours.map(\.ghi))
        e.hInc = weighted(\.hInc); e.hIAM = weighted(\.hIAM); e.hShade = weighted(\.hShade)
        e.hFrontEff = weighted(\.hFrontEff); e.hEff = e.hFrontEff
        e.eNominal = summed(\.eNominal); e.eAfterIrrLevel = summed(\.eIrrLevel); e.eAfterTemp = summed(\.eTemp)
        e.eAfterQualityLidMismatch = summed(\.eQuality); e.eArrMpp = summed(\.eArrMpp)
        e.eAfterCurrentLimit = summed(\.eCurrentLimit)
        e.eAfterInvEff = kwh(acFree); e.eAfterClipping = kwh(ac); e.eAfterACOhmic = kwh(acOhm); e.eGrid = kwh(grid)

        var monthly: [YieldResult.Month] = []
        for m in 1...12 {
            var ghi = 0.0, poa = 0.0, eg = 0.0
            for k in 0..<n where track.hours[k].month == m { ghi += track.hours[k].ghi; poa += poaW[k]; eg += grid[k] }
            monthly.append(.init(month: m, ghi: ghi / 1000, poa: poa / 1000, eGrid: eg / 1000,
                                 pr: poa > 0 ? (eg / 1000) / (pNomDC / 1000 * poa / 1000) : 0))
        }
        var daylight = 0.0, daylightN = 0
        for k in 0..<n where poaW[k] > 100 { daylight += tCellW[k]; daylightN += 1 }
        let hours = YieldResult.HourStats(currentLimited: over.filter { $0 }.count, clipped: clipped.filter { $0 }.count,
                                          maxDCkW: (dcIn.max() ?? 0) / 1000,
                                          tCellMeanDaylight: daylightN > 0 ? daylight / Double(daylightN) : 0,
                                          tCellMax: tCellW.max() ?? 0)
        let faces = parts.map { p in
            YieldResult.Face(id: p.face.id, modules: p.face.moduleCount, tiltDeg: p.face.tiltDeg, azimuthDegTrueN: p.face.azimuthDegTrueN,
                             hInc: p.e.hInc, hShade: p.e.hShade, eDCIn: p.e.eCurrentLimit,
                             dcYield: p.e.eCurrentLimit / (Double(p.face.moduleCount) * system.module.stc.pNomW / 1000))
        }
        let hourly = keepHourly ? YieldResult.Hourly(poa: poaW, gEff: gEffW, tCell: tCellW, pModule: pModW, pDCIn: dcIn, pAC: ac, pGrid: grid) : nil
        return YieldResult(system: system, energies: e, monthly: monthly, hours: hours, faces: faces, hourly: hourly,
                           weatherSource: track.weatherSource)
    }

    /// The reference's `run_array`: one face up to the inverter's DC input.
    static func runFace(_ face: ArrayFace, system: YieldSystem, model: PVsystSingleDiodeModel, track: SunTrack) -> FaceRun {
        let L = system.losses, spec = system.module, s = spec.stc, n = track.hours.count
        let tilt = face.tiltDeg, az = face.azimuthDegTrueN
        let diffuse = IAM.marionDiffuse(tilt: tilt, b0: L.iamB0)
        let skyFactor = face.horizon?.skyFactor(tilt: tilt) ?? 1
        var thermal = system.thermal
        if let uc = face.uc { thermal.uc = uc }
        let area = spec.dimensions.map { $0.widthM * $0.heightM } ?? (s.pNomW / 1000 / 0.21)
        let eta = s.pNomW / (area * 1000)
        let nMod = Double(face.moduleCount)
        let kq = (1 - L.moduleQuality) * (1 - L.lid) * (1 - L.mismatch)

        // MPPT current limit: strings beyond one per MPPT double up on `two` MPPTs, which share its operating limit
        var two = 0, shareTwo = 0.0
        let iLimit = system.inverter.maxInputCurrentPerMpptA / 2
        if let d = system.design {
            let mppts = system.inverter.mpptCount * system.inverterCount
            two = d.strings > mppts ? max(0, min(mppts, d.strings - mppts)) : 0
            shareTwo = min(1, Double(two * 2 * d.modulesPerString) / nMod)
        }

        var r = FaceRun(face: face, poa: .init(repeating: 0, count: n), gEff: .init(repeating: 0, count: n),
                        tCell: .init(repeating: 0, count: n), pMpp: .init(repeating: 0, count: n),
                        pDcIn: .init(repeating: 0, count: n), sunny: .init(repeating: false, count: n),
                        over: .init(repeating: false, count: n), e: FaceEnergies())
        var e = FaceEnergies()
        for k in 0..<n {
            let h = track.hours[k]
            let poa = Irradiance.planeOfArray(tilt: tilt, azimuth: az, albedo: L.albedo, hour: h)
            let iamBeam = IAM.ashrae(aoi: poa.aoi, b0: L.iamB0)
            let gIAM = poa.direct * iamBeam + poa.sky * diffuse.sky + poa.ground * diffuse.ground
            var beam = poa.direct, sky = poa.sky
            if let hz = face.horizon {
                if 90 - h.zenith <= hz.elevation(at: h.azimuth) { beam = 0 }
                sky *= skyFactor
            }
            let gShade = (beam * iamBeam + sky * diffuse.sky + poa.ground * diffuse.ground) * (1 - face.nearShadingLossFrac)
            let g = gShade * (1 - L.soiling)
            let tc = thermal.cellTemperature(poaGlobal: poa.global, airTemp: h.tempAir, wind: h.windSpeed, moduleEfficiency: eta)
            r.poa[k] = poa.global; r.gEff[k] = g; r.tCell[k] = tc
            e.hInc += poa.global; e.hIAM += gIAM; e.hShade += gShade; e.hFrontEff += g
            e.eNominal += s.pNomW * g / 1000
            guard g > 0.5 else { continue }
            r.sunny[k] = true
            let params = model.parameters(effectiveIrradiance: g, cellTempC: tc)
            let mpp = PVsystSingleDiodeModel.maxPowerPoint(params)
            let p25 = model.maxPowerPoint(effectiveIrradiance: g, cellTempC: 25).p
            r.pMpp[k] = mpp.p
            e.eIrrLevel += p25; e.eTemp += mpp.p
            let ohm = mpp.v > 0 ? L.dcOhmicAtSTC * (mpp.i / s.impA) * (s.vmpV / mpp.v) : 0
            var pLim = mpp.p
            if two > 0 && mpp.i > iLimit {
                r.over[k] = true
                pLim = PVsystSingleDiodeModel.voltage(atCurrent: iLimit, params) * iLimit
            }
            let pEff = shareTwo * pLim + (1 - shareTwo) * mpp.p
            e.eArrMpp += nMod * mpp.p * kq * (1 - ohm)
            r.pDcIn[k] = nMod * pEff * kq * (1 - ohm)
            e.eCurrentLimit += r.pDcIn[k]
        }
        // to kWh (W·h sums over 1 h steps); per-module sums times the face's modules
        e.hInc /= 1000; e.hIAM /= 1000; e.hShade /= 1000; e.hFrontEff /= 1000
        e.eNominal *= nMod / 1000; e.eIrrLevel *= nMod / 1000; e.eTemp *= nMod / 1000
        e.eQuality = e.eTemp * kq
        e.eArrMpp /= 1000; e.eCurrentLimit /= 1000
        r.e = e
        return r
    }
}

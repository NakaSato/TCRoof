import Foundation

/// The year's energy at each step of the chain, kWh (H_* in kWh/m², module-weighted over the faces). Coding keys
/// are the reference's `energies_kWh` names, so a golden file decodes into it.
public struct YieldEnergies: Codable, Sendable, Equatable {
    public var hHor = 0.0, hInc = 0.0, hIAM = 0.0, hShade = 0.0, hFrontEff = 0.0, hEff = 0.0
    public var eNominal = 0.0, eAfterIrrLevel = 0.0, eAfterTemp = 0.0, eAfterQualityLidMismatch = 0.0
    public var eArrMpp = 0.0, eAfterCurrentLimit = 0.0, eAfterInvEff = 0.0, eAfterClipping = 0.0
    public var eAfterACOhmic = 0.0, eGrid = 0.0

    enum CodingKeys: String, CodingKey {
        case hHor = "H_hor", hInc = "H_inc", hIAM = "H_iam", hShade = "H_shade", hFrontEff = "H_front_eff", hEff = "H_eff"
        case eNominal = "E_nominal", eAfterIrrLevel = "E_after_irr_level", eAfterTemp = "E_after_temp"
        case eAfterQualityLidMismatch = "E_after_quality_lid_mm", eArrMpp = "E_arr_mpp"
        case eAfterCurrentLimit = "E_after_current_limit", eAfterInvEff = "E_after_inv_eff"
        case eAfterClipping = "E_after_clipping", eAfterACOhmic = "E_after_ac_ohmic", eGrid = "E_grid"
    }
    public init() {}
}

public struct YieldResult: Sendable {
    public struct Month: Sendable, Equatable {
        public var month: Int
        /// kWh/m² and kWh.
        public var ghi: Double, poa: Double, eGrid: Double
        public var pr: Double
    }

    public struct HourStats: Sendable, Equatable {
        public var currentLimited: Int, clipped: Int
        public var maxDCkW: Double
        /// Mean cell temperature over hours with POA > 100 W/m², and the year's maximum (°C).
        public var tCellMeanDaylight: Double, tCellMax: Double
    }

    public struct Face: Sendable, Equatable {
        public var id: String
        public var modules: Int
        public var tiltDeg: Double, azimuthDegTrueN: Double
        /// kWh/m² on the plane, and after IAM, horizon and near shading.
        public var hInc: Double, hShade: Double
        /// kWh at the inverter input, and per kWp.
        public var eDCIn: Double, dcYield: Double
    }

    public struct Hourly: Sendable {
        /// W/m² (module-weighted) and °C.
        public var poa: [Double], gEff: [Double], tCell: [Double]
        /// W: one module's MPP (weighted), the inverter input, AC after clipping, the grid.
        public var pModule: [Double], pDCIn: [Double], pAC: [Double], pGrid: [Double]
    }

    public struct Probability: Sendable, Equatable {
        public var sigma1yr: Double, sigma10yr: Double
        /// kWh, year 1.
        public var p50: Double, p90OneYear: Double, p90TenYear: Double, p99OneYear: Double
    }

    public var system: YieldSystem
    public var energies: YieldEnergies
    public var monthly: [Month]
    public var hours: HourStats
    public var faces: [Face]
    public var hourly: Hourly?
    public var weatherSource: String

    public var dcKWp: Double { system.dcKWp }
    public var dcAcRatio: Double { system.dcKWp / system.acKW }
    /// kWh/kWp.
    public var specificYield: Double { energies.eGrid / dcKWp }
    /// Performance ratio on the plane's irradiation (IEC 61724-1).
    public var performanceRatio: Double { energies.eGrid / (dcKWp * energies.hInc) }

    /// E_grid of years 1…n, PVsyst ageing: linear, mid-year (year n loses rate × (n − 0.5)); LID is already in
    /// year 1.
    public var ageing: [Double] {
        (1...max(1, system.years)).map { energies.eGrid * (1 - system.ageingPerYear * (Double($0) - 0.5)) }
    }

    /// P50 = E_grid; P90 / P99 from the combined σ (1.2816 σ and 2.3263 σ).
    public var probability: Probability {
        let s1 = system.uncertainty.sigma(), s10 = system.uncertainty.sigma(years: 10), p50 = energies.eGrid
        return Probability(sigma1yr: s1, sigma10yr: s10, p50: p50, p90OneYear: p50 * (1 - 1.2816 * s1),
                           p90TenYear: p50 * (1 - 1.2816 * s10), p99OneYear: p50 * (1 - 2.3263 * s1))
    }

    public struct LossStep: Sendable, Equatable {
        public var label: String
        /// % change over the step.
        public var percent: Double
    }

    /// The loss diagram, in the reference's order and labels.
    public var lossDiagram: [LossStep] {
        let e = energies
        func pct(_ a: Double, _ b: Double) -> Double { a > 0 ? (b / a - 1) * 100 : 0 }
        return [
            .init(label: "Transposition gain (Perez)", percent: pct(e.hHor, e.hInc)),
            .init(label: String(format: "IAM (ASHRAE b0=%.2f)", system.losses.iamB0), percent: pct(e.hInc, e.hIAM)),
            .init(label: "Shading (horizon, near, row-to-row)", percent: pct(e.hIAM, e.hShade)),
            .init(label: "Soiling", percent: pct(e.hShade, e.hFrontEff)),
            .init(label: "PV loss due to irradiance level", percent: pct(e.eNominal, e.eAfterIrrLevel)),
            .init(label: "PV loss due to temperature", percent: pct(e.eAfterIrrLevel, e.eAfterTemp)),
            .init(label: "Module quality + LID + mismatch", percent: pct(e.eAfterTemp, e.eAfterQualityLidMismatch)),
            .init(label: "DC ohmic wiring", percent: pct(e.eAfterQualityLidMismatch, e.eArrMpp)),
            .init(label: "MPPT current limit", percent: pct(e.eArrMpp, e.eAfterCurrentLimit)),
            .init(label: "Inverter efficiency", percent: pct(e.eAfterCurrentLimit, e.eAfterInvEff)),
            .init(label: "Clipping (AC \(system.acLimit == .nominalPower ? "nominal" : "max_apparent"))", percent: pct(e.eAfterInvEff, e.eAfterClipping)),
            .init(label: "AC ohmic", percent: pct(e.eAfterClipping, e.eAfterACOhmic)),
            .init(label: "Unavailability + night consumption", percent: pct(e.eAfterACOhmic, e.eGrid)),
        ]
    }
}

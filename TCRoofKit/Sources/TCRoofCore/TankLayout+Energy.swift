import Foundation

/// `หาผังที่ได้พลังงานมากที่สุด` (docs/specs/tank-mounting-layout.md §3a): the layout scored by its energy a year
/// instead of its module count. Rows keep following the tank walls (the team rule); for each row gap from the
/// standard's 2.70 m up to 2.00 m wider, in 0.20 m steps, the offsets with the most modules are kept (`best`), and the
/// gap whose layout makes the most MWh a year after the shade of the row in front and of what stands beside the tank
/// (`TankShade`) wins. A tie keeps the narrower gap. Gaps under the standard are never tried.
extension TankLayout {
    /// One row gap tried.
    public struct GapTrial: Hashable, Sendable {
        public var gap: Double
        public var params: Params
        public var modules: Int
        public var kWp: Double
        /// MWh a year after both shades, and the share lost to the row in front.
        public var mwh: Double
        public var rowLoss: Double
    }

    public struct EnergySearch: Sendable {
        /// Every gap tried, narrowest first.
        public var trials: [GapTrial]
        /// The winner.
        public var chosen: GapTrial
        public var params: Params { chosen.params }
        /// `ลองระยะห่างแถว 11 แบบ | เลือก 2.70 ม. | 352.0 MWh/ปี`
        public var line: String {
            String(format: "ลองระยะห่างแถว %d แบบ | เลือก %.2f ม. | %.1f MWh/ปี", trials.count, chosen.gap, chosen.mwh)
                + (chosen.gap > chosen.params.standardGap + 1e-6 ? " (กว้างกว่ามาตรฐาน)" : "")
        }
    }

    /// The gaps tried: the standard, then 0.20 m wider each, up to 2.00 m wider.
    public static func gapSteps(_ standard: Double = 2.7) -> [Double] {
        (0...10).map { ((standard + Double($0) * 0.2) * 100).rounded() / 100 }
    }

    /// The search; nil without a tank size. The standard gap gets the full 5 cm offset search (so the result never
    /// has fewer modules than `best` and never less energy than its layout), the wider ones the spec's coarser pass
    /// (rows 0.20 m, columns 0.10 m), and a wider winner is searched again on the 5 cm grid. The year is sampled more
    /// coarsely than `TankShade` (every 6th day, half hours), which ranks the gaps the same.
    public static func bestEnergy(_ v: Values, latitude: Double, base: Params? = nil) -> EnergySearch? {
        let base = base ?? defaults(v)
        guard TankPoints.tankSize(v) != nil else { return nil }
        let objects = TankShade.objects(v), az = Tank.azimuth(v).map(Double.init), exposed = Tank.exposed(v) ?? 0
        var yields: [Int: Double] = [:]
        func trial(_ g: Double, fine: Bool) -> GapTrial? {
            var b = base; b.rowGap = g
            guard let p = fine ? best(v, base: b) : best(v, base: b, stepX: 0.1, stepY: 0.2), let l = TankLayout(v, params: p) else { return nil }
            guard l.count > 0 else { return GapTrial(gap: g, params: p, modules: 0, kWp: 0, mwh: 0, rowLoss: 0) }
            let sim = TankShade.Sim(layout: l, objects: objects, azimuth: az, exposed: exposed)
            let r = sim.run(latitude: latitude, dayStep: 6, minutes: 30)
            let y = yields[l.turn] ?? l.yield(latitude: latitude, facing: sim.facing)
            yields[l.turn] = y
            return GapTrial(gap: g, params: p, modules: l.count, kWp: l.kWp, mwh: l.kWp * y / 1000 * (1 - r.rowLoss - r.objectLoss), rowLoss: r.rowLoss)
        }
        var trials = gapSteps(base.standardGap).enumerated().compactMap { trial($0.element, fine: $0.offset == 0) }
        guard var at = trials.indices.first else { return nil }
        for i in trials.indices.dropFirst() where trials[i].mwh > trials[at].mwh + 1e-9 { at = i }
        if at > 0, let fine = trial(trials[at].gap, fine: true), fine.mwh > trials[at].mwh { trials[at] = fine }
        return EnergySearch(trials: trials, chosen: trials[at])
    }
}

extension TankShade {
    /// MWh a year after the row shade and the objects.
    public var netMWh: Double { energy * (1 - totalLoss) }
}

import Foundation

/// The roof layout's quantities (docs/specs/roof-pv-layout.md §3.8), over the faces in use: what the report and the
/// Excel BOQ print.
public struct RoofMountQuantities: Equatable, Sendable {
    public var modules = 0
    public var kWp = 0.0
    /// MWh per year.
    public var energy = 0.0
    /// Rail metres, both rails of every run.
    public var railLength = 0.0
    public var splices = 0
    public var feet = 0
    public var midClamps = 0
    public var endClamps = 0
    public var runs = 0
    /// Module columns cut so no foot lands on an obstacle.
    public var cuts = 0
    /// Runs whose feet were moved off equal spacing.
    public var moved = 0
    /// Always 0: feet are never placed on an obstacle.
    public var feetOnObstacles = 0

    public init(_ layout: RoofMountLayout) {
        let s = layout.standard
        for f in layout.faces where f.used {
            modules += f.modules
            cuts += f.cuts
            energy += Double(f.modules) * s.moduleKW * f.yield / 1000
            for row in f.rows {
                for run in row.runs {
                    let lr = run.railLength, k = run.columns.count
                    runs += 1
                    railLength += 2 * lr
                    splices += 2 * (Int((lr / s.railStock).rounded(.up)) - 1)
                    feet += run.feet.reduce(0) { $0 + $1.count }
                    midClamps += 2 * (k - 1)
                    endClamps += 4
                    if run.moved { moved += 1 }
                }
            }
        }
        kWp = Double(modules) * s.moduleKW
    }
}

extension RoofMountLayout {
    public var quantities: RoofMountQuantities { RoofMountQuantities(self) }
}

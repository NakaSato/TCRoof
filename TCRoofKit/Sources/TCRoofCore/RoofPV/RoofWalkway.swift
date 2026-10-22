import Foundation

/// The walkways of C1's PV layout drawn as the team's walkway top view (docs/specs/cad-export-dxf, Walkways, after
/// `Walkway_S1.dxf`, measured): in each walkway gap (`RoofMountLayout.Options.walkwayEvery`, one module column up the
/// slope, or one down the middle of each face) a 0.90 m band across the gap with, from its cable-tray side, the 200 mm
/// cable tray, the HDG grating 0.30 × 2.40 × 0.03 m on L-feet every 1.20 m at both its edges, the 3/4" PPR pipe, the
/// rail and the 6 mm wire-rope lifeline on supports every 2.40 m.
public struct RoofWalkway: Sendable {
    public var face: RoofFace
    /// The gap's start along the eave and its width (a module's along the eave), and where it starts and ends up the
    /// slope (surface metres).
    public var u, width, v0, v1: Double

    /// Across the band, from its cable-tray side (metres; the band is centred in the gap), as `Walkway_S1.dxf` draws it.
    public static let band = 0.90, tray = (0.053, 0.253), grating = (0.325, 0.625), gratingFrame = 0.03, pipe = 0.656
    public static let rail = (0.687, 0.712), lifeline = 0.801
    /// Along the slope: grating panels, L-feet (the first 0.63 m in) and lifeline supports (the first 0.65 m in).
    public static let panel = 2.40, foot = 1.20, footStart = 0.63, support = 2.40, supportStart = 0.65
    /// The plan's tag at each walkway; the detail sheet beside the plan has the specification.
    public static let tag = "WALKWAY + LIFELINE (SEE DETAIL)"

    /// Where the band starts across the gap.
    public var b0: Double { u + (width - Self.band) / 2 }
    /// The grating panels' ends up the slope: whole 2.40 m panels, the last one cut to fit.
    public var panels: [(Double, Double)] {
        stride(from: v0, to: v1 - 1e-6, by: Self.panel).map { ($0, min($0 + Self.panel, v1)) }
    }
    public var feet: [Double] { Array(stride(from: v0 + Self.footStart, to: v1 - 1e-6, by: Self.foot)) }
    /// Every 2.40 m from 0.65 m in, as the top view spaces them; at least one.
    public var supports: [Double] {
        let s = Array(stride(from: v0 + min(Self.supportStart, (v1 - v0) / 2), to: v1 - 1e-6, by: Self.support))
        return s.isEmpty ? [(v0 + v1) / 2] : s
    }

    /// The walkway gaps of the faces in use: one per run of rows whose walkway slot in a column starts at the same u.
    public static func walkways(_ m: RoofMountLayout) -> [RoofWalkway] {
        var out: [RoofWalkway] = []
        let w = m.moduleAlong, l = m.moduleUp
        for f in m.faces where f.used {
            var open: [Int: RoofWalkway] = [:]
            var lastRow: [Int: Int] = [:]
            for (r, row) in f.rows.enumerated() {
                for (c, slot) in row.slots.enumerated() where slot.blocked == RoofMountLayout.walkway {
                    if var g = open[c], abs(g.u - slot.u) < 1e-6, lastRow[c] == r - 1 {
                        g.v1 = row.v + l; open[c] = g
                    } else {
                        if let g = open[c] { out.append(g) }
                        open[c] = RoofWalkway(face: f.face, u: slot.u, width: w, v0: row.v, v1: row.v + l)
                    }
                    lastRow[c] = r
                }
            }
            out += open.keys.sorted().compactMap { open[$0] }
        }
        return out
    }
}

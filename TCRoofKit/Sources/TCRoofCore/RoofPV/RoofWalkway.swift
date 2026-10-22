import Foundation

/// The walkways of C1's PV layout drawn as the team's walkway detail (docs/specs/cad-export-dxf, Walkways, after
/// `Walkway.dxf`): in each walkway gap (`RoofMountLayout.Options.walkwayEvery`, one module column up the slope) a
/// 0.90 m band across the gap with, from its lifeline side, the 6 mm wire rope on supports every 2.40 m, the rail, the
/// HDG grating 0.30 × 2.40 × 0.03 m on L-feet every 1.20 m, the 3/4" PPR pipe and the 200 mm cable tray.
public struct RoofWalkway: Sendable {
    public var face: RoofFace
    /// The gap's start along the eave and its width (a module's along the eave), and where it starts and ends up the
    /// slope (surface metres).
    public var u, width, v0, v1: Double

    /// Across the band, from its lifeline side (metres; the band is centred in the gap).
    public static let band = 0.90, lifeline = 0.05, rail = 0.12, grating = (0.17, 0.47), pipe = 0.505, tray = (0.54, 0.74)
    /// Along the slope: grating panels, L-feet and lifeline supports.
    public static let panel = 2.40, foot = 1.20, footStart = 0.60, support = 2.40
    /// The plan's tag at each walkway; the detail sheet beside the plan has the specification.
    public static let tag = "WALKWAY + LIFELINE (SEE DETAIL)"

    /// Where the band starts across the gap.
    public var b0: Double { u + (width - Self.band) / 2 }
    /// The grating panels' ends up the slope: whole 2.40 m panels, the last one cut to fit.
    public var panels: [(Double, Double)] {
        stride(from: v0, to: v1 - 1e-6, by: Self.panel).map { ($0, min($0 + Self.panel, v1)) }
    }
    public var feet: [Double] { Array(stride(from: v0 + Self.footStart, to: v1 - 1e-6, by: Self.foot)) }
    /// Every 2.40 m from the start, and one at the end.
    public var supports: [Double] {
        let s = Array(stride(from: v0, to: v1 - 1e-6, by: Self.support))
        return s + ((s.last.map { v1 - $0 > 0.3 } ?? true) ? [v1] : [])
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

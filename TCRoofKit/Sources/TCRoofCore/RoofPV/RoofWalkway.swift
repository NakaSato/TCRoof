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
    /// The walkway along the ridge, centred on it: `u` and `width` are then across it (v on `face`, half on each side
    /// of the ridge), `v0` and `v1` along it (u on `face`).
    public var ridge = false
    /// The one walkway the roof is reached by: it starts at the eave, where the access ladder stands beyond it.
    public var access = false

    /// Across the band, from its cable-tray side (metres; the band is centred in the gap), as `Walkway_S1.dxf` draws it.
    public static let band = 0.90, tray = (0.053, 0.253), grating = (0.325, 0.625), gratingFrame = 0.03, pipe = 0.656
    public static let rail = (0.687, 0.712), lifeline = 0.801
    /// Along the slope: grating panels, the cross rails with their L-feet every 1.20 m and the lifeline supports every
    /// 2.40 m, the first of each 0.646 m in (as `Walkway_S1.dxf` places them).
    public static let panel = 2.40, foot = 1.20, footStart = 0.646, support = 2.40, supportStart = 0.646
    /// A cross rail's width (the hat section), under the whole band.
    public static let railWidth = 0.024
    /// The plan's tag at each walkway; the detail sheet beside the plan has the specification.
    public static let tag = "WALKWAY + LIFELINE (SEE DETAIL)"
    /// The roof access: a cat ladder 0.45 m wide in line with the grating, its cage 0.75 m out from the eave on plan,
    /// rungs every 0.25 m.
    public static let ladderWidth = 0.45, ladderOut = 0.75, rung = 0.25
    public static let accessTag = "ROOF ACCESS LADDER + WALKWAY + LIFELINE (SEE DETAIL)"
    public static let accessNote = "ONE SIDE ONLY - SIDE TO BE CONFIRMED BY INSTALLER ON SITE"

    /// The ridge setback the centre walkways ask for: half the band and 50 mm.
    public static let ridgeClear = band / 2 + 0.05
    /// A ridge walkway's ends stop this far in from the verges (or hips).
    public static let ridgeInset = 0.50

    /// The plan point `a` across the band from its cable-tray side and `s` along the walkway.
    public func plan(_ a: Double, _ s: Double) -> Pt { ridge ? face.plan(s, b0 + a) : face.plan(b0 + a, s) }

    /// Where the band starts across the gap.
    public var b0: Double { u + (width - Self.band) / 2 }
    /// The grating panels' ends up the slope: whole 2.40 m panels, the last one cut to fit.
    public var panels: [(Double, Double)] {
        stride(from: v0, to: v1 - 1e-6, by: Self.panel).map { ($0, min($0 + Self.panel, v1)) }
    }
    /// The cross rails and their L-feet, up the slope.
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
            var mine = open.keys.sorted().compactMap { open[$0] }
            // down the middle, the walkway goes on past the top row up to the ridge (to the ridge walkway's edge)
            if m.options.walkwayCentre, let i = mine.indices.max(by: { mine[$0].v1 < mine[$1].v1 }) {
                let top = mine[i].ridgeEnd - (ridgeWalkway(m) == nil ? 0 : Self.band / 2)
                mine[i].v1 = max(mine[i].v1, top)
            }
            out += mine
        }
        // one side only: the lowest walkway of the face whose eave is at the plan's top (clear of the plan's title
        // below it) is the way up, from the eave
        let low = Dictionary(grouping: out.indices, by: { out[$0].face.id }).values.compactMap { $0.min { out[$0].v0 < out[$1].v0 } }
        if let i = low.min(by: { out[$0].eaveY < out[$1].eaveY }) {
            out[i].access = true
            out[i].v0 = min(out[i].v0, out[i].eaveEnd)
        }
        if let r = ridgeWalkway(m) { out.append(r) }
        return out
    }

    /// Down the middle on a roof with a ridge (not a shed): the walkway along the ridge, centred on it, from 0.50 m in
    /// from one end of the ridge to 0.50 m in from the other; nil when the ridge is shorter than a grating panel.
    public static func ridgeWalkway(_ m: RoofMountLayout) -> RoofWalkway? {
        guard m.options.walkwayCentre, m.faces.count > 1, m.faces.contains(where: \.used) else { return nil }
        let f = m.faces.map(\.face).first { $0.edges.contains(.ridge) && ($0.span(atV: $0.slopeLength).map { $0.1 - $0.0 } ?? 0) > 2 * ridgeInset + panel }
        guard let f, let (lo, hi) = f.span(atV: f.slopeLength) else { return nil }
        return RoofWalkway(face: f, u: f.slopeLength - band / 2, width: band, v0: lo + ridgeInset, v1: hi - ridgeInset, ridge: true)
    }

    /// The plan y (downwards) of the band's foot at the eave.
    var eaveY: Double { face.plan(b0 + Self.band / 2, eaveEnd).y }
    /// Where the band meets the eave: the lowest v inside the face across the whole band.
    public var eaveEnd: Double { max(edge(b0, top: false), edge(b0 + Self.band, top: false)) }

    /// How far up the slope the band can go inside the face: the ridge, or where a hip edge crosses the band.
    public var ridgeEnd: Double { min(edge(b0, top: true), edge(b0 + Self.band, top: true)) }

    /// The face's top (or bottom) v on the line at `x` along the eave.
    func edge(_ x: Double, top: Bool) -> Double {
        let p = face.polygon
        var vs: [Double] = []
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            guard (a.x - x) * (b.x - x) <= 0 else { continue }
            if abs(b.x - a.x) < 1e-12 { vs += [a.y, b.y] } else { vs.append(a.y + (x - a.x) / (b.x - a.x) * (b.y - a.y)) }
        }
        return (top ? vs.max() : vs.min()) ?? (top ? v1 : v0)
    }
}

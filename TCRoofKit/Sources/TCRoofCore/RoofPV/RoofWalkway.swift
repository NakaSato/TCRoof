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
    /// The one walkway the roof is reached by. On a gable roof it is the ridge walkway, reached by the cat ladder up the
    /// gable wall at the ridge (the team's top view: cage, ladder and a 0.60 × 1.00 m landing) at its start (`v0`) or end
    /// (`accessAtStart` false); elsewhere it is an up-slope walkway starting at the eave, with the ladder beyond it.
    public var access = false
    public var accessAtStart = true

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
    /// The ridge access (`Roof access Topview.dxf`): the cat ladder 0.60 m wide between its stiles, its cage R 0.30 m
    /// standing 0.90 m out from the gable wall, and the landing grating 0.60 × 0.98 m on the roof, framed 0.05 m.
    public static let gableLadder = 0.60, cageRadius = 0.30, cageOut = 0.90, landing = 0.98, landingFrame = 0.05
    public static let ridgeAccessTag = "ROOF ACCESS: CAT LADDER WITH CAGE + LANDING 0.60x1.00 (SEE TOP VIEW)"
    public static let ridgeAccessNote = "ONE SIDE ONLY (%@) - CONFIRM ON SITE"
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
                let top = mine[i].ridgeEnd - (ridgeWalkway(m).map { $0.width / 2 } ?? 0)
                mine[i].v1 = max(mine[i].v1, top)
            }
            out += mine
        }
        if var r = ridgeWalkway(m) {
            // a gable roof is reached up its gable wall at the ridge, on the side picked (left or right on plan)
            if r.face.edges.contains(.verge), let (lo, hi) = r.face.span(atV: r.face.slopeLength) {
                let a = r.face.plan(lo, r.face.slopeLength), b = r.face.plan(hi, r.face.slopeLength)
                // left on plan: the smaller x, or the lower end of a ridge drawn up the sheet (plan y runs down)
                let loIsLeft = abs(a.x - b.x) > 1e-6 ? a.x < b.x : a.y > b.y
                r.access = true
                r.accessAtStart = loIsLeft != m.options.walkwayAccessRight
                if r.accessAtStart { r.v0 = lo + Self.landing } else { r.v1 = hi - Self.landing }
                out.append(r)
                return out
            }
            out.append(r)
        }
        // otherwise one side only: the lowest walkway of the face whose eave is at the plan's top (clear of the plan's
        // title below it) is the way up, from the eave
        let low = Dictionary(grouping: out.indices.filter { !out[$0].ridge }, by: { out[$0].face.id }).values
            .compactMap { $0.min { out[$0].v0 < out[$1].v0 } }
        if let i = low.min(by: { out[$0].eaveY < out[$1].eaveY }) {
            out[i].access = true
            out[i].v0 = min(out[i].v0, out[i].eaveEnd)
        }
        return out
    }

    /// The gable wall's point at the ridge where the ladder stands (s along the ridge), for the ridge access.
    public var wallS: Double { accessAtStart ? v0 - Self.landing : v1 + Self.landing }

    /// Along the ridge, alone or with the walkways down the middle, on a roof with a ridge (not a shed): the walkway along the ridge, centred on it, from 0.50 m in
    /// from one end of the ridge to 0.50 m in from the other; nil when the ridge is shorter than a grating panel. Its
    /// width is the clear width chosen (`Options.ridgeWidth`, never under the band); the band stays centred in it.
    public static func ridgeWalkway(_ m: RoofMountLayout) -> RoofWalkway? {
        guard m.options.ridgeWalkway, m.faces.count > 1, m.faces.contains(where: \.used) else { return nil }
        let f = m.faces.map(\.face).first { $0.edges.contains(.ridge) && ($0.span(atV: $0.slopeLength).map { $0.1 - $0.0 } ?? 0) > 2 * ridgeInset + panel }
        guard let f, let (lo, hi) = f.span(atV: f.slopeLength) else { return nil }
        let width = m.options.ridgeWidth
        return RoofWalkway(face: f, u: f.slopeLength - width / 2, width: width, v0: lo + ridgeInset, v1: hi - ridgeInset, ridge: true)
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

/// The walkways' materials (the BOQ's walkway line): the walkways' length, the HDG grating panels (whole 2.40 m panels
/// and the cut last ones), the cross rails under them with two L-feet each, the lifeline's length and supports, the
/// cable tray and PPR pipe along them, and the roof access ladders (on a gable roof with its cage and landing).
public struct RoofWalkwayQuantities: Equatable, Sendable {
    public var walkways = 0
    public var length = 0.0
    public var gratings = 0, crossRails = 0, lFeet = 0
    public var lifeline = 0.0
    public var supports = 0
    public var tray = 0.0
    public var ladders = 0, cagedLadders = 0

    public init(_ ws: [RoofWalkway]) {
        walkways = ws.count
        for w in ws {
            let l = w.v1 - w.v0
            length += l; lifeline += l; tray += l
            gratings += w.panels.count
            crossRails += w.feet.count
            supports += w.supports.count
            if w.access { ladders += 1; if w.ridge { cagedLadders += 1 } }
        }
        lFeet = 2 * crossRails
    }
}

